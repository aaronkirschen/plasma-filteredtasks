/*
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.Menu {
    id: sectionMenu

    property int layoutIndex: -1
    property var tasksRoot: null

    readonly property var itemData: (tasksRoot && layoutIndex >= 0 && layoutIndex < tasksRoot.parsedLayout.length)
        ? tasksRoot.parsedLayout[layoutIndex] : {}
    readonly property bool isUngrouped: (itemData.name || "") === "__ungrouped"

    placement: {
        if (Plasmoid.location === PlasmaCore.Types.LeftEdge) {
            return PlasmaExtras.Menu.RightPosedTopAlignedPopup;
        } else if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
            return PlasmaExtras.Menu.BottomPosedLeftAlignedPopup;
        } else if (Plasmoid.location === PlasmaCore.Types.RightEdge) {
            return PlasmaExtras.Menu.LeftPosedTopAlignedPopup;
        } else {
            return PlasmaExtras.Menu.TopPosedLeftAlignedPopup;
        }
    }

    onStatusChanged: {
        if (status === PlasmaExtras.Menu.Closed) {
            sectionMenu.destroy();
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Rename Group...")
        icon: "edit-rename"
        visible: !sectionMenu.isUngrouped

        onClicked: {
            var root = sectionMenu.tasksRoot;
            if (!root || root.inputDialogComponent.status !== Component.Ready) return;
            var idx = sectionMenu.layoutIndex;
            var dlg = root.inputDialogComponent.createObject(root, {
                visualParent: sectionMenu.visualParent,
                visible: true,
                title: i18n("Rename Group"),
                value: sectionMenu.itemData.name || "",
                placeholderText: i18n("Enter group name...")
            });
            dlg.accepted.connect(function(text) {
                root.renameGroup(idx, text);
            });
        }
    }

    PlasmaExtras.MenuItem {
        readonly property bool isRight: (sectionMenu.itemData["float"] || "left") === "right"
        text: isRight ? i18n("Float Left") : i18n("Float Right")
        icon: isRight ? "align-horizontal-left" : "align-horizontal-right"

        onClicked: {
            sectionMenu.tasksRoot.setGroupFloat(sectionMenu.layoutIndex, isRight ? "left" : "right");
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Remove Group")
        icon: "edit-delete"
        visible: !sectionMenu.isUngrouped

        onClicked: {
            sectionMenu.tasksRoot.removeLayoutItem(sectionMenu.layoutIndex);
        }
    }

    PlasmaExtras.MenuItem {
        separator: true
        visible: !sectionMenu.isUngrouped
    }

    PlasmaExtras.MenuItem {
        text: i18n("Add Spacer Before")
        icon: "distribute-horizontal"

        onClicked: {
            sectionMenu.tasksRoot.addSpacerAt(sectionMenu.layoutIndex);
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Add Spacer After")
        icon: "distribute-horizontal"

        onClicked: {
            sectionMenu.tasksRoot.addSpacerAt(sectionMenu.layoutIndex + 1);
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Add Group Before...")
        icon: "list-add"

        onClicked: {
            var root = sectionMenu.tasksRoot;
            if (!root || root.inputDialogComponent.status !== Component.Ready) return;
            var idx = sectionMenu.layoutIndex;
            var dlg = root.inputDialogComponent.createObject(root, {
                visualParent: sectionMenu.visualParent,
                visible: true,
                title: i18n("Group Name"),
                value: "New Group",
                placeholderText: i18n("Enter group name...")
            });
            dlg.accepted.connect(function(text) {
                root.addGroupAt(idx, text);
            });
        }
    }

    PlasmaExtras.MenuItem {
        separator: true
    }

    PlasmaExtras.MenuItem {
        property QtObject configureAction: null

        enabled: configureAction && configureAction.enabled
        visible: configureAction && configureAction.visible

        text: configureAction ? configureAction.text : ""
        icon: configureAction ? configureAction.icon : ""

        onClicked: configureAction.trigger()

        Component.onCompleted: configureAction = Plasmoid.internalAction("configure")
    }
}
