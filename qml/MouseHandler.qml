/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasmoid

import "tools.js" as TaskTools

DropArea {
    id: dropArea
    signal urlsDropped(var urls)

    property Item target
    property Item ignoredItem
    property Item hoveredItem
    property bool isGroupDialog: false
    property bool moved: false
    property point dragStartPos: Qt.point(-1, -1)
    property bool dragMovedPastThreshold: false

    property alias handleWheelEvents: wheelHandler.handleWheelEvents

    //ignore anything that is neither internal to TaskManager or a URL list
    onEntered: event => {
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
        }
        if (target.animating) { // Not all targets have an animating property
            target.animating = false;
        }
        dragStartPos = Qt.point(event.x, event.y);
        dragMovedPastThreshold = false;
    }

    onPositionChanged: event => {
        if (target.animating) {
            return;
        }

        // Skip reorder logic until cursor has moved a minimum distance from drag start
        if (tasks.sectionedMode && tasks.dragSource && !dragMovedPastThreshold) {
            var dx = event.x - dragStartPos.x;
            var dy = event.y - dragStartPos.y;
            if (dx * dx + dy * dy < 25) { // 5px threshold
                return;
            }
            dragMovedPastThreshold = true;
        }

        let above;
        if (isGroupDialog) {
            above = target.itemAt(event.x, event.y);
        } else if (tasks.sectionedMode) {
            var mapped = tasks.sectionedLayout.mapFromItem(dropArea, event.x, event.y);
            above = tasks.sectionedLayout.taskAtPosition(mapped.x, mapped.y);
        } else {
            above = target.childAt(event.x, event.y);
        }

        if (!above) {
            if (tasks.sectionedMode && tasks.dragSource) {
                var mappedPos = tasks.sectionedLayout.mapFromItem(dropArea, event.x, event.y);
                var targetIdx = tasks.sectionedLayout.sectionIndexAtPosition(mappedPos.x, mappedPos.y);
                tasks.sectionedLayout.dropTargetSectionIndex = targetIdx;
                tasks.sectionedLayout.dropInsertIndex = -1;
                tasks.sectionedLayout.updateDropIndicator();
                if (targetIdx >= 0 && tasks.dragSource.sectionIndex >= 0
                    && tasks.dragSource.sectionIndex !== targetIdx) {
                    tasks.moveAppToSection(tasks.dragSource.appId, tasks.dragSource.sectionIndex, targetIdx);
                }
            }
            hoveredItem = null;
            activationTimer.stop();

            return;
        }

        // If we're mixing launcher tasks with other tasks and are moving
        // a (small) launcher task across a non-launcher task, don't allow
        // the latter to be the move target twice in a row for a while, as
        // it will naturally be moved underneath the cursor as result of the
        // initial move, due to being far larger than the launcher delegate.
        // TODO: This restriction (minus the timer, which improves things)
        // has been proven out in the EITM fork, but could be improved later
        // by tracking the cursor movement vector and allowing the drag if
        // the movement direction has reversed, establishing user intent to
        // move back.
        if (!Plasmoid.configuration.separateLaunchers
                && tasks.dragSource?.model.IsLauncher
                && !above.model.IsLauncher
                && above === ignoredItem) {
            return;
        } else {
            ignoredItem = null;
        }

        if (tasks.sectionedMode && tasks.dragSource && above.sectionIndex >= 0) {
            tasks.sectionedLayout.dropTargetSectionIndex = above.sectionIndex;
        }

        if (tasksModel.sortMode === TaskManager.TasksModel.SortManual && tasks.dragSource) {
            if (tasks.sectionedMode) {
                // ── Sectioned mode drag: use visual position, not model index ──

                // Cross-section drag
                if (tasks.dragSource.parent !== above.parent) {
                    if (tasks.dragSource.sectionIndex >= 0
                        && above.sectionIndex >= 0 && tasks.dragSource.sectionIndex !== above.sectionIndex) {
                        tasks.moveAppToSection(tasks.dragSource.appId, tasks.dragSource.sectionIndex, above.sectionIndex);
                    }
                    tasks.sectionedLayout.dropInsertIndex = -1;
                    tasks.sectionedLayout.updateDropIndicator();
                    return;
                }

                // Same-section drag: compare visual positions within the Flow
                if (tasks.dragSource !== above) {
                    tasks.sectionedLayout.dropInsertIndex = tasks.sectionedLayout.visualIndexInFlow(above);
                    if (tasks.sectionedLayout.moveAppIdToPosition(
                            tasks.dragSource.sectionIndex, tasks.dragSource.appId, above.appId)) {
                        tasks.sectionedLayout.reorderSectionFlow(tasks.dragSource.sectionIndex);
                    }
                    tasks.sectionedLayout.updateDropIndicator();
                } else {
                    tasks.sectionedLayout.dropInsertIndex = tasks.sectionedLayout.visualIndexInFlow(above);
                    tasks.sectionedLayout.updateDropIndicator();
                }
            } else {
                // ── Non-sectioned mode drag: use model index ──

                // Different parent check (shouldn't happen without sectionedMode, but kept for safety)
                if (tasks.dragSource.parent !== above.parent) {
                    return;
                }

                const insertAt = above.index;
                if (tasks.dragSource !== above && tasks.dragSource.index !== insertAt) {
                    const fromIndex = tasks.dragSource.index;
                    if (tasks.groupDialog) {
                        tasksModel.move(fromIndex, insertAt,
                            tasksModel.makeModelIndex(tasks.groupDialog.visualParent.index));
                    } else {
                        tasksModel.move(fromIndex, insertAt);
                    }

                    ignoredItem = above;
                    ignoreItemTimer.restart();
                }
            }
        } else if (!tasks.dragSource && hoveredItem !== above) {
            hoveredItem = above;
            activationTimer.restart();
        }
    }

    onExited: {
        hoveredItem = null;
        activationTimer.stop();
        if (tasks.sectionedMode) {
            tasks.sectionedLayout.dropTargetSectionIndex = -1;
            tasks.sectionedLayout.dropInsertIndex = -1;
            tasks.sectionedLayout.updateDropIndicator();
        }
    }

    onDropped: event => {
        if (tasks.sectionedMode) {
            tasks.sectionedLayout.dropTargetSectionIndex = -1;
            tasks.sectionedLayout.dropInsertIndex = -1;
            tasks.sectionedLayout.updateDropIndicator();
        }
        // Reject internal drops.
        if (event.formats.indexOf("application/x-orgkdeplasmataskmanager_taskbuttonitem") >= 0) {
            event.accepted = false;
            return;
        }

        // Reject plasmoid drops.
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
            return;
        }

        if (event.hasUrls) {
            urlsDropped(event.urls);
            return;
        }
    }

    Connections {
        target: tasks

        function onDragSourceChanged(): void {
            if (!dragSource) {
                ignoredItem = null;
                ignoreItemTimer.stop();
                dragMovedPastThreshold = false;
                dragStartPos = Qt.point(-1, -1);
            }
        }
    }

    Timer {
        id: ignoreItemTimer

        repeat: false
        interval: 750

        onTriggered: {
            ignoredItem = null;
        }
    }

    Timer {
        id: activationTimer

        interval: 250
        repeat: false

        onTriggered: {
            if (parent.hoveredItem.model.IsGroupParent) {
                TaskTools.createGroupDialog(parent.hoveredItem, tasks);
            } else if (!parent.hoveredItem.model.IsLauncher) {
                tasksModel.requestActivate(parent.hoveredItem.modelIndex());
            }
        }
    }

    WheelHandler {
        id: wheelHandler

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property bool handleWheelEvents: true

        enabled: handleWheelEvents && Plasmoid.configuration.wheelEnabled !== 0

        onWheel: event => {
            // magic number 15 for common "one scroll"
            // See https://doc.qt.io/qt-6/qml-qtquick-wheelhandler.html#rotation-prop
            let increment = 0;
            while (rotation >= 15) {
                rotation -= 15;
                increment++;
            }
            while (rotation <= -15) {
                rotation += 15;
                increment--;
            }
            const anchor = dropArea.target.childAt(event.x, event.y);
            while (increment !== 0) {
                TaskTools.activateNextPrevTask(anchor, increment < 0, Plasmoid.configuration.wheelSkipMinimized, Plasmoid.configuration.wheelEnabled, tasks);
                increment += (increment < 0) ? 1 : -1;
            }
        }
    }
}
