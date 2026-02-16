/*
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: cardRoot

    // ── Data properties ──
    property string name: ""
    property string icon: ""
    property string itemColor: ""
    property bool collapsed: false
    property bool nameEditable: true
    property bool collapsable: true
    property color outlineColor: Kirigami.Theme.disabledTextColor

    // ── Signals ──
    signal nameEdited(string newName)
    signal deleteClicked()
    signal colorClicked()
    signal moveUp()
    signal moveDown()
    property bool upEnabled: true
    property bool downEnabled: true

    // ── Drag support ──
    property Item dragTarget: null
    property alias handleArea: handleArea

    // ── Extra content below the standard row ──
    default property alias extraContent: extraContentColumn.children

    // ── Right-side extra controls (between middle and color swatch) ──
    property alias rightControls: rightControlsRow.children

    // ── Condensed info text (shown after name in collapsed mode) ──
    property string collapsedInfo: ""

    // ── Whether extra content below the standard row is visible ──
    property bool extraContentVisible: true

    // ── Card styling ──
    color: collapsed ? "transparent" : Kirigami.Theme.alternateBackgroundColor
    border.color: cardRoot.outlineColor
    border.width: 1
    radius: collapsed ? 4 : 6
    implicitHeight: cardColumn.implicitHeight + cardColumn.anchors.topMargin + cardColumn.anchors.bottomMargin

    ColumnLayout {
        id: cardColumn
        anchors.fill: parent
        anchors.leftMargin: collapsed ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
        anchors.topMargin: collapsed ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
        anchors.bottomMargin: collapsed ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ── Standard row: [handle] [up] [down] [name FILLS] [right controls] [color] [trash] ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // Drag handle
            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "handle-sort"
                    width: Kirigami.Units.iconSizes.small
                    height: Kirigami.Units.iconSizes.small
                    opacity: 0.5
                }
                MouseArea {
                    id: handleArea
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    drag.target: cardRoot.dragTarget
                    drag.axis: Drag.YAxis
                    preventStealing: true
                }
            }

            // Up
            QQC2.ToolButton {
                icon.name: "go-up"
                enabled: cardRoot.upEnabled
                onClicked: cardRoot.moveUp()
            }

            // Down
            QQC2.ToolButton {
                icon.name: "go-down"
                enabled: cardRoot.downEnabled
                onClicked: cardRoot.moveDown()
            }

            // Name — fills remaining width
            Item {
                id: nameSlot
                Layout.fillWidth: true
                implicitHeight: collapsed ? collapsedNameRow.implicitHeight : expandedNameItem.implicitHeight

                // Expanded: editable TextField or read-only Label, same position
                Item {
                    id: expandedNameItem
                    visible: !cardRoot.collapsed || !cardRoot.collapsable
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: cardRoot.nameEditable ? expandedNameField.implicitHeight : expandedNameLabel.implicitHeight

                    QQC2.TextField {
                        id: expandedNameField
                        visible: cardRoot.nameEditable
                        anchors.fill: parent
                        text: cardRoot.name
                        placeholderText: i18n("Name")
                        onEditingFinished: cardRoot.nameEdited(text)
                    }
                    QQC2.Label {
                        id: expandedNameLabel
                        visible: !cardRoot.nameEditable
                        anchors.left: parent.left
                        anchors.leftMargin: expandedNameField.leftPadding
                        anchors.verticalCenter: parent.verticalCenter
                        text: cardRoot.name
                    }
                }

                // Collapsed: icon + label + info
                RowLayout {
                    id: collapsedNameRow
                    visible: cardRoot.collapsed && cardRoot.collapsable
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: cardRoot.icon
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        opacity: cardRoot.icon !== "" ? 0.5 : 0
                    }
                    QQC2.Label {
                        text: cardRoot.name
                    }
                    QQC2.Label {
                        visible: cardRoot.collapsedInfo !== ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                        text: cardRoot.collapsedInfo
                    }
                }
            }

            // Right-side controls slot — vertically centered
            RowLayout {
                id: rightControlsRow
                spacing: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignVCenter
                visible: {
                    for (var i = 0; i < children.length; i++) {
                        if (children[i].visible) return true;
                    }
                    return false;
                }
            }

            // Color swatch
            Rectangle {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 4
                color: cardRoot.itemColor || "transparent"
                border.color: Kirigami.Theme.textColor
                border.width: 1
                MouseArea {
                    anchors.fill: parent
                    onClicked: cardRoot.colorClicked()
                }
            }

            // Delete
            QQC2.ToolButton {
                icon.name: "edit-delete"
                Layout.alignment: Qt.AlignVCenter
                QQC2.ToolTip.text: i18n("Delete")
                QQC2.ToolTip.visible: hovered
                onClicked: cardRoot.deleteClicked()
            }
        }

        // Extra content slot (app list, etc.)
        ColumnLayout {
            id: extraContentColumn
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: cardRoot.extraContentVisible
        }
    }
}
