/*
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmaCore.PopupPlasmaWindow {
    id: inputDialog

    property string title: ""
    property string value: ""
    property string placeholderText: ""

    signal accepted(string text)
    signal cancelled()

    width: Kirigami.Units.gridUnit * 16
    height: contentLayout.implicitHeight + topPadding + bottomPadding

    animated: true
    removeBorderStrategy: Plasmoid.location === PlasmaCore.Types.Floating
            ? PlasmaCore.AppletPopup.AtScreenEdges
            : PlasmaCore.AppletPopup.AtScreenEdges | PlasmaCore.AppletPopup.AtPanelEdges

    margin: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersFloatingApplets) ? Kirigami.Units.largeSpacing : 0

    popupDirection: switch (Plasmoid.location) {
        case PlasmaCore.Types.TopEdge:
            return Qt.BottomEdge
        case PlasmaCore.Types.LeftEdge:
            return Qt.RightEdge
        case PlasmaCore.Types.RightEdge:
            return Qt.LeftEdge
        default:
            return Qt.TopEdge
    }

    property bool _submitted: false

    onActiveChanged: {
        if (!active && !_submitted) {
            _deactivateTimer.start();
        }
    }

    Timer {
        id: _deactivateTimer
        interval: 150
        onTriggered: {
            if (!inputDialog.active && !inputDialog._submitted) {
                inputDialog.cancelled();
                inputDialog.visible = false;
            }
        }
    }

    onVisibleChanged: {
        if (!visible) {
            inputDialog.destroy();
        }
    }

    function _submit() {
        _submitted = true;
        inputDialog.accepted(inputField.text);
        inputDialog.visible = false;
    }

    function _cancel() {
        _submitted = true;
        inputDialog.cancelled();
        inputDialog.visible = false;
    }

    Component.onCompleted: {
        inputField.text = value;
        inputField.selectAll();
        inputField.forceActiveFocus();
    }

    ColumnLayout {
        id: contentLayout
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 4
            text: inputDialog.title
            visible: text !== ""
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.TextField {
                id: inputField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                placeholderText: inputDialog.placeholderText

                onAccepted: inputDialog._submit()
                Keys.onEscapePressed: inputDialog._cancel()
            }

            PlasmaComponents3.Button {
                icon.name: "dialog-ok"
                onClicked: inputDialog._submit()
            }

            PlasmaComponents3.Button {
                icon.name: "dialog-cancel"
                onClicked: inputDialog._cancel()
            }
        }
    }
}
