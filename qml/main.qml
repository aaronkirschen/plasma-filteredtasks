/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import Qt.labs.settings as LabSettings
import QtCore

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

import org.kde.plasma.workspace.trianglemousefilter

import org.kde.taskmanager as TaskManager
import plasma.applet.org.kde.plasma.filteredtasks as TaskManagerApplet
import org.kde.plasma.workspace.dbus as DBus

import "layoutmetrics.js" as LayoutMetrics
import "tools.js" as TaskTools

PlasmoidItem {
    id: tasks

    // For making a bottom to top layout since qml flow can't do that.
    // We just hang the task manager upside down to achieve that.
    // This mirrors the tasks and group dialog as well, so we un-rotate them
    // to fix that (see Task.qml and GroupDialog.qml).
    rotation: Plasmoid.configuration.reverseMode && Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    readonly property bool shouldShrinkToZero: tasksModel.count === 0
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool iconsOnly: Plasmoid.pluginName === "org.kde.plasma.icontasks"
        || Plasmoid.pluginName === "org.kde.plasma.filteredtasks"

    property Task toolTipOpenedByClick
    property Task toolTipAreaItem

    // Live layout JSON — the single source of truth for this instance.
    // Set from the shared sync group in tools.js, or from local config if not syncing.
    property string _liveLayoutJson: ""

    // Live launchers JSON — tracks the last launcher list we sent/received via sync,
    // used to avoid feedback loops (same pattern as _liveLayoutJson).
    property string _liveLaunchersJson: ""

    // Live grouping blacklist JSON — tracks which apps have grouping disabled, synced like launchers.
    property string _liveGroupingBlacklistJson: ""

    // Parsed layout: mixed array of section and spacer items from config
    readonly property var parsedLayout: {
        var raw = _liveLayoutJson;
        if (!raw || raw.trim() === "") return [];
        try { return JSON.parse(raw); }
        catch (e) { return []; }
    }
    readonly property bool sectionedMode: parsedLayout.length > 0
    property alias taskRepeater: taskRepeater
    property alias sectionedLayout: sectionedLayout

    // Collect all claimed app IDs (from named sections, not unsectioned or spacers)
    readonly property var allClaimedAppIds: {
        var ids = [];
        for (var i = 0; i < parsedLayout.length; i++) {
            var item = parsedLayout[i];
            if (item.type !== "section" || item.name === "__unsectioned") continue;
            var appIds = item.appIds || [];
            for (var j = 0; j < appIds.length; j++) {
                ids.push(appIds[j]);
            }
        }
        return ids;
    }

    // ── Exclusive mode ──
    readonly property string _homeDir: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")
    readonly property string _claimsPath: _homeDir !== ""
        ? (_homeDir + "/.config/plasma-filteredtasks-claims.conf") : ""
    readonly property string _myInstanceId: String(Plasmoid.id)
    property var excludedByOthers: []

    LabSettings.Settings {
        id: claimsStore
        fileName: tasks._claimsPath
        category: "Claims"
    }

    function _writeClaims() {
        if (!_claimsPath || !Plasmoid.configuration.exclusiveMode) return;
        claimsStore.sync();
        var instances = String(claimsStore.value("instances", ""));
        var arr = instances ? instances.split(",") : [];
        if (arr.indexOf(_myInstanceId) < 0) arr.push(_myInstanceId);
        claimsStore.setValue("instances", arr.join(","));
        claimsStore.setValue("inst_" + _myInstanceId, allClaimedAppIds.join(","));
        claimsStore.sync();
    }

    function _readOtherClaims() {
        if (!_claimsPath || !Plasmoid.configuration.exclusiveMode) {
            excludedByOthers = [];
            return;
        }
        claimsStore.sync();
        var instances = String(claimsStore.value("instances", ""));
        var arr = instances ? instances.split(",") : [];
        var excluded = [];
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] === _myInstanceId) continue;
            var claimed = String(claimsStore.value("inst_" + arr[i], ""));
            if (!claimed) continue;
            var ids = claimed.split(",");
            for (var j = 0; j < ids.length; j++) {
                var id = ids[j].trim();
                if (id && excluded.indexOf(id) < 0) excluded.push(id);
            }
        }
        excludedByOthers = excluded;
    }

    Timer {
        id: claimsRefresh
        interval: 3000
        repeat: true
        running: Plasmoid.configuration.exclusiveMode && tasks._claimsPath !== ""
        onTriggered: {
            tasks._writeClaims();
            tasks._readOtherClaims();
            if (tasks.sectionedMode) sectionedLayout.reparentAllTasks();
        }
    }

    onAllClaimedAppIdsChanged: _writeClaims()

    // ── Sync group name registry (file-based, for cross-process discovery) ──
    readonly property string _syncNamesPath: _homeDir !== ""
        ? (_homeDir + "/.config/plasma-filteredtasks-syncgroups.conf") : ""

    LabSettings.Settings {
        id: syncNamesStore
        fileName: tasks._syncNamesPath
        category: "SyncGroups"
    }

    function _registerSyncGroupName(name) {
        if (!_syncNamesPath || !name) return;
        syncNamesStore.sync();
        var names = String(syncNamesStore.value("names", ""));
        var arr = names ? names.split("|").filter(function(n) { return n !== ""; }) : [];
        if (arr.indexOf(name) < 0) {
            arr.push(name);
            syncNamesStore.setValue("names", arr.join("|"));
        }
        // Also persist current layout so config dialogs (separate process) can read it
        syncNamesStore.setValue("layout_" + name, Plasmoid.configuration.taskSections);
        syncNamesStore.sync();
    }

    function _persistSyncGroupLayout(name, json) {
        if (!_syncNamesPath || !name) return;
        syncNamesStore.setValue("layout_" + name, json);
        syncNamesStore.sync();
    }

    function _unregisterSyncGroupName(name) {
        if (!_syncNamesPath || !name) return;
        // Only remove if no other live subscribers remain
        var liveNames = TaskTools.getSyncGroupNames();
        if (liveNames.indexOf(name) >= 0) return;
        syncNamesStore.sync();
        var names = String(syncNamesStore.value("names", ""));
        var arr = names ? names.split("|").filter(function(n) { return n !== ""; }) : [];
        arr = arr.filter(function(n) { return n !== name; });
        syncNamesStore.setValue("names", arr.join("|"));
        syncNamesStore.sync();
    }

    // ── Layout sync via shared tools.js state ──
    readonly property string _syncInstanceId: Math.random().toString(36).substring(2)
    property string _activeSyncGroup: ""

    function _joinSyncGroup() {
        var name = Plasmoid.configuration.syncGroup || "";
        if (_activeSyncGroup === name) return;
        var oldGroup = _activeSyncGroup;
        // Leave previous group
        if (_activeSyncGroup) TaskTools.leaveSyncGroup(_activeSyncGroup, _syncInstanceId);
        _activeSyncGroup = name;
        // Clean up old group name from file if nobody else is using it
        if (oldGroup) _unregisterSyncGroupName(oldGroup);
        if (!name) {
            // No sync group — use local config directly
            _liveLayoutJson = Plasmoid.configuration.taskSections;
            return;
        }
        // Join the group; returns existing layout, launchers, and grouping blacklist if another widget is already in it
        var localLaunchers = JSON.stringify(Plasmoid.configuration.launchers);
        var localBlacklist = _serializeGroupingBlacklist();
        var result = TaskTools.joinSyncGroup(name, _syncInstanceId,
            _onSyncLayoutChanged, Plasmoid.configuration.taskSections,
            _onSyncLaunchersChanged, localLaunchers,
            _onSyncGroupingBlacklistChanged, localBlacklist);
        // Adopt layout
        if (result.layout && result.layout !== "") {
            _liveLayoutJson = result.layout;
            Plasmoid.configuration.taskSections = result.layout;
        } else {
            _liveLayoutJson = Plasmoid.configuration.taskSections;
        }
        // Adopt launchers
        if (result.launchers && result.launchers !== "") {
            _liveLaunchersJson = result.launchers;
            var launcherList = JSON.parse(result.launchers);
            tasksModel.launcherList = launcherList;
            Plasmoid.configuration.launchers = launcherList;
        } else {
            _liveLaunchersJson = localLaunchers;
        }
        // Adopt grouping blacklist
        if (result.groupingBlacklist && result.groupingBlacklist !== "") {
            _liveGroupingBlacklistJson = result.groupingBlacklist;
            _applyGroupingBlacklist(result.groupingBlacklist);
        } else {
            _liveGroupingBlacklistJson = localBlacklist;
        }
        // Register name to file so config dialogs can discover it
        _registerSyncGroupName(name);
    }

    function _onSyncLayoutChanged(newJson) {
        _liveLayoutJson = newJson;
        Plasmoid.configuration.taskSections = newJson;
    }

    function _onSyncLaunchersChanged(newLaunchersJson) {
        _liveLaunchersJson = newLaunchersJson;
        var launcherList = JSON.parse(newLaunchersJson);
        tasksModel.launcherList = launcherList;
        Plasmoid.configuration.launchers = launcherList;
    }

    function _serializeGroupingBlacklist() {
        return JSON.stringify({
            appIds: Array.from(Plasmoid.configuration.groupingAppIdBlacklist),
            launcherUrls: Array.from(Plasmoid.configuration.groupingLauncherUrlBlacklist)
        });
    }

    function _applyGroupingBlacklist(json) {
        var data = JSON.parse(json);
        tasksModel.groupingAppIdBlacklist = data.appIds;
        tasksModel.groupingLauncherUrlBlacklist = data.launcherUrls;
        Plasmoid.configuration.groupingAppIdBlacklist = data.appIds;
        Plasmoid.configuration.groupingLauncherUrlBlacklist = data.launcherUrls;
    }

    function _onSyncGroupingBlacklistChanged(newJson) {
        if (!Plasmoid.configuration.syncGroupingBlacklist) return;
        _liveGroupingBlacklistJson = newJson;
        _applyGroupingBlacklist(newJson);
    }

    function _broadcastGroupingBlacklist() {
        if (!_activeSyncGroup || !Plasmoid.configuration.syncGroupingBlacklist) return;
        var json = _serializeGroupingBlacklist();
        if (json === _liveGroupingBlacklistJson) return;
        _liveGroupingBlacklistJson = json;
        TaskTools.updateSyncGroupGroupingBlacklist(_activeSyncGroup, json, _syncInstanceId);
    }

    Connections {
        target: Plasmoid.configuration
        function onSyncGroupChanged() { tasks._joinSyncGroup(); }
        function onExclusiveModeChanged() {
            tasks._readOtherClaims();
            if (tasks.sectionedMode) sectionedLayout.reparentAllTasks();
        }
        function onTaskSectionsChanged() {
            // Pick up external config changes (e.g. from config dialog Apply).
            // If _saveLayout or _onSyncLayoutChanged already set _liveLayoutJson
            // to this value, this is a no-op due to string comparison.
            var cfg = Plasmoid.configuration.taskSections;
            if (cfg !== tasks._liveLayoutJson) {
                tasks._liveLayoutJson = cfg;
                if (tasks._activeSyncGroup) {
                    TaskTools.updateSyncGroupLayout(tasks._activeSyncGroup, cfg, tasks._syncInstanceId);
                    tasks._persistSyncGroupLayout(tasks._activeSyncGroup, cfg);
                }
            }
        }
    }

    function _saveLayout(items) {
        var json = JSON.stringify(items);
        _liveLayoutJson = json;
        Plasmoid.configuration.taskSections = json;
        if (_activeSyncGroup) {
            TaskTools.updateSyncGroupLayout(_activeSyncGroup, json, _syncInstanceId);
            _persistSyncGroupLayout(_activeSyncGroup, json);
        }
    }

    function moveAppToSection(appId, fromLayoutIdx, toLayoutIdx) {
        var items = parsedLayout.slice();
        // Remove from old section
        if (fromLayoutIdx >= 0 && fromLayoutIdx < items.length && items[fromLayoutIdx].type === "section") {
            items[fromLayoutIdx] = Object.assign({}, items[fromLayoutIdx]);
            items[fromLayoutIdx].appIds = (items[fromLayoutIdx].appIds || []).filter(function(id) { return id !== appId; });
        }
        // Add to new section (unless it's unsectioned)
        if (toLayoutIdx >= 0 && toLayoutIdx < items.length && items[toLayoutIdx].type === "section" && items[toLayoutIdx].name !== "__unsectioned") {
            items[toLayoutIdx] = Object.assign({}, items[toLayoutIdx]);
            var ids = (items[toLayoutIdx].appIds || []).slice();
            if (ids.indexOf(appId) < 0) ids.push(appId);
            items[toLayoutIdx].appIds = ids;
        }
        _saveLayout(items);
    }

    function addAppToNewSection(appId, fromLayoutIdx, sectionName) {
        var name = (sectionName && sectionName.trim() !== "") ? sectionName.trim() : "New Section";
        var items = parsedLayout.slice();
        // Remove from old section
        if (fromLayoutIdx >= 0 && fromLayoutIdx < items.length && items[fromLayoutIdx].type === "section") {
            items[fromLayoutIdx] = Object.assign({}, items[fromLayoutIdx]);
            items[fromLayoutIdx].appIds = (items[fromLayoutIdx].appIds || []).filter(function(id) { return id !== appId; });
        }
        // Find unsectioned index to insert before it
        var insertIdx = items.length;
        for (var i = 0; i < items.length; i++) {
            if (items[i].type === "section" && items[i].name === "__unsectioned") {
                insertIdx = i;
                break;
            }
        }
        items.splice(insertIdx, 0, {type: "section", name: name, appIds: [appId], color: ""});
        _saveLayout(items);
    }

    function addSectionAt(layoutIndex, sectionName) {
        var name = (sectionName && sectionName.trim() !== "") ? sectionName.trim() : "New Section";
        var items = parsedLayout.slice();
        items.splice(layoutIndex, 0, {type: "section", name: name, appIds: [], color: ""});
        _saveLayout(items);
    }

    function addSpacerAt(layoutIndex) {
        var items = parsedLayout.slice();
        items.splice(layoutIndex, 0, {type: "spacer", width: 8});
        _saveLayout(items);
    }

    function updateSpacerWidth(layoutIndex, newWidth) {
        var spec = String(newWidth).trim();
        if (!spec) spec = "8";
        var items = parsedLayout.slice();
        if (layoutIndex >= 0 && layoutIndex < items.length && items[layoutIndex].type === "spacer") {
            // Store raw spec string for vw support; also store numeric width for backwards compat
            var px = resolveSpacerWidth(spec);
            items[layoutIndex] = {type: "spacer", width: px, widthSpec: spec};
            _saveLayout(items);
        }
    }

    function resolveSpacerWidth(spec) {
        var s = String(spec).trim().toLowerCase();
        var vwMatch = s.match(/^([0-9]*\.?[0-9]+)\s*vw$/);
        if (vwMatch) {
            var vw = parseFloat(vwMatch[1]);
            var screenW = Plasmoid.containment.screenGeometry.width || Screen.width || 1920;
            return Math.max(1, Math.round(screenW * vw / 100));
        }
        var px = Number(s);
        return (isNaN(px) || px < 1) ? 8 : Math.round(px);
    }

    function renameSection(layoutIndex, newName) {
        var items = parsedLayout.slice();
        if (layoutIndex >= 0 && layoutIndex < items.length && items[layoutIndex].type === "section") {
            items[layoutIndex] = Object.assign({}, items[layoutIndex]);
            items[layoutIndex].name = (newName && newName.trim() !== "") ? newName.trim() : items[layoutIndex].name;
            _saveLayout(items);
        }
    }

    function setSectionFloat(layoutIndex, floatValue) {
        var items = parsedLayout.slice();
        if (layoutIndex >= 0 && layoutIndex < items.length) {
            items[layoutIndex] = Object.assign({}, items[layoutIndex]);
            items[layoutIndex].float = floatValue;
            _saveLayout(items);
        }
    }

    function removeLayoutItem(layoutIndex) {
        var items = parsedLayout.slice();
        if (layoutIndex >= 0 && layoutIndex < items.length) {
            // If removing a section, its apps become unsectioned (just remove the section entry)
            items.splice(layoutIndex, 1);
        }
        _saveLayout(items);
    }

    readonly property Component inputDialogComponent: Qt.createComponent("InlineInputDialog.qml")

    readonly property Component contextMenuComponent: Qt.createComponent("ContextMenu.qml")
    readonly property Component pulseAudioComponent: Qt.createComponent("PulseAudio.qml")

    property bool needLayoutRefresh: false
    property /*list<WId> where WId = int|string*/ var taskClosedWithMouseMiddleButton: []
    property alias taskList: taskList

    preferredRepresentation: fullRepresentation

    Plasmoid.constraintHints: Plasmoid.CanFillArea

    Plasmoid.onUserConfiguringChanged: {
        if (Plasmoid.userConfiguring && groupDialog !== null) {
            groupDialog.visible = false;
        }
    }

    // In sectioned mode, always fill (float handles spacing); otherwise use config
    readonly property bool effectiveFill: sectionedMode ? true : Plasmoid.configuration.fill
    Layout.fillWidth: vertical ? true : effectiveFill
    Layout.fillHeight: !vertical ? true : effectiveFill
    Layout.minimumWidth: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        if (sectionedMode && !vertical) {
            return sectionedLayout.implicitWidth;
        }
        return vertical ? 0 : LayoutMetrics.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        if (sectionedMode && vertical) {
            return sectionedLayout.implicitHeight;
        }
        return !vertical ? 0 : LayoutMetrics.preferredMinHeight();
    }

//BEGIN TODO: this is not precise enough: launchers are smaller than full tasks
    Layout.preferredWidth: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            return Kirigami.Units.gridUnit * 10;
        }
        if (sectionedMode) {
            return sectionedLayout.implicitWidth;
        }
        return taskList.Layout.maximumWidth
    }
    Layout.preferredHeight: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            if (sectionedMode) {
                return sectionedLayout.implicitHeight;
            }
            return taskList.Layout.maximumHeight
        }
        return Kirigami.Units.gridUnit * 2;
    }
//END TODO

    property Item dragSource

    signal requestLayout

    onDragSourceChanged: {
        if (dragSource === null) {
            tasksModel.syncLaunchers();
        }
    }

    function windowsHovered(winIds: var, hovered: bool): DBus.DBusPendingReply {
        if (!Plasmoid.configuration.highlightWindows) {
            return;
        }
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.HighlightWindow", path: "/org/kde/KWin/HighlightWindow", iface: "org.kde.KWin.HighlightWindow", member: "highlightWindows", arguments: [hovered ? winIds : []], signature: "(as)"});
    }

    function cancelHighlightWindows(): DBus.DBusPendingReply {
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.HighlightWindow", path: "/org/kde/KWin/HighlightWindow", iface: "org.kde.KWin.HighlightWindow", member: "highlightWindows", arguments: [[]], signature: "(as)"});
    }

    function activateWindowView(winIds: var): DBus.DBusPendingReply {
        if (!effectWatcher.registered) {
            return;
        }
        cancelHighlightWindows();
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.Effect.WindowView1", path: "/org/kde/KWin/Effect/WindowView1", iface: "org.kde.KWin.Effect.WindowView1", member: "activate", arguments: [winIds.map(s => String(s))], signature: "(as)"});
    }

    function publishIconGeometries(taskItems: /*list<Item>*/var): void {
        if (TaskTools.taskManagerInstanceCount >= 2) {
            return;
        }
        for (let i = 0; i < taskItems.length - 1; ++i) {
            const task = taskItems[i];

            if (!task.model.IsLauncher && !task.model.IsStartup) {
                tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(task.index),
                    backend.globalRect(task), task);
            }
        }
    }

    readonly property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        id: tasksModel

        readonly property int logicalLauncherCount: {
            if (Plasmoid.configuration.separateLaunchers) {
                return launcherCount;
            }

            let startupsWithLaunchers = 0;

            for (let i = 0; i < taskRepeater.count; ++i) {
                const item = taskRepeater.itemAt(i);

                // During destruction required properties such as item.model can go null for a while,
                // so in paths that can trigger on those moments, they need to be guarded
                if (item?.model?.IsStartup && item.model.HasLauncher) {
                    ++startupsWithLaunchers;
                }
            }

            return launcherCount + startupsWithLaunchers;
        }

        virtualDesktop: virtualDesktopInfo.currentDesktop
        screenGeometry: Plasmoid.containment.screenGeometry
        activity: activityInfo.currentActivity

        filterByVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
        filterNotMinimized: Plasmoid.configuration.showOnlyMinimized

        hideActivatedLaunchers: tasks.iconsOnly || Plasmoid.configuration.hideLauncherOnStart
        sortMode: sortModeEnumValue(Plasmoid.configuration.sortingStrategy)
        launchInPlace: tasks.iconsOnly && Plasmoid.configuration.sortingStrategy === 1
        separateLaunchers: {
            if (!tasks.iconsOnly && !Plasmoid.configuration.separateLaunchers
                && Plasmoid.configuration.sortingStrategy === 1) {
                return false;
            }

            return true;
        }

        groupMode: groupModeEnumValue(Plasmoid.configuration.groupingStrategy)
        groupInline: !Plasmoid.configuration.groupPopups && !tasks.iconsOnly
        groupingWindowTasksThreshold: (Plasmoid.configuration.onlyGroupWhenFull && !tasks.iconsOnly
            ? LayoutMetrics.optimumCapacity(width, height) + 1 : -1)

        onLauncherListChanged: {
            Plasmoid.configuration.launchers = launcherList;
            var json = JSON.stringify(launcherList);
            if (tasks._activeSyncGroup && json !== tasks._liveLaunchersJson) {
                tasks._liveLaunchersJson = json;
                TaskTools.updateSyncGroupLaunchers(tasks._activeSyncGroup, json, tasks._syncInstanceId);
            }
        }

        onGroupingAppIdBlacklistChanged: {
            Plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist;
            tasks._broadcastGroupingBlacklist();
        }

        onGroupingLauncherUrlBlacklistChanged: {
            Plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
            tasks._broadcastGroupingBlacklist();
        }

        function sortModeEnumValue(index: int): /*TaskManager.TasksModel.SortMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.SortDisabled;
            case 1:
                return TaskManager.TasksModel.SortManual;
            case 2:
                return TaskManager.TasksModel.SortAlpha;
            case 3:
                return TaskManager.TasksModel.SortVirtualDesktop;
            case 4:
                return TaskManager.TasksModel.SortActivity;
            // 5 is SortLastActivated, skipped
            case 6:
                return TaskManager.TasksModel.SortWindowPositionHorizontal;
            default:
                return TaskManager.TasksModel.SortDisabled;
            }
        }

        function groupModeEnumValue(index: int): /*TaskManager.TasksModel.GroupMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.GroupDisabled;
            case 1:
                return TaskManager.TasksModel.GroupApplications;
            }
        }

        Component.onCompleted: {
            launcherList = Plasmoid.configuration.launchers;
            groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;

            // Only hook up view only after the above churn is done.
            taskRepeater.model = tasksModel;
        }
    }

    readonly property TaskManagerApplet.Backend backend: TaskManagerApplet.Backend {
        id: backend

        onAddLauncher: {
            tasks.addLauncher(url);
        }
    }

    DBus.DBusServiceWatcher {
        id: effectWatcher
        busType: DBus.BusType.Session
        watchedService: "org.kde.KWin.Effect.WindowView1"
    }

    readonly property Component taskInitComponent: Component {
        Timer {
            interval: 200
            running: true

            onTriggered: {
                const task = parent as Task;
                if (task) {
                    tasksModel.requestPublishDelegateGeometry(task.modelIndex(), backend.globalRect(task), task);
                }
                destroy();
            }
        }
    }

    Connections {
        target: Plasmoid

        function onLocationChanged(): void {
            if (TaskTools.taskManagerInstanceCount >= 2) {
                return;
            }
            // This is on a timer because the panel may not have
            // settled into position yet when the location prop-
            // erty updates.
            iconGeometryTimer.start();
        }
    }

    Connections {
        target: Plasmoid.containment

        function onScreenGeometryChanged(): void {
            iconGeometryTimer.start();
        }
    }

    Mpris.Mpris2Model {
        id: mpris2Source
    }

    Item {
        anchors.fill: parent

        TaskManager.VirtualDesktopInfo {
            id: virtualDesktopInfo
        }

        TaskManager.ActivityInfo {
            id: activityInfo
            readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
        }

        Loader {
            id: pulseAudio
            sourceComponent: pulseAudioComponent
            active: pulseAudioComponent.status === Component.Ready
        }

        Timer {
            id: iconGeometryTimer

            interval: 500
            repeat: false

            onTriggered: {
                tasks.publishIconGeometries(taskList.children, tasks);
            }
        }

        Binding {
            target: Plasmoid
            property: "status"
            value: (tasksModel.anyTaskDemandsAttention && Plasmoid.configuration.unhideOnAttention
                ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus)
            restoreMode: Binding.RestoreBinding
        }

        Connections {
            target: Plasmoid.configuration

            function onLaunchersChanged(): void {
                tasksModel.launcherList = Plasmoid.configuration.launchers;
                // Pick up external config changes (e.g. from another process)
                var json = JSON.stringify(Plasmoid.configuration.launchers);
                if (tasks._activeSyncGroup && json !== tasks._liveLaunchersJson) {
                    tasks._liveLaunchersJson = json;
                    TaskTools.updateSyncGroupLaunchers(tasks._activeSyncGroup, json, tasks._syncInstanceId);
                }
            }
            function onGroupingAppIdBlacklistChanged(): void {
                tasksModel.groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            }
            function onGroupingLauncherUrlBlacklistChanged(): void {
                tasksModel.groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;
            }
        }

        Component {
            id: busyIndicator
            PlasmaComponents3.BusyIndicator {}
        }

        // Save drag data
        Item {
            id: dragHelper

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
            Drag.onDragFinished: dropAction => {
                tasks.dragSource = null;
            }
        }

        KSvg.FrameSvgItem {
            id: taskFrame

            visible: false

            imagePath: "widgets/tasks"
            prefix: TaskTools.taskPrefix("normal", Plasmoid.location)
        }

        MouseHandler {
            id: mouseHandler

            anchors.fill: parent

            target: taskList

            onUrlsDropped: urls => {
                // If all dropped URLs point to application desktop files, we'll add a launcher for each of them.
                const createLaunchers = urls.every(item => backend.isApplication(item));

                if (createLaunchers) {
                    urls.forEach(item => addLauncher(item));
                    return;
                }

                if (!hoveredItem) {
                    return;
                }

                // Otherwise we'll just start a new instance of the application with the URLs as argument,
                // as you probably don't expect some of your files to open in the app and others to spawn launchers.
                tasksModel.requestOpenUrls(hoveredItem.modelIndex(), urls);
            }
        }

        ToolTipDelegate {
            id: openWindowToolTipDelegate
            visible: false
        }

        ToolTipDelegate {
            id: pinnedAppToolTipDelegate
            visible: false
        }

        TriangleMouseFilter {
            id: tmf
            filterTimeOut: 300
            active: tasks.toolTipAreaItem && tasks.toolTipAreaItem.toolTipOpen
            blockFirstEnter: false

            edge: {
                switch (Plasmoid.location) {
                case PlasmaCore.Types.BottomEdge:
                    return Qt.TopEdge;
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
                }
            }

            LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, vertical)
            anchors {
                left: parent.left
                top: parent.top
            }

            height: tasks.sectionedMode ? sectionedLayout.height : taskList.height
            width: tasks.sectionedMode ? sectionedLayout.width : taskList.width

            TaskList {
                id: taskList
                visible: !tasks.sectionedMode

                LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, vertical)
                anchors {
                    left: parent.left
                    top: parent.top
                }

                readonly property real widthOccupation: taskRepeater.count / columns
                readonly property real heightOccupation: taskRepeater.count / rows

                Layout.maximumWidth: {
                    const totalMaxWidth = children.reduce((accumulator, child) => {
                            if (!isFinite(child.Layout.maximumWidth)) {
                                return accumulator;
                            }
                            return accumulator + child.Layout.maximumWidth
                        }, 0);
                    return Math.round(totalMaxWidth / widthOccupation);
                }
                Layout.maximumHeight: {
                    const totalMaxHeight = children.reduce((accumulator, child) => {
                            if (!isFinite(child.Layout.maximumHeight)) {
                                return accumulator;
                            }
                            return accumulator + child.Layout.maximumHeight
                        }, 0);
                    return Math.round(totalMaxHeight / heightOccupation);
                }
                width: {
                    if (tasks.shouldShrinkToZero) {
                        return 0;
                    }
                    if (tasks.vertical) {
                        return tasks.width * Math.min(1, widthOccupation);
                    } else {
                        return Math.min(tasks.width, Layout.maximumWidth);
                    }
                }
                height: {
                    if (tasks.shouldShrinkToZero) {
                        return 0;
                    }
                    if (tasks.vertical) {
                        return Math.min(tasks.height, Layout.maximumHeight);
                    } else {
                        return tasks.height * Math.min(1, heightOccupation);
                    }
                }

                flow: {
                    if (tasks.vertical) {
                        return Plasmoid.configuration.forceStripes ? Grid.LeftToRight : Grid.TopToBottom
                    }
                    return Plasmoid.configuration.forceStripes ? Grid.TopToBottom : Grid.LeftToRight
                }

                onAnimatingChanged: {
                    if (!animating) {
                        tasks.publishIconGeometries(children, tasks);
                    }
                }

                Repeater {
                    id: taskRepeater

                    delegate: Task {
                        tasksRoot: tasks
                    }
                    onItemRemoved: (index, item) => {
                        if (tasks.containsMouse && index !== taskRepeater.count &&
                            item.model.WinIdList.length > 0 &&
                            taskClosedWithMouseMiddleButton.includes(item.winIdList[0])) {
                            needLayoutRefresh = true;
                        }
                        taskClosedWithMouseMiddleButton = [];
                    }
                    onItemAdded: (index, item) => {
                        if (tasks.sectionedMode && item) {
                            sectionedLayout.reparentTask(item);
                        }
                    }
                }
            }

            SectionedTaskLayout {
                id: sectionedLayout
                visible: tasks.sectionedMode
                layoutItems: tasks.parsedLayout
                anchors {
                    left: parent.left
                    top: parent.top
                }
                width: tasks.width
                height: tasks.height
            }
        }
    }

    readonly property Component groupDialogComponent: Qt.createComponent("GroupDialog.qml")
    property GroupDialog groupDialog

    readonly property bool supportsLaunchers: true

    function hasLauncher(url: url): bool {
        return tasksModel.launcherPosition(url) !== -1;
    }

    function addLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestAddLauncher(url);
        }
    }

    function removeLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestRemoveLauncher(url);
        }
    }

    // This is called by plasmashell in response to a Meta+number shortcut.
    function activateTaskAtIndex(index: int): void {

        const task = taskRepeater.itemAt(index);
        if (task) {
            TaskTools.activateTask(task.modelIndex(), task.model, null, task, Plasmoid, this, effectWatcher.registered);
        }
    }

    function createContextMenu(rootTask, modelIndex, args = {}) {
        const initialArgs = Object.assign(args, {
            visualParent: rootTask,
            modelIndex,
            mpris2Source,
            backend,
        });
        return contextMenuComponent.createObject(rootTask, initialArgs);
    }

    function shouldBeMirrored(reverseMode, layoutDirection, vertical): bool {
        // LayoutMirroring is only horizontal
        if (vertical) {
            return layoutDirection === Qt.RightToLeft;
        }

        if (layoutDirection === Qt.LeftToRight) {
            return reverseMode;
        }
        return !reverseMode;
    }

    Component.onCompleted: {
        TaskTools.taskManagerInstanceCount += 1;
        requestLayout.connect(iconGeometryTimer.restart);

        // Initialize layout if no sections are configured yet
        var tg = Plasmoid.configuration.taskSections;
        if (!tg || tg.trim() === "" || tg.trim() === "[]") {
            Plasmoid.configuration.taskSections = JSON.stringify([
                {type: "section", name: "__unsectioned", appIds: [], color: ""}
            ]);
        }

        // Set initial live state and join sync group
        _liveLayoutJson = Plasmoid.configuration.taskSections;
        _joinSyncGroup();

        // Init exclusive mode claims
        if (Plasmoid.configuration.exclusiveMode && _claimsPath) {
            _writeClaims();
            _readOtherClaims();
        }
    }

    Component.onDestruction: {
        TaskTools.taskManagerInstanceCount -= 1;
        if (_activeSyncGroup) TaskTools.leaveSyncGroup(_activeSyncGroup, _syncInstanceId);

        // Clean up claims on destruction
        if (_claimsPath) {
            try {
                claimsStore.sync();
                var instances = String(claimsStore.value("instances", ""));
                var arr = instances ? instances.split(",") : [];
                arr = arr.filter(function(id) { return id !== _myInstanceId; });
                claimsStore.setValue("instances", arr.join(","));
                claimsStore.setValue("inst_" + _myInstanceId, "");
                claimsStore.sync();
            } catch (e) {}
        }
    }
}
