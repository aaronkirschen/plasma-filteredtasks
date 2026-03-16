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
    id: sectionDelegate

    required property var modelData
    required property int index

    readonly property int origIndex: modelData.origIndex
    readonly property var itemData: modelData.data
    readonly property bool isSection: (itemData.type || "section") === "section"
    readonly property bool isSpacer: itemData.type === "spacer"
    readonly property string itemColor: itemData.color || ""
    property Item taskFlow: isSection ? flow : null
    readonly property real spacerSize: isSpacer ? tasks.resolveSpacerWidth(itemData.widthSpec || String(itemData.width || 8)) : 0

    // In horizontal mode, sections size by content width; in vertical, by content height
    readonly property bool isVerticalLayout: tasks.vertical

    readonly property real contentWidth: {
        if (!isSection) return 0;
        var w = 0;
        for (var i = 0; i < flow.children.length; i++) {
            var c = flow.children[i];
            if (c.visible) w += c.implicitWidth;
        }
        return w;
    }

    readonly property real contentHeight: {
        if (!isSection) return 0;
        var h = 0;
        for (var i = 0; i < flow.children.length; i++) {
            var c = flow.children[i];
            if (c.visible) h += c.implicitHeight;
        }
        return h;
    }

    // Horizontal layout properties
    Layout.fillHeight: !isVerticalLayout
    Layout.preferredWidth: isVerticalLayout ? -1 : (isSpacer ? spacerSize : contentWidth)
    Layout.maximumWidth: isVerticalLayout ? -1 : (isSpacer ? spacerSize : contentWidth)

    // Vertical layout properties
    Layout.fillWidth: isVerticalLayout
    Layout.preferredHeight: isVerticalLayout ? (isSpacer ? spacerSize : contentHeight) : -1
    Layout.maximumHeight: isVerticalLayout ? (isSpacer ? spacerSize : contentHeight) : -1

    implicitWidth: isSpacer ? spacerSize : contentWidth
    implicitHeight: isSpacer ? spacerSize : contentHeight

    Rectangle {
        visible: sectionDelegate.itemColor !== "" || (sectionedLayout.dropTargetSectionIndex === sectionDelegate.origIndex && tasks.dragSource)
        anchors.fill: parent
        color: sectionDelegate.itemColor || "transparent"
        border.color: (sectionedLayout.dropTargetSectionIndex === sectionDelegate.origIndex && tasks.dragSource)
            ? Kirigami.Theme.highlightColor : "transparent"
        border.width: (sectionedLayout.dropTargetSectionIndex === sectionDelegate.origIndex && tasks.dragSource) ? 2 : 0
        radius: 4
    }

    Flow {
        id: flow
        visible: sectionDelegate.isSection
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
        enabled: sectionDelegate.isSection
        onTapped: function(eventPoint) {
            var localPos = flow.mapFromItem(sectionDelegate, eventPoint.position.x, eventPoint.position.y);
            var child = flow.childAt(localPos.x, localPos.y);
            if (!child) {
                sectionedLayout.showSectionMenu(sectionDelegate, sectionDelegate.origIndex);
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: sectionDelegate.isSpacer
        onTapped: {
            sectionedLayout.showSpacerMenu(sectionDelegate, sectionDelegate.origIndex);
        }
    }
}
