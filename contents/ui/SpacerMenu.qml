/*
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.Menu {
    id: spacerMenu

    property int layoutIndex: -1
    property var tasksRoot: null

    readonly property var itemData: (tasksRoot && layoutIndex >= 0 && layoutIndex < tasksRoot.parsedLayout.length)
        ? tasksRoot.parsedLayout[layoutIndex] : {}

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
            spacerMenu.destroy();
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Edit Spacer Width...")
        icon: "transform-scale"

        onClicked: {
            var root = spacerMenu.tasksRoot;
            if (!root || root.inputDialogComponent.status !== Component.Ready) return;
            var idx = spacerMenu.layoutIndex;
            var dlg = root.inputDialogComponent.createObject(root, {
                visualParent: spacerMenu.visualParent,
                visible: true,
                title: i18n("Spacer Width (px)"),
                value: spacerMenu.itemData.widthSpec || String(spacerMenu.itemData.width || 8),
                placeholderText: i18n("e.g. 20 or 5vw")
            });
            dlg.accepted.connect(function(text) {
                root.updateSpacerWidth(idx, text);
            });
        }
    }

    PlasmaExtras.MenuItem {
        text: i18n("Remove Spacer")
        icon: "edit-delete"

        onClicked: {
            spacerMenu.tasksRoot.removeLayoutItem(spacerMenu.layoutIndex);
        }
    }
}
