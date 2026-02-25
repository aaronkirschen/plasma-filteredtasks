/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasmoid

import "code/tools.js" as TaskTools

DropArea {
    id: dropArea
    signal urlsDropped(var urls)

    property Item target
    property Item ignoredItem
    property Item hoveredItem
    property bool isGroupDialog: false
    property bool moved: false

    property alias handleWheelEvents: wheelHandler.handleWheelEvents

    //ignore anything that is neither internal to TaskManager or a URL list
    onEntered: event => {
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
        }
        if (target.animating) { // Not all targets have an animating property
            target.animating = false;
        }
    }

    onPositionChanged: event => {
        if (target.animating) {
            return;
        }

        let above;
        if (isGroupDialog) {
            above = target.itemAt(event.x, event.y);
        } else if (tasks.groupedMode) {
            var mapped = tasks.groupedLayout.mapFromItem(dropArea, event.x, event.y);
            above = tasks.groupedLayout.taskAtPosition(mapped.x, mapped.y);
        } else {
            above = target.childAt(event.x, event.y);
        }

        if (!above) {
            if (tasks.groupedMode && tasks.dragSource) {
                var mappedPos = tasks.groupedLayout.mapFromItem(dropArea, event.x, event.y);
                var targetIdx = tasks.groupedLayout.groupIndexAtPosition(mappedPos.x, mappedPos.y);
                tasks.groupedLayout.dropTargetGroupIndex = targetIdx;
                if (targetIdx >= 0 && tasks.dragSource.groupIndex >= 0
                    && tasks.dragSource.groupIndex !== targetIdx) {
                    tasks.moveAppToGroup(tasks.dragSource.appId, tasks.dragSource.groupIndex, targetIdx);
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

        if (tasks.groupedMode && tasks.dragSource && above.groupIndex >= 0) {
            tasks.groupedLayout.dropTargetGroupIndex = above.groupIndex;
        }

        if (tasksModel.sortMode === TaskManager.TasksModel.SortManual && tasks.dragSource) {
            // Handle drags between different groups in grouped mode.
            if (tasks.dragSource.parent !== above.parent) {
                if (tasks.groupedMode && tasks.dragSource.groupIndex >= 0
                    && above.groupIndex >= 0 && tasks.dragSource.groupIndex !== above.groupIndex) {
                    tasks.moveAppToGroup(tasks.dragSource.appId, tasks.dragSource.groupIndex, above.groupIndex);
                }
                return;
            }

            const insertAt = above.index;

            if (tasks.dragSource !== above && tasks.dragSource.index !== insertAt) {
                const fromIndex = tasks.dragSource.index;

                if (tasks.groupedMode) {
                    // In grouped mode, skip tasksModel.move() — the Repeater's
                    // internal stackBefore/stackAfter fails when delegates have
                    // been reparented into Flow containers. Instead, update
                    // appIds order in config (persists + syncs) and do an
                    // immediate visual reorder of this group's Flow.
                    tasks.reorderAppInGroup(tasks.dragSource.groupIndex,
                        tasks.dragSource.appId, above.appId,
                        fromIndex < insertAt);
                    tasks.groupedLayout.reorderGroupFlow(tasks.dragSource.groupIndex);
                } else if (tasks.groupDialog) {
                    tasksModel.move(fromIndex, insertAt,
                        tasksModel.makeModelIndex(tasks.groupDialog.visualParent.index));
                } else {
                    tasksModel.move(fromIndex, insertAt);
                }

                ignoredItem = above;
                ignoreItemTimer.restart();
            }
        } else if (!tasks.dragSource && hoveredItem !== above) {
            hoveredItem = above;
            activationTimer.restart();
        }
    }

    onExited: {
        hoveredItem = null;
        activationTimer.stop();
        if (tasks.groupedMode) {
            tasks.groupedLayout.dropTargetGroupIndex = -1;
        }
    }

    onDropped: event => {
        if (tasks.groupedMode) {
            tasks.groupedLayout.dropTargetGroupIndex = -1;
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
