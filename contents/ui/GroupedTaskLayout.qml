/*
    SPDX-FileCopyrightText: 2024 Filtered Task Manager fork
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
    id: groupedLayout

    property var layoutItems: []
    property bool animating: false
    // 0 = Left, 1 = Right, 2 = Center, 3 = No Fill (no fillers active)
    property int alignment: 0
    property int dropTargetGroupIndex: -1

    implicitWidth: tasks.vertical ? groupColumn.implicitWidth : groupRow.implicitWidth
    implicitHeight: tasks.vertical ? groupColumn.implicitHeight : groupRow.implicitHeight

    readonly property real minimumWidth: {
        var rep = tasks.vertical ? repeaterV : repeaterH;
        var min = Infinity;
        for (var g = 0; g < rep.count; g++) {
            var section = rep.itemAt(g);
            if (!section || !section.isGroup) continue;
            var flow = section.taskFlow;
            if (!flow) continue;
            for (var c = 0; c < flow.children.length; c++) {
                var child = flow.children[c];
                if (child.visible && child.width > 0) {
                    min = Math.min(min, child.width);
                }
            }
        }
        return min === Infinity ? 0 : min;
    }

    function groupForApp(appId) {
        var ungroupedIdx = -1;
        for (var i = 0; i < layoutItems.length; i++) {
            var item = layoutItems[i];
            if (item.type !== "group") continue;
            if (item.name === "__ungrouped") {
                ungroupedIdx = i;
                continue;
            }
            var ids = item.appIds || [];
            for (var j = 0; j < ids.length; j++) {
                if (ids[j] === appId) return i;
            }
        }
        return ungroupedIdx;
    }

    function _returnAllTasksToTaskList() {
        for (var i = 0; i < tasks.taskRepeater.count; i++) {
            var task = tasks.taskRepeater.itemAt(i);
            if (task && task.parent !== tasks.taskList) {
                task.oldX = -1;
                task.oldY = -1;
                task.parent = tasks.taskList;
            }
        }
    }

    function reparentTask(task) {
        var gIdx = groupForApp(task.appId);
        if (gIdx < 0) {
            task.visible = false;
            return;
        }

        var isUngrouped = layoutItems[gIdx].name === "__ungrouped";

        if (isUngrouped && Plasmoid.configuration.exclusiveMode) {
            var excluded = tasks.excludedByOthers;
            if (excluded) {
                for (var k = 0; k < excluded.length; k++) {
                    if (excluded[k] === task.appId) {
                        task.visible = false;
                        return;
                    }
                }
            }
        }

        var container = containerForGroup(gIdx);
        if (container && task.parent !== container) {
            task.oldX = -1;
            task.oldY = -1;
            task.parent = container;
        }
        task.visible = true;
        task.groupIndex = gIdx;
    }

    function reparentAllTasks() {
        // Build a map of groupIdx -> sorted task list
        var groupTasks = {};  // groupIdx -> [task, ...]
        for (var i = 0; i < tasks.taskRepeater.count; i++) {
            var task = tasks.taskRepeater.itemAt(i);
            if (!task) continue;
            var gIdx = groupForApp(task.appId);
            if (gIdx < 0) {
                task.visible = false;
                continue;
            }

            var isUngrouped = layoutItems[gIdx].name === "__ungrouped";
            if (isUngrouped && Plasmoid.configuration.exclusiveMode) {
                var excluded = tasks.excludedByOthers;
                var isExcluded = false;
                if (excluded) {
                    for (var k = 0; k < excluded.length; k++) {
                        if (excluded[k] === task.appId) {
                            isExcluded = true;
                            break;
                        }
                    }
                }
                if (isExcluded) {
                    task.visible = false;
                    continue;
                }
            }

            task.visible = true;
            task.groupIndex = gIdx;
            if (!groupTasks[gIdx]) groupTasks[gIdx] = [];
            groupTasks[gIdx].push(task);
        }

        // For each group, sort tasks by appIds order, then reparent in order
        for (var gIdx in groupTasks) {
            var container = containerForGroup(parseInt(gIdx));
            if (!container) continue;
            var tasksInGroup = groupTasks[gIdx];
            var itemData = layoutItems[parseInt(gIdx)] || {};
            var appIds = itemData.appIds || [];

            // Build order map
            var orderMap = {};
            for (var a = 0; a < appIds.length; a++) {
                orderMap[appIds[a]] = a;
            }

            // Sort tasks: those in appIds by their order, others by model index
            tasksInGroup.sort(function(a, b) {
                var oa = (a.appId in orderMap) ? orderMap[a.appId] : 999999 + a.index;
                var ob = (b.appId in orderMap) ? orderMap[b.appId] : 999999 + b.index;
                return oa - ob;
            });

            // Detach all tasks to taskList, then reparent in sorted order.
            // Flow uses insertion order, so this controls visual ordering.
            for (var d = 0; d < tasksInGroup.length; d++) {
                tasksInGroup[d].oldX = -1;
                tasksInGroup[d].oldY = -1;
                tasksInGroup[d].parent = tasks.taskList;
            }
            for (var r = 0; r < tasksInGroup.length; r++) {
                tasksInGroup[r].oldX = -1;
                tasksInGroup[r].oldY = -1;
                tasksInGroup[r].parent = container;
            }
        }
    }

    // Return the visual index of a task within its parent Flow (0-based),
    // or -1 if not found. Only counts visible task children with appId.
    function visualIndexInFlow(task) {
        if (!task || !task.parent) return -1;
        var flow = task.parent;
        var idx = 0;
        for (var c = 0; c < flow.children.length; c++) {
            var child = flow.children[c];
            if (child === task) return idx;
            if (child && child.visible && child.appId !== undefined) idx++;
        }
        return -1;
    }

    // Move an app to a specific visual position within a group's appIds.
    // Updates layoutItems in-place for immediate visual effect without
    // triggering the full _saveLayout → config persistence chain.
    // Returns true if a change was made.
    function moveAppIdToPosition(groupIdx, appId, targetVisualIndex) {
        var itemData = layoutItems[groupIdx];
        if (!itemData) return false;
        var ids = itemData.appIds || [];
        var fromIdx = ids.indexOf(appId);
        if (fromIdx < 0 || targetVisualIndex < 0 || targetVisualIndex >= ids.length) return false;
        if (fromIdx === targetVisualIndex) return false;
        // Mutate in place for speed — we'll persist on drop
        ids.splice(fromIdx, 1);
        ids.splice(targetVisualIndex, 0, appId);
        _dragDirty = true;
        return true;
    }

    // Reorder a single group's Flow children to match current appIds order.
    // Detaches and re-adds all tasks synchronously so parent references
    // are correct immediately after return.
    function reorderGroupFlow(groupIdx) {
        var container = containerForGroup(groupIdx);
        if (!container) return;
        var itemData = layoutItems[groupIdx] || {};
        var appIds = itemData.appIds || [];
        if (appIds.length < 2) return;

        // Build order map
        var orderMap = {};
        for (var a = 0; a < appIds.length; a++) {
            orderMap[appIds[a]] = a;
        }

        // Collect task children of this Flow
        var children = [];
        for (var c = 0; c < container.children.length; c++) {
            var child = container.children[c];
            if (child && child.appId !== undefined) {
                children.push(child);
            }
        }
        if (children.length < 2) return;

        // Sort by appIds order
        children.sort(function(a, b) {
            var oa = (a.appId in orderMap) ? orderMap[a.appId] : 999999 + a.index;
            var ob = (b.appId in orderMap) ? orderMap[b.appId] : 999999 + b.index;
            return oa - ob;
        });

        // Detach all then re-add in sorted order
        for (var d = 0; d < children.length; d++) {
            children[d].oldX = -1;
            children[d].oldY = -1;
            children[d].parent = tasks.taskList;
        }
        for (var r = 0; r < children.length; r++) {
            children[r].oldX = -1;
            children[r].oldY = -1;
            children[r].parent = container;
        }
    }

    // Persist current in-memory layoutItems to config and sync group.
    function persistLayout() {
        tasks._saveLayout(layoutItems);
    }

    property bool _reparentPending: false
    property bool _dragDirty: false  // true when in-memory appIds changed during drag

    onLayoutItemsChanged: {
        if (!tasks.dragSource) {
            _returnAllTasksToTaskList();
            _reparentTimer.restart();
        } else {
            // During a drag, defer full reparent until drag ends.
            _reparentPending = true;
        }
    }

    Connections {
        target: tasks
        function onDragSourceChanged() {
            if (!tasks.dragSource) {
                if (groupedLayout._dragDirty) {
                    // Persist the in-memory appIds order that was built up during drag
                    groupedLayout._dragDirty = false;
                    groupedLayout.persistLayout();
                }
                if (groupedLayout._reparentPending) {
                    groupedLayout._reparentPending = false;
                    _reparentTimer.restart();
                }
            }
        }
    }

    Timer {
        id: _reparentTimer
        interval: 0
        onTriggered: groupedLayout.reparentAllTasks()
    }

    function scheduleReparent() {
        _reparentTimer.restart();
    }

    function taskAtPosition(x, y) {
        var rep = tasks.vertical ? repeaterV : repeaterH;
        for (var g = 0; g < rep.count; g++) {
            var section = rep.itemAt(g);
            if (!section || !section.isGroup) continue;
            var flow = section.taskFlow;
            if (!flow) continue;
            var localPos = flow.mapFromItem(groupedLayout, x, y);
            var child = flow.childAt(localPos.x, localPos.y);
            if (child) return child;
        }
        return null;
    }

    function groupIndexAtPosition(x, y) {
        var rep = tasks.vertical ? repeaterV : repeaterH;
        for (var g = 0; g < rep.count; g++) {
            var section = rep.itemAt(g);
            if (!section || !section.isGroup) continue;
            var localPos = section.mapFromItem(groupedLayout, x, y);
            if (localPos.x >= 0 && localPos.x <= section.width
                && localPos.y >= 0 && localPos.y <= section.height) {
                return section.index;
            }
        }
        return -1;
    }

    // ── Horizontal panel ──
    RowLayout {
        id: groupRow
        anchors.fill: parent
        spacing: 0
        visible: !tasks.vertical

        // Left filler: visible for Right-aligned and Centered
        Item { Layout.fillWidth: groupedLayout.alignment === 1 || groupedLayout.alignment === 2 }

        Repeater {
            id: repeaterH
            model: groupedLayout.layoutItems.length

            delegate: Item {
                id: sectionH
                required property int index

                readonly property var itemData: groupedLayout.layoutItems[index] || {}
                readonly property bool isGroup: (itemData.type || "group") === "group"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property string itemColor: itemData.color || ""
                property Item taskFlow: isGroup ? flowH : null
                readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

                readonly property real contentWidth: {
                    if (!isGroup) return 0;
                    var w = 0;
                    for (var i = 0; i < flowH.children.length; i++) {
                        var c = flowH.children[i];
                        if (c.visible) w += c.implicitWidth;
                    }
                    return w;
                }
                Layout.fillHeight: true
                Layout.preferredWidth: isSpacer ? spacerSize : contentWidth
                Layout.maximumWidth: isSpacer ? spacerSize : contentWidth

                Rectangle {
                    visible: sectionH.itemColor !== "" || (groupedLayout.dropTargetGroupIndex === sectionH.index && tasks.dragSource)
                    anchors.fill: parent
                    color: sectionH.itemColor || "transparent"
                    border.color: (groupedLayout.dropTargetGroupIndex === sectionH.index && tasks.dragSource)
                        ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: (groupedLayout.dropTargetGroupIndex === sectionH.index && tasks.dragSource) ? 2 : 0
                    radius: 4
                }

                Flow {
                    id: flowH
                    visible: sectionH.isGroup
                    anchors.fill: parent
                    spacing: 0
                    LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, tasks.vertical)
                    LayoutMirroring.childrenInherit: true

                    // Task.qml reads task.parent.minimumWidth for icon sizing
                    readonly property real minimumWidth: {
                        var min = Infinity;
                        for (var i = 0; i < children.length; i++) {
                            var c = children[i];
                            if (c.visible && c.width > 0)
                                min = Math.min(min, c.width);
                        }
                        return min === Infinity ? 0 : min;
                    }
                    property int animationsRunning: 0
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionH.isGroup
                    onTapped: function(eventPoint) {
                        var localPos = flowH.mapFromItem(sectionH, eventPoint.position.x, eventPoint.position.y);
                        var child = flowH.childAt(localPos.x, localPos.y);
                        if (!child) {
                            groupedLayout.showSectionMenu(sectionH, sectionH.index);
                        }
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionH.isSpacer
                    onTapped: {
                        groupedLayout.showSpacerMenu(sectionH, sectionH.index);
                    }
                }

                implicitWidth: isSpacer ? spacerSize : contentWidth
            }
        }

        // Right filler: visible for Left-aligned and Centered
        Item { Layout.fillWidth: groupedLayout.alignment === 0 || groupedLayout.alignment === 2 }
    }

    // ── Vertical panel ──
    ColumnLayout {
        id: groupColumn
        anchors.fill: parent
        spacing: 0
        visible: tasks.vertical

        // Top filler: visible for Right(Bottom)-aligned and Centered
        Item { Layout.fillHeight: groupedLayout.alignment === 1 || groupedLayout.alignment === 2 }

        Repeater {
            id: repeaterV
            model: groupedLayout.layoutItems.length

            delegate: Item {
                id: sectionV
                required property int index

                readonly property var itemData: groupedLayout.layoutItems[index] || {}
                readonly property bool isGroup: (itemData.type || "group") === "group"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property string itemColor: itemData.color || ""
                property Item taskFlow: isGroup ? flowV : null
                readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

                readonly property real contentHeight: {
                    if (!isGroup) return 0;
                    var h = 0;
                    for (var i = 0; i < flowV.children.length; i++) {
                        var c = flowV.children[i];
                        if (c.visible) h += c.implicitHeight;
                    }
                    return h;
                }
                Layout.fillWidth: true
                Layout.preferredHeight: isSpacer ? spacerSize : contentHeight
                Layout.maximumHeight: isSpacer ? spacerSize : contentHeight

                Rectangle {
                    visible: sectionV.itemColor !== "" || (groupedLayout.dropTargetGroupIndex === sectionV.index && tasks.dragSource)
                    anchors.fill: parent
                    color: sectionV.itemColor || "transparent"
                    border.color: (groupedLayout.dropTargetGroupIndex === sectionV.index && tasks.dragSource)
                        ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: (groupedLayout.dropTargetGroupIndex === sectionV.index && tasks.dragSource) ? 2 : 0
                    radius: 4
                }

                Flow {
                    id: flowV
                    visible: sectionV.isGroup
                    anchors.fill: parent
                    spacing: 0
                    LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, tasks.vertical)
                    LayoutMirroring.childrenInherit: true

                    readonly property real minimumWidth: {
                        var min = Infinity;
                        for (var i = 0; i < children.length; i++) {
                            var c = children[i];
                            if (c.visible && c.width > 0)
                                min = Math.min(min, c.width);
                        }
                        return min === Infinity ? 0 : min;
                    }
                    property int animationsRunning: 0
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionV.isGroup
                    onTapped: function(eventPoint) {
                        var localPos = flowV.mapFromItem(sectionV, eventPoint.position.x, eventPoint.position.y);
                        var child = flowV.childAt(localPos.x, localPos.y);
                        if (!child) {
                            groupedLayout.showSectionMenu(sectionV, sectionV.index);
                        }
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionV.isSpacer
                    onTapped: {
                        groupedLayout.showSpacerMenu(sectionV, sectionV.index);
                    }
                }

                implicitHeight: isSpacer ? spacerSize : contentHeight
            }
        }

        // Bottom filler: visible for Left(Top)-aligned and Centered
        Item { Layout.fillHeight: groupedLayout.alignment === 0 || groupedLayout.alignment === 2 }
    }

    function containerForGroup(layoutIndex) {
        var rep = tasks.vertical ? repeaterV : repeaterH;
        if (layoutIndex < 0 || layoutIndex >= rep.count) return null;
        var section = rep.itemAt(layoutIndex);
        if (!section || !section.isGroup) return null;
        return section.taskFlow;
    }

    readonly property Component sectionMenuComponent: Qt.createComponent("GroupSectionMenu.qml")
    readonly property Component spacerMenuComponent: Qt.createComponent("SpacerMenu.qml")

    function showSectionMenu(section, layoutIndex) {
        if (sectionMenuComponent.status !== Component.Ready) return;
        var menu = sectionMenuComponent.createObject(section, {
            layoutIndex: layoutIndex,
            tasksRoot: tasks,
            visualParent: section
        });
        menu.openRelative();
    }

    function showSpacerMenu(section, layoutIndex) {
        if (spacerMenuComponent.status !== Component.Ready) return;
        var menu = spacerMenuComponent.createObject(section, {
            layoutIndex: layoutIndex,
            tasksRoot: tasks,
            visualParent: section
        });
        menu.openRelative();
    }
}
