/*
    SPDX-FileCopyrightText: 2024 Filtered Task Manager fork
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

Item {
    id: groupedLayout

    property var layoutItems: []
    property bool animating: false
    // 0 = Left, 1 = Right, 2 = Center, 3 = No Fill (no fillers active)
    property int alignment: 0

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
        for (var i = 0; i < tasks.taskRepeater.count; i++) {
            var task = tasks.taskRepeater.itemAt(i);
            if (task) reparentTask(task);
        }
    }

    onLayoutItemsChanged: {
        _returnAllTasksToTaskList();
        _reparentTimer.restart();
    }

    Timer {
        id: _reparentTimer
        interval: 0
        onTriggered: groupedLayout.reparentAllTasks()
    }

    function scheduleReparent() {
        _reparentTimer.restart();
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
                Layout.preferredWidth: isSpacer ? (itemData.width || 0) : contentWidth
                Layout.maximumWidth: isSpacer ? (itemData.width || 0) : contentWidth

                Rectangle {
                    visible: sectionH.itemColor !== ""
                    anchors.fill: parent
                    color: sectionH.itemColor
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

                implicitWidth: isSpacer ? (itemData.width || 0) : contentWidth
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
                Layout.preferredHeight: isSpacer ? (itemData.width || 0) : contentHeight
                Layout.maximumHeight: isSpacer ? (itemData.width || 0) : contentHeight

                Rectangle {
                    visible: sectionV.itemColor !== ""
                    anchors.fill: parent
                    color: sectionV.itemColor
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

                implicitHeight: isSpacer ? (itemData.width || 0) : contentHeight
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
}
