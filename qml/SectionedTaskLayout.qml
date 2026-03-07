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
    id: sectionedLayout

    property var layoutItems: []
    property bool animating: false
    property int dropTargetSectionIndex: -1
    property int dropInsertIndex: -1

    // Split layoutItems into left-floated and right-floated arrays.
    // Each entry is {origIndex, data} so delegates can map back to layoutItems.
    readonly property var leftItems: {
        var arr = [];
        for (var i = 0; i < layoutItems.length; i++) {
            var item = layoutItems[i];
            if ((item["float"] || "left") === "left")
                arr.push({origIndex: i, data: item});
        }
        return arr;
    }
    readonly property var rightItems: {
        var arr = [];
        for (var i = 0; i < layoutItems.length; i++) {
            var item = layoutItems[i];
            if ((item["float"] || "left") === "right")
                arr.push({origIndex: i, data: item});
        }
        return arr;
    }

    // Whether we have any right-floated items (controls fill visibility)
    readonly property bool hasRightItems: rightItems.length > 0

    implicitWidth: tasks.vertical ? sectionColumn.implicitWidth : sectionRow.implicitWidth
    implicitHeight: tasks.vertical ? sectionColumn.implicitHeight : sectionRow.implicitHeight

    readonly property real minimumWidth: {
        var min = Infinity;
        var repeaters = tasks.vertical
            ? [repeaterLeftV, repeaterRightV]
            : [repeaterLeftH, repeaterRightH];
        for (var r = 0; r < repeaters.length; r++) {
            var rep = repeaters[r];
            for (var g = 0; g < rep.count; g++) {
                var section = rep.itemAt(g);
                if (!section || !section.isSection) continue;
                var flow = section.taskFlow;
                if (!flow) continue;
                for (var c = 0; c < flow.children.length; c++) {
                    var child = flow.children[c];
                    if (child.visible && child.width > 0) {
                        min = Math.min(min, child.width);
                    }
                }
            }
        }
        return min === Infinity ? 0 : min;
    }

    function sectionForApp(appId) {
        var unsectionedIdx = -1;
        for (var i = 0; i < layoutItems.length; i++) {
            var item = layoutItems[i];
            if (item.type !== "section") continue;
            if (item.name === "__unsectioned") {
                unsectionedIdx = i;
                continue;
            }
            var ids = item.appIds || [];
            for (var j = 0; j < ids.length; j++) {
                if (ids[j] === appId) return i;
            }
        }
        return unsectionedIdx;
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
        var gIdx = sectionForApp(task.appId);
        if (gIdx < 0) {
            task.visible = false;
            return;
        }

        var isUnsectioned = layoutItems[gIdx].name === "__unsectioned";

        if (isUnsectioned && Plasmoid.configuration.exclusiveMode) {
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

        var container = containerForSection(gIdx);
        if (container && task.parent !== container) {
            task.oldX = -1;
            task.oldY = -1;
            task.parent = container;
        }
        task.visible = true;
        task.sectionIndex = gIdx;
    }

    function reparentAllTasks() {
        // Build a map of sectionIdx -> sorted task list
        var sectionTasks = {};  // sectionIdx -> [task, ...]
        for (var i = 0; i < tasks.taskRepeater.count; i++) {
            var task = tasks.taskRepeater.itemAt(i);
            if (!task) continue;
            var gIdx = sectionForApp(task.appId);
            if (gIdx < 0) {
                task.visible = false;
                continue;
            }

            var isUnsectioned = layoutItems[gIdx].name === "__unsectioned";
            if (isUnsectioned && Plasmoid.configuration.exclusiveMode) {
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
            task.sectionIndex = gIdx;
            if (!sectionTasks[gIdx]) sectionTasks[gIdx] = [];
            sectionTasks[gIdx].push(task);
        }

        // For each section, sort tasks by appIds order, then reparent only if needed
        for (var gIdx in sectionTasks) {
            var container = containerForSection(parseInt(gIdx));
            if (!container) continue;
            var tasksInSection = sectionTasks[gIdx];
            var itemData = layoutItems[parseInt(gIdx)] || {};
            var appIds = itemData.appIds || [];

            // Build order map
            var orderMap = {};
            for (var a = 0; a < appIds.length; a++) {
                orderMap[appIds[a]] = a;
            }

            // Sort tasks: those in appIds by their order, others by model index
            tasksInSection.sort(function(a, b) {
                var oa = (a.appId in orderMap) ? orderMap[a.appId] : 999999 + a.index;
                var ob = (b.appId in orderMap) ? orderMap[b.appId] : 999999 + b.index;
                return oa - ob;
            });

            // Check if all tasks are already in the correct container and order
            var needsReorder = tasksInSection.length > 0 && tasksInSection[0].parent !== container;
            if (!needsReorder) {
                // Check if Flow child order matches sorted order
                var flowIdx = 0;
                for (var c = 0; c < container.children.length && flowIdx < tasksInSection.length; c++) {
                    var child = container.children[c];
                    if (child && child.appId !== undefined && child.visible) {
                        if (child !== tasksInSection[flowIdx]) {
                            needsReorder = true;
                            break;
                        }
                        flowIdx++;
                    }
                }
                if (flowIdx < tasksInSection.length) needsReorder = true;
            }

            if (needsReorder) {
                // Detach then re-add in sorted order (synchronous = no flash).
                // Flow uses insertion order, so this controls visual ordering.
                for (var d = 0; d < tasksInSection.length; d++) {
                    tasksInSection[d].oldX = -1;
                    tasksInSection[d].oldY = -1;
                    tasksInSection[d].parent = tasks.taskList;
                }
                for (var r = 0; r < tasksInSection.length; r++) {
                    tasksInSection[r].oldX = -1;
                    tasksInSection[r].oldY = -1;
                    tasksInSection[r].parent = container;
                }
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

    // Move an app to the position of another app within a section's appIds.
    // Updates layoutItems in-place for immediate visual effect without
    // triggering the full _saveLayout → config persistence chain.
    // Returns true if a change was made.
    function moveAppIdToPosition(sectionIdx, appId, targetAppId) {
        var itemData = layoutItems[sectionIdx];
        if (!itemData) return false;
        var ids = itemData.appIds || [];
        var fromIdx = ids.indexOf(appId);
        var toIdx = ids.indexOf(targetAppId);
        if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return false;
        // Mutate in place for speed — we'll persist on drop
        ids.splice(fromIdx, 1);
        ids.splice(toIdx, 0, appId);
        _dragDirty = true;
        return true;
    }

    // Reorder a single section's Flow children to match current appIds order.
    // Detaches and re-adds all tasks synchronously so parent references
    // are correct immediately after return.
    function reorderSectionFlow(sectionIdx) {
        var container = containerForSection(sectionIdx);
        if (!container) return;
        var itemData = layoutItems[sectionIdx] || {};
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

    // Persist current in-memory layoutItems to config and sync section.
    function persistLayout() {
        tasks._saveLayout(layoutItems);
    }

    property bool _dragDirty: false  // true when in-memory appIds changed during drag

    onLayoutItemsChanged: {
        // Qt.callLater runs after all bindings settle (Repeater creates
        // new containers) but before the next render frame — no flash.
        Qt.callLater(reparentAllTasks);
    }

    Connections {
        target: tasks
        function onDragSourceChanged() {
            if (!tasks.dragSource && sectionedLayout._dragDirty) {
                // Persist the in-memory appIds order that was built up during drag
                sectionedLayout._dragDirty = false;
                sectionedLayout.persistLayout();
            }
            if (!tasks.dragSource) {
                sectionedLayout.dropInsertIndex = -1;
                dropIndicator.visible = false;
            }
        }
    }

    function scheduleReparent() {
        reparentAllTasks();
    }

    // Helper: search a repeater for a task at position
    function _searchRepeaterForTask(rep, x, y, isDragging, isVert) {
        for (var g = 0; g < rep.count; g++) {
            var section = rep.itemAt(g);
            if (!section || !section.isSection) continue;
            var flow = section.taskFlow;
            if (!flow) continue;

            // Only consider this section if the cursor is within its bounds
            var sectionPos = section.mapFromItem(sectionedLayout, x, y);
            if (sectionPos.x < 0 || sectionPos.x > section.width
                || sectionPos.y < 0 || sectionPos.y > section.height) {
                continue;
            }

            var localPos = flow.mapFromItem(sectionedLayout, x, y);

            if (!isDragging) {
                var child = flow.childAt(localPos.x, localPos.y);
                if (child) return child;
                continue;
            }

            var cursor = isVert ? localPos.y : localPos.x;
            var bestTask = null;
            for (var c = 0; c < flow.children.length; c++) {
                var t = flow.children[c];
                if (!t || !t.visible || t.appId === undefined) continue;
                var start = isVert ? t.y : t.x;
                var size = isVert ? t.height : t.width;
                var mid = start + size / 2;
                if (cursor >= mid) {
                    bestTask = t;
                } else if (cursor >= start) {
                    if (!bestTask) bestTask = t;
                    break;
                } else {
                    break;
                }
            }
            if (!bestTask && flow.children.length > 0) {
                for (var f = 0; f < flow.children.length; f++) {
                    var ft = flow.children[f];
                    if (ft && ft.visible && ft.appId !== undefined) {
                        bestTask = ft;
                        break;
                    }
                }
            }
            if (bestTask) return bestTask;
        }
        return null;
    }

    function taskAtPosition(x, y) {
        var isDragging = !!tasks.dragSource;
        var isVert = tasks.vertical;
        var repL = isVert ? repeaterLeftV : repeaterLeftH;
        var repR = isVert ? repeaterRightV : repeaterRightH;
        var result = _searchRepeaterForTask(repL, x, y, isDragging, isVert);
        if (result) return result;
        return _searchRepeaterForTask(repR, x, y, isDragging, isVert);
    }

    // Helper: search a repeater for a section at position
    function _searchRepeaterForSection(rep, x, y) {
        for (var g = 0; g < rep.count; g++) {
            var section = rep.itemAt(g);
            if (!section || !section.isSection) continue;
            var localPos = section.mapFromItem(sectionedLayout, x, y);
            if (localPos.x >= 0 && localPos.x <= section.width
                && localPos.y >= 0 && localPos.y <= section.height) {
                return section.origIndex;
            }
        }
        return -1;
    }

    function sectionIndexAtPosition(x, y) {
        var repL = tasks.vertical ? repeaterLeftV : repeaterLeftH;
        var repR = tasks.vertical ? repeaterRightV : repeaterRightH;
        var result = _searchRepeaterForSection(repL, x, y);
        if (result >= 0) return result;
        return _searchRepeaterForSection(repR, x, y);
    }

    // ── Horizontal panel ──
    RowLayout {
        id: sectionRow
        anchors.fill: parent
        spacing: 0
        visible: !tasks.vertical

        Repeater {
            id: repeaterLeftH
            model: sectionedLayout.leftItems

            delegate: Item {
                id: sectionLH
                required property var modelData
                required property int index

                readonly property int origIndex: modelData.origIndex
                readonly property var itemData: modelData.data
                readonly property bool isSection: (itemData.type || "section") === "section"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property string itemColor: itemData.color || ""
                property Item taskFlow: isSection ? flowLH : null
                readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

                readonly property real contentWidth: {
                    if (!isSection) return 0;
                    var w = 0;
                    for (var i = 0; i < flowLH.children.length; i++) {
                        var c = flowLH.children[i];
                        if (c.visible) w += c.implicitWidth;
                    }
                    return w;
                }
                Layout.fillHeight: true
                Layout.preferredWidth: isSpacer ? spacerSize : contentWidth
                Layout.maximumWidth: isSpacer ? spacerSize : contentWidth

                Rectangle {
                    visible: sectionLH.itemColor !== "" || (sectionedLayout.dropTargetSectionIndex === sectionLH.origIndex && tasks.dragSource)
                    anchors.fill: parent
                    color: sectionLH.itemColor || "transparent"
                    border.color: (sectionedLayout.dropTargetSectionIndex === sectionLH.origIndex && tasks.dragSource)
                        ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: (sectionedLayout.dropTargetSectionIndex === sectionLH.origIndex && tasks.dragSource) ? 2 : 0
                    radius: 4
                }

                Flow {
                    id: flowLH
                    visible: sectionLH.isSection
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
                    enabled: sectionLH.isSection
                    onTapped: function(eventPoint) {
                        var localPos = flowLH.mapFromItem(sectionLH, eventPoint.position.x, eventPoint.position.y);
                        var child = flowLH.childAt(localPos.x, localPos.y);
                        if (!child) {
                            sectionedLayout.showSectionMenu(sectionLH, sectionLH.origIndex);
                        }
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionLH.isSpacer
                    onTapped: {
                        sectionedLayout.showSpacerMenu(sectionLH, sectionLH.origIndex);
                    }
                }

                implicitWidth: isSpacer ? spacerSize : contentWidth
            }
        }

        // Fill space between left and right sections
        Item { Layout.fillWidth: true }

        Repeater {
            id: repeaterRightH
            model: sectionedLayout.rightItems

            delegate: Item {
                id: sectionRH
                required property var modelData
                required property int index

                readonly property int origIndex: modelData.origIndex
                readonly property var itemData: modelData.data
                readonly property bool isSection: (itemData.type || "section") === "section"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property string itemColor: itemData.color || ""
                property Item taskFlow: isSection ? flowRH : null
                readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

                readonly property real contentWidth: {
                    if (!isSection) return 0;
                    var w = 0;
                    for (var i = 0; i < flowRH.children.length; i++) {
                        var c = flowRH.children[i];
                        if (c.visible) w += c.implicitWidth;
                    }
                    return w;
                }
                Layout.fillHeight: true
                Layout.preferredWidth: isSpacer ? spacerSize : contentWidth
                Layout.maximumWidth: isSpacer ? spacerSize : contentWidth

                Rectangle {
                    visible: sectionRH.itemColor !== "" || (sectionedLayout.dropTargetSectionIndex === sectionRH.origIndex && tasks.dragSource)
                    anchors.fill: parent
                    color: sectionRH.itemColor || "transparent"
                    border.color: (sectionedLayout.dropTargetSectionIndex === sectionRH.origIndex && tasks.dragSource)
                        ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: (sectionedLayout.dropTargetSectionIndex === sectionRH.origIndex && tasks.dragSource) ? 2 : 0
                    radius: 4
                }

                Flow {
                    id: flowRH
                    visible: sectionRH.isSection
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
                    enabled: sectionRH.isSection
                    onTapped: function(eventPoint) {
                        var localPos = flowRH.mapFromItem(sectionRH, eventPoint.position.x, eventPoint.position.y);
                        var child = flowRH.childAt(localPos.x, localPos.y);
                        if (!child) {
                            sectionedLayout.showSectionMenu(sectionRH, sectionRH.origIndex);
                        }
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionRH.isSpacer
                    onTapped: {
                        sectionedLayout.showSpacerMenu(sectionRH, sectionRH.origIndex);
                    }
                }

                implicitWidth: isSpacer ? spacerSize : contentWidth
            }
        }
    }

    // ── Vertical panel ──
    ColumnLayout {
        id: sectionColumn
        anchors.fill: parent
        spacing: 0
        visible: tasks.vertical

        Repeater {
            id: repeaterLeftV
            model: sectionedLayout.leftItems

            delegate: Item {
                id: sectionLV
                required property var modelData
                required property int index

                readonly property int origIndex: modelData.origIndex
                readonly property var itemData: modelData.data
                readonly property bool isSection: (itemData.type || "section") === "section"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property string itemColor: itemData.color || ""
                property Item taskFlow: isSection ? flowLV : null
                readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

                readonly property real contentHeight: {
                    if (!isSection) return 0;
                    var h = 0;
                    for (var i = 0; i < flowLV.children.length; i++) {
                        var c = flowLV.children[i];
                        if (c.visible) h += c.implicitHeight;
                    }
                    return h;
                }
                Layout.fillWidth: true
                Layout.preferredHeight: isSpacer ? spacerSize : contentHeight
                Layout.maximumHeight: isSpacer ? spacerSize : contentHeight

                Rectangle {
                    visible: sectionLV.itemColor !== "" || (sectionedLayout.dropTargetSectionIndex === sectionLV.origIndex && tasks.dragSource)
                    anchors.fill: parent
                    color: sectionLV.itemColor || "transparent"
                    border.color: (sectionedLayout.dropTargetSectionIndex === sectionLV.origIndex && tasks.dragSource)
                        ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: (sectionedLayout.dropTargetSectionIndex === sectionLV.origIndex && tasks.dragSource) ? 2 : 0
                    radius: 4
                }

                Flow {
                    id: flowLV
                    visible: sectionLV.isSection
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
                    enabled: sectionLV.isSection
                    onTapped: function(eventPoint) {
                        var localPos = flowLV.mapFromItem(sectionLV, eventPoint.position.x, eventPoint.position.y);
                        var child = flowLV.childAt(localPos.x, localPos.y);
                        if (!child) {
                            sectionedLayout.showSectionMenu(sectionLV, sectionLV.origIndex);
                        }
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionLV.isSpacer
                    onTapped: {
                        sectionedLayout.showSpacerMenu(sectionLV, sectionLV.origIndex);
                    }
                }

                implicitHeight: isSpacer ? spacerSize : contentHeight
            }
        }

        // Fill space between top (left-floated) and bottom (right-floated) sections
        Item { Layout.fillHeight: true }

        Repeater {
            id: repeaterRightV
            model: sectionedLayout.rightItems

            delegate: Item {
                id: sectionRV
                required property var modelData
                required property int index

                readonly property int origIndex: modelData.origIndex
                readonly property var itemData: modelData.data
                readonly property bool isSection: (itemData.type || "section") === "section"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property string itemColor: itemData.color || ""
                property Item taskFlow: isSection ? flowRV : null
                readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

                readonly property real contentHeight: {
                    if (!isSection) return 0;
                    var h = 0;
                    for (var i = 0; i < flowRV.children.length; i++) {
                        var c = flowRV.children[i];
                        if (c.visible) h += c.implicitHeight;
                    }
                    return h;
                }
                Layout.fillWidth: true
                Layout.preferredHeight: isSpacer ? spacerSize : contentHeight
                Layout.maximumHeight: isSpacer ? spacerSize : contentHeight

                Rectangle {
                    visible: sectionRV.itemColor !== "" || (sectionedLayout.dropTargetSectionIndex === sectionRV.origIndex && tasks.dragSource)
                    anchors.fill: parent
                    color: sectionRV.itemColor || "transparent"
                    border.color: (sectionedLayout.dropTargetSectionIndex === sectionRV.origIndex && tasks.dragSource)
                        ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: (sectionedLayout.dropTargetSectionIndex === sectionRV.origIndex && tasks.dragSource) ? 2 : 0
                    radius: 4
                }

                Flow {
                    id: flowRV
                    visible: sectionRV.isSection
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
                    enabled: sectionRV.isSection
                    onTapped: function(eventPoint) {
                        var localPos = flowRV.mapFromItem(sectionRV, eventPoint.position.x, eventPoint.position.y);
                        var child = flowRV.childAt(localPos.x, localPos.y);
                        if (!child) {
                            sectionedLayout.showSectionMenu(sectionRV, sectionRV.origIndex);
                        }
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: sectionRV.isSpacer
                    onTapped: {
                        sectionedLayout.showSpacerMenu(sectionRV, sectionRV.origIndex);
                    }
                }

                implicitHeight: isSpacer ? spacerSize : contentHeight
            }
        }
    }

    function containerForSection(layoutIndex) {
        if (layoutIndex < 0 || layoutIndex >= layoutItems.length) return null;
        // Search both left and right repeaters
        var repeaters = tasks.vertical
            ? [repeaterLeftV, repeaterRightV]
            : [repeaterLeftH, repeaterRightH];
        for (var r = 0; r < repeaters.length; r++) {
            var rep = repeaters[r];
            for (var g = 0; g < rep.count; g++) {
                var section = rep.itemAt(g);
                if (!section) continue;
                if (section.origIndex === layoutIndex && section.isSection) {
                    return section.taskFlow;
                }
            }
        }
        return null;
    }

    readonly property Component sectionMenuComponent: Qt.createComponent("SectionMenu.qml")
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

    // ── Drop position indicator ──

    function updateDropIndicator() {
        if (dropTargetSectionIndex < 0 || dropInsertIndex < 0 || !tasks.dragSource) {
            dropIndicator.visible = false;
            return;
        }
        var container = containerForSection(dropTargetSectionIndex);
        if (!container) { dropIndicator.visible = false; return; }

        var isVert = tasks.vertical;
        var visibleTasks = [];
        for (var c = 0; c < container.children.length; c++) {
            var child = container.children[c];
            if (child && child.visible && child.appId !== undefined)
                visibleTasks.push(child);
        }
        if (visibleTasks.length === 0) { dropIndicator.visible = false; return; }

        var targetTask, pos;
        if (dropInsertIndex < visibleTasks.length) {
            targetTask = visibleTasks[dropInsertIndex];
            pos = targetTask.mapToItem(sectionedLayout, 0, 0);
        } else {
            // After the last task
            targetTask = visibleTasks[visibleTasks.length - 1];
            pos = targetTask.mapToItem(sectionedLayout,
                isVert ? 0 : targetTask.width,
                isVert ? targetTask.height : 0);
        }

        if (isVert) {
            dropIndicator.x = pos.x;
            dropIndicator.y = pos.y - 1;
            dropIndicator.width = targetTask.width;
            dropIndicator.height = 3;
        } else {
            dropIndicator.x = pos.x - 1;
            dropIndicator.y = pos.y;
            dropIndicator.width = 3;
            dropIndicator.height = targetTask.height;
        }
        dropIndicator.visible = true;
    }

    Rectangle {
        id: dropIndicator
        visible: false
        color: Kirigami.Theme.highlightColor
        radius: 1
        z: 1000
    }
}
