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
    readonly property bool isCatchAll: itemData.catchAll === true

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
        text: i18n("Rename Section...")
        icon: "edit-rename"
        visible: !sectionMenu.isCatchAll

        onClicked: {
            var root = sectionMenu.tasksRoot;
            if (!root || root.inputDialogComponent.status !== Component.Ready) return;
            var idx = sectionMenu.layoutIndex;
            var dlg = root.inputDialogComponent.createObject(root, {
                visualParent: sectionMenu.visualParent,
                visible: true,
                title: i18n("Rename Section"),
                value: sectionMenu.itemData.name || "",
                placeholderText: i18n("Enter section name...")
            });
            dlg.accepted.connect(function(text) {
                root.renameSection(idx, text);
            });
        }
    }

    PlasmaExtras.MenuItem {
        readonly property bool isRight: (sectionMenu.itemData["float"] || "left") === "right"
        text: isRight ? i18n("Float Left") : i18n("Float Right")
        icon: isRight ? "align-horizontal-left" : "align-horizontal-right"

        onClicked: {
            sectionMenu.tasksRoot.setSectionFloat(sectionMenu.layoutIndex, isRight ? "left" : "right");
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Remove Section")
        icon: "edit-delete"
        visible: !sectionMenu.isCatchAll

        onClicked: {
            sectionMenu.tasksRoot.removeLayoutItem(sectionMenu.layoutIndex);
        }
    }

    PlasmaExtras.MenuItem {
        separator: true
        visible: !sectionMenu.isCatchAll
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
        text: i18n("Add Section Before...")
        icon: "list-add"

        onClicked: {
            var root = sectionMenu.tasksRoot;
            if (!root || root.inputDialogComponent.status !== Component.Ready) return;
            var idx = sectionMenu.layoutIndex;
            var dlg = root.inputDialogComponent.createObject(root, {
                visualParent: sectionMenu.visualParent,
                visible: true,
                title: i18n("Section Name"),
                value: "New Section",
                placeholderText: i18n("Enter section name...")
            });
            dlg.accepted.connect(function(text) {
                root.addSectionAt(idx, text);
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
