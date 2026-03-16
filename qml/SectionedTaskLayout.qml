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
        var repeaters = _allRepeaters();
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

    // ── Helpers ──

    // Returns the pair of repeaters for the current orientation
    function _allRepeaters() {
        return tasks.vertical
            ? [repeaterLeftV, repeaterRightV]
            : [repeaterLeftH, repeaterRightH];
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

    // Check if an app should be excluded by exclusive mode
    function _isExcludedByOthers(appId) {
        if (!Plasmoid.configuration.exclusiveMode) return false;
        var excluded = tasks.excludedByOthers;
        if (!excluded) return false;
        for (var k = 0; k < excluded.length; k++) {
            if (excluded[k] === appId) return true;
        }
        return false;
    }

    function reparentTask(task) {
        var sectionIdx = sectionForApp(task.appId);
        if (sectionIdx < 0) {
            task.visible = false;
            return;
        }

        var isUnsectioned = layoutItems[sectionIdx].name === "__unsectioned";
        if (isUnsectioned && _isExcludedByOthers(task.appId)) {
            task.visible = false;
            return;
        }

        var container = containerForSection(sectionIdx);
        if (container && task.parent !== container) {
            task.oldX = -1;
            task.oldY = -1;
            task.parent = container;
        }
        task.visible = true;
        task.sectionIndex = sectionIdx;
    }

    // Build sort key for a task within a section's appIds order
    function _buildOrderMap(appIds) {
        var orderMap = {};
        for (var a = 0; a < appIds.length; a++) {
            orderMap[appIds[a]] = a;
        }
        return orderMap;
    }

    // Sort tasks by appIds order, then by model index for unlisted ones
    function _sortTasks(taskList, orderMap) {
        taskList.sort(function(a, b) {
            var oa = (a.appId in orderMap) ? orderMap[a.appId] : 999999 + a.index;
            var ob = (b.appId in orderMap) ? orderMap[b.appId] : 999999 + b.index;
            return oa - ob;
        });
    }

    // Detach tasks to taskList then re-add to container in order (controls Flow ordering)
    function _reorderIntoContainer(taskList, container) {
        for (var d = 0; d < taskList.length; d++) {
            taskList[d].oldX = -1;
            taskList[d].oldY = -1;
            taskList[d].parent = tasks.taskList;
        }
        for (var r = 0; r < taskList.length; r++) {
            taskList[r].oldX = -1;
            taskList[r].oldY = -1;
            taskList[r].parent = container;
        }
    }

    function reparentAllTasks() {
        // Build a map of sectionIdx -> sorted task list
        var sectionTasks = {};
        for (var i = 0; i < tasks.taskRepeater.count; i++) {
            var task = tasks.taskRepeater.itemAt(i);
            if (!task) continue;
            var sectionIdx = sectionForApp(task.appId);
            if (sectionIdx < 0) {
                task.visible = false;
                continue;
            }

            var isUnsectioned = layoutItems[sectionIdx].name === "__unsectioned";
            if (isUnsectioned && _isExcludedByOthers(task.appId)) {
                task.visible = false;
                continue;
            }

            task.visible = true;
            task.sectionIndex = sectionIdx;
            if (!sectionTasks[sectionIdx]) sectionTasks[sectionIdx] = [];
            sectionTasks[sectionIdx].push(task);
        }

        // For each section, sort tasks by appIds order, then reparent only if needed
        for (var sectionIdx in sectionTasks) {
            var container = containerForSection(parseInt(sectionIdx));
            if (!container) continue;
            var tasksInSection = sectionTasks[sectionIdx];
            var itemData = layoutItems[parseInt(sectionIdx)] || {};
            var appIds = itemData.appIds || [];
            var orderMap = _buildOrderMap(appIds);

            _sortTasks(tasksInSection, orderMap);

            // Check if all tasks are already in the correct container and order
            var needsReorder = tasksInSection.length > 0 && tasksInSection[0].parent !== container;
            if (!needsReorder) {
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
                _reorderIntoContainer(tasksInSection, container);
            }
        }
    }

    // Return the visual index of a task within its parent Flow (0-based)
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
    function moveAppIdToPosition(sectionIdx, appId, targetAppId) {
        var itemData = layoutItems[sectionIdx];
        if (!itemData) return false;
        var ids = itemData.appIds || [];
        var fromIdx = ids.indexOf(appId);
        var toIdx = ids.indexOf(targetAppId);
        if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return false;
        ids.splice(fromIdx, 1);
        ids.splice(toIdx, 0, appId);
        _dragDirty = true;
        return true;
    }

    // Reorder a single section's Flow children to match current appIds order.
    function reorderSectionFlow(sectionIdx) {
        var container = containerForSection(sectionIdx);
        if (!container) return;
        var itemData = layoutItems[sectionIdx] || {};
        var appIds = itemData.appIds || [];
        if (appIds.length < 2) return;

        var orderMap = _buildOrderMap(appIds);

        // Collect task children of this Flow
        var children = [];
        for (var c = 0; c < container.children.length; c++) {
            var child = container.children[c];
            if (child && child.appId !== undefined) {
                children.push(child);
            }
        }
        if (children.length < 2) return;

        _sortTasks(children, orderMap);
        _reorderIntoContainer(children, container);
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
                sectionedLayout._dragDirty = false;
                sectionedLayout.persistLayout();
            }
            if (!tasks.dragSource) {
                sectionedLayout.dropInsertIndex = -1;
                dropIndicator.visible = false;
            }
        }
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
        var repeaters = _allRepeaters();
        var result = _searchRepeaterForTask(repeaters[0], x, y, isDragging, isVert);
        if (result) return result;
        return _searchRepeaterForTask(repeaters[1], x, y, isDragging, isVert);
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
        var repeaters = _allRepeaters();
        var result = _searchRepeaterForSection(repeaters[0], x, y);
        if (result >= 0) return result;
        return _searchRepeaterForSection(repeaters[1], x, y);
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
            delegate: SectionDelegate {}
        }

        // Fill space between left and right sections
        Item { Layout.fillWidth: true }

        Repeater {
            id: repeaterRightH
            model: sectionedLayout.rightItems
            delegate: SectionDelegate {}
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
            delegate: SectionDelegate {}
        }

        // Fill space between top (left-floated) and bottom (right-floated) sections
        Item { Layout.fillHeight: true }

        Repeater {
            id: repeaterRightV
            model: sectionedLayout.rightItems
            delegate: SectionDelegate {}
        }
    }

    function containerForSection(layoutIndex) {
        if (layoutIndex < 0 || layoutIndex >= layoutItems.length) return null;
        var repeaters = _allRepeaters();
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
