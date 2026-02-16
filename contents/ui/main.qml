/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import Qt.labs.settings as LabSettings

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

import org.kde.plasma.workspace.trianglemousefilter

import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.taskmanager as TaskManagerApplet
import org.kde.plasma.workspace.dbus as DBus

import "code/layoutmetrics.js" as LayoutMetrics
import "code/tools.js" as TaskTools

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

    // Parsed layout: mixed array of group and spacer items from config
    readonly property var parsedLayout: {
        var raw = Plasmoid.configuration.taskGroups;
        if (!raw || raw.trim() === "") return [];
        try { return JSON.parse(raw); }
        catch (e) { return []; }
    }
    readonly property bool groupedMode: parsedLayout.length > 0
    property alias taskRepeater: taskRepeater
    property alias groupedLayout: groupedLayout

    // Collect all claimed app IDs (from named groups, not ungrouped or spacers)
    readonly property var allClaimedAppIds: {
        var ids = [];
        for (var i = 0; i < parsedLayout.length; i++) {
            var item = parsedLayout[i];
            if (item.type !== "group" || item.name === "__ungrouped") continue;
            var appIds = item.appIds || [];
            for (var j = 0; j < appIds.length; j++) {
                ids.push(appIds[j]);
            }
        }
        return ids;
    }

    // ── Exclusive mode ──
    readonly property string _homeDir: {
        var url = Qt.resolvedUrl(".").toString();
        var m = url.match(/^file:\/\/(\/[^\/]+\/[^\/]+)\//);
        return m ? m[1] : "";
    }
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
            if (tasks.groupedMode) groupedLayout.reparentAllTasks();
        }
    }

    onAllClaimedAppIdsChanged: _writeClaims()

    function _saveLayout(items) {
        Plasmoid.configuration.taskGroups = JSON.stringify(items);
    }

    function moveAppToGroup(appId, fromLayoutIdx, toLayoutIdx) {
        var items = parsedLayout.slice();
        // Remove from old group
        if (fromLayoutIdx >= 0 && fromLayoutIdx < items.length && items[fromLayoutIdx].type === "group") {
            items[fromLayoutIdx] = Object.assign({}, items[fromLayoutIdx]);
            items[fromLayoutIdx].appIds = (items[fromLayoutIdx].appIds || []).filter(function(id) { return id !== appId; });
        }
        // Add to new group (unless it's ungrouped)
        if (toLayoutIdx >= 0 && toLayoutIdx < items.length && items[toLayoutIdx].type === "group" && items[toLayoutIdx].name !== "__ungrouped") {
            items[toLayoutIdx] = Object.assign({}, items[toLayoutIdx]);
            var ids = (items[toLayoutIdx].appIds || []).slice();
            if (ids.indexOf(appId) < 0) ids.push(appId);
            items[toLayoutIdx].appIds = ids;
        }
        _saveLayout(items);
    }

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

    // groupAlignment 0-2 = fill (Left/Right/Center), 3 = no fill
    readonly property bool effectiveFill: groupedMode
        ? Plasmoid.configuration.groupAlignment !== 3
        : Plasmoid.configuration.fill
    Layout.fillWidth: vertical ? true : effectiveFill
    Layout.fillHeight: !vertical ? true : effectiveFill
    Layout.minimumWidth: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        if (groupedMode && !vertical) {
            return groupedLayout.implicitWidth;
        }
        return vertical ? 0 : LayoutMetrics.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        if (groupedMode && vertical) {
            return groupedLayout.implicitHeight;
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
        if (groupedMode) {
            return groupedLayout.implicitWidth;
        }
        return taskList.Layout.maximumWidth
    }
    Layout.preferredHeight: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            if (groupedMode) {
                return groupedLayout.implicitHeight;
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
        }

        onGroupingAppIdBlacklistChanged: {
            Plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist;
        }

        onGroupingLauncherUrlBlacklistChanged: {
            Plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
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
                tasksModel.launcherList = Plasmoid.configuration.launchers
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

            height: tasks.groupedMode ? groupedLayout.height : taskList.height
            width: tasks.groupedMode ? groupedLayout.width : taskList.width

            TaskList {
                id: taskList
                visible: !tasks.groupedMode

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
                        if (tasks.groupedMode) {
                            groupedLayout.scheduleReparent();
                        }
                    }
                }
            }

            GroupedTaskLayout {
                id: groupedLayout
                visible: tasks.groupedMode
                layoutItems: tasks.parsedLayout
                alignment: Plasmoid.configuration.groupAlignment
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
    // TODO: Change type to int
    function activateTaskAtIndex(index: var): void {
        if (typeof index !== "number") {
            return;
        }

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

        // Initialize layout if no groups are configured yet
        var tg = Plasmoid.configuration.taskGroups;
        if (!tg || tg.trim() === "" || tg.trim() === "[]") {
            var fa = Plasmoid.configuration.filterAppIds;
            if (fa && fa.trim() !== "") {
                // Migrate from flat filter list to grouped layout
                var ids = fa.split(",").map(function(s) { return s.trim(); }).filter(function(s) { return s !== ""; });
                Plasmoid.configuration.taskGroups = JSON.stringify([
                    {type: "group", name: "Default", appIds: ids, color: ""},
                    {type: "spacer", width: 8},
                    {type: "group", name: "__ungrouped", appIds: [], color: ""}
                ]);
            } else {
                Plasmoid.configuration.taskGroups = JSON.stringify([
                    {type: "group", name: "__ungrouped", appIds: [], color: ""}
                ]);
            }
        }

        // Init exclusive mode claims
        if (Plasmoid.configuration.exclusiveMode && _claimsPath) {
            _writeClaims();
            _readOtherClaims();
        }
    }

    Component.onDestruction: {
        TaskTools.taskManagerInstanceCount -= 1;

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
