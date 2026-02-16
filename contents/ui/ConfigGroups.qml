/*
    SPDX-FileCopyrightText: 2024 Filtered Task Manager fork
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.folderlistmodel
import Qt.labs.settings as LabSettings

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: root

    property string cfg_taskGroups
    property string cfg_filterAppIds
    property bool cfg_exclusiveMode

    property var layoutItems: []
    property bool _loading: true

    // Write config on every change so the Apply button activates immediately
    onLayoutItemsChanged: {
        if (_loading) return;
        cfg_taskGroups = JSON.stringify(layoutItems);
        // Sync filterAppIds for backward compat
        var allIds = [];
        for (var i = 0; i < layoutItems.length; i++) {
            var item = layoutItems[i];
            if (item.type !== "group" || item.name === "__ungrouped") continue;
            var ids = item.appIds || [];
            for (var j = 0; j < ids.length; j++) {
                if (allIds.indexOf(ids[j]) < 0) allIds.push(ids[j]);
            }
        }
        cfg_filterAppIds = allIds.join(",");
    }

    Component.onCompleted: {
        _loading = true;
        var parsed = [];
        if (cfg_taskGroups && cfg_taskGroups.trim() !== "") {
            try { parsed = JSON.parse(cfg_taskGroups); }
            catch (e) { parsed = []; }
        }
        if (parsed.length === 0) {
            parsed = [{type: "group", name: "__ungrouped", appIds: [], color: ""}];
        }
        layoutItems = parsed;
        _loading = false;
        scanDebounce.start();
    }

    // ── Helpers ──
    readonly property bool hasUngrouped: {
        for (var i = 0; i < layoutItems.length; i++) {
            if (layoutItems[i].type === "group" && layoutItems[i].name === "__ungrouped") return true;
        }
        return false;
    }

    // ── App scanning ──
    property string searchQuery: ""
    property bool appsLoaded: false
    ListModel { id: allAppsModel }

    readonly property string homeDir: {
        var url = Qt.resolvedUrl(".").toString();
        var m = url.match(/^file:\/\/(\/[^\/]+\/[^\/]+)\//);
        return m ? m[1] : "";
    }

    FolderListModel {
        id: systemApps
        folder: "file:///usr/share/applications"
        nameFilters: ["*.desktop"]; showDirs: false
    }
    Instantiator {
        id: systemInst; model: systemApps
        delegate: QtObject { required property string fileName }
        onCountChanged: scanDebounce.restart()
    }
    FolderListModel {
        id: localApps
        folder: root.homeDir !== "" ? ("file://" + root.homeDir + "/.local/share/applications") : "file:///nonexistent"
        nameFilters: ["*.desktop"]; showDirs: false
    }
    Instantiator {
        id: localInst; model: localApps
        delegate: QtObject { required property string fileName }
        onCountChanged: scanDebounce.restart()
    }
    FolderListModel {
        id: flatpakApps
        folder: "file:///var/lib/flatpak/exports/share/applications"
        nameFilters: ["*.desktop"]; showDirs: false
    }
    Instantiator {
        id: flatpakInst; model: flatpakApps
        delegate: QtObject { required property string fileName }
        onCountChanged: scanDebounce.restart()
    }

    Component {
        id: desktopReaderComponent
        LabSettings.Settings { category: "Desktop Entry" }
    }

    function readDesktopEntry(filePath) {
        var reader;
        try { reader = desktopReaderComponent.createObject(root, { fileName: filePath }); }
        catch (e) { return null; }
        if (!reader) return null;
        var type = String(reader.value("Type", ""));
        if (type !== "Application") { reader.destroy(); return null; }
        var noDisplay = String(reader.value("NoDisplay", "false"));
        var hidden = String(reader.value("Hidden", "false"));
        if (noDisplay === "true" || hidden === "true") { reader.destroy(); return null; }
        var result = {
            name: String(reader.value("Name", "")),
            icon: String(reader.value("Icon", "application-x-executable")),
            genericName: String(reader.value("GenericName", "")),
            comment: String(reader.value("Comment", ""))
        };
        reader.destroy();
        return result;
    }

    function processInstantiator(inst, dirPath, map) {
        for (var i = 0; i < inst.count; i++) {
            var obj = inst.objectAt(i);
            if (!obj) continue;
            var fn = obj.fileName;
            if (!fn || !fn.endsWith(".desktop")) continue;
            var appId = fn.replace(/\.desktop$/, "");
            if (map.hasOwnProperty(appId)) continue;
            var info = readDesktopEntry(dirPath + fn);
            if (!info) continue;
            map[appId] = { appId: appId, name: info.name || appId, genericName: info.genericName || "", icon: info.icon || "application-x-executable", comment: info.comment || "" };
        }
    }

    function scanAllApps() {
        var map = {};
        if (root.homeDir !== "") processInstantiator(localInst, root.homeDir + "/.local/share/applications/", map);
        processInstantiator(flatpakInst, "/var/lib/flatpak/exports/share/applications/", map);
        processInstantiator(systemInst, "/usr/share/applications/", map);
        var list = [];
        for (var id in map) list.push(map[id]);
        list.sort(function(a, b) { return a.name.localeCompare(b.name); });
        allAppsModel.clear();
        for (var i = 0; i < list.length; i++) allAppsModel.append(list[i]);
        appsLoaded = true;
    }

    Timer { id: scanDebounce; interval: 500; onTriggered: root.scanAllApps() }

    function appDisplayName(appId) {
        for (var i = 0; i < allAppsModel.count; i++) {
            if (allAppsModel.get(i).appId === appId) return allAppsModel.get(i).name;
        }
        return appId;
    }

    function appIconName(appId) {
        for (var i = 0; i < allAppsModel.count; i++) {
            if (allAppsModel.get(i).appId === appId) return allAppsModel.get(i).icon;
        }
        return "application-x-executable";
    }

    property int pickerTargetGroup: -1

    // ── UI ──
    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.largeSpacing

        // ── Exclusive mode ──
        QQC2.CheckBox {
            checked: cfg_exclusiveMode
            text: i18n("Exclusive mode")
            onToggled: cfg_exclusiveMode = checked
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("When enabled, apps assigned to groups in this widget won't appear in other Filtered Task Manager widgets.")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── Panel layout heading ──
        Kirigami.Heading {
            level: 3
            text: i18n("Panel Layout")
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Arrange groups and spacers in the order they appear on the panel.")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }

        // ── Layout item list ──
        Repeater {
            id: layoutRepeater
            model: root.layoutItems.length

            delegate: ColumnLayout {
                id: itemDelegate
                required property int index

                readonly property var itemData: root.layoutItems[index] || {}
                readonly property bool isGroup: (itemData.type || "group") === "group"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property bool isUngrouped: isGroup && itemData.name === "__ungrouped"

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                // ════════════════════════════════════
                // Spacer item card
                // ════════════════════════════════════
                Rectangle {
                    visible: itemDelegate.isSpacer
                    Layout.fillWidth: true
                    implicitHeight: spacerContent.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: "transparent"
                    border.color: Qt.darker(Kirigami.Theme.backgroundColor, 1.08)
                    border.width: 1
                    radius: 4

                    RowLayout {
                        id: spacerContent
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.ToolButton {
                            icon.name: "go-up"
                            enabled: itemDelegate.index > 0
                            onClicked: {
                                var items = root.layoutItems.slice();
                                var tmp = items[itemDelegate.index];
                                items[itemDelegate.index] = items[itemDelegate.index - 1];
                                items[itemDelegate.index - 1] = tmp;
                                root.layoutItems = items;
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: "go-down"
                            enabled: itemDelegate.index < root.layoutItems.length - 1
                            onClicked: {
                                var items = root.layoutItems.slice();
                                var tmp = items[itemDelegate.index];
                                items[itemDelegate.index] = items[itemDelegate.index + 1];
                                items[itemDelegate.index + 1] = tmp;
                                root.layoutItems = items;
                            }
                        }

                        Kirigami.Icon {
                            source: "spacer"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            opacity: 0.5
                        }
                        QQC2.Label {
                            text: i18n("Spacer")
                            opacity: 0.7
                        }
                        Item { Layout.fillWidth: true }
                        QQC2.Label {
                            text: i18n("Width:")
                            opacity: 0.6
                        }
                        QQC2.SpinBox {
                            from: 1; to: 128
                            value: itemDelegate.itemData.width || 8
                            onValueModified: {
                                var items = root.layoutItems.slice();
                                items[itemDelegate.index] = Object.assign({}, items[itemDelegate.index], {width: value});
                                root.layoutItems = items;
                            }
                        }
                        QQC2.Label {
                            text: i18n("px")
                            opacity: 0.5
                        }
                        Rectangle {
                            width: 24; height: 24
                            radius: 4
                            color: itemDelegate.itemData.color || "transparent"
                            border.color: Kirigami.Theme.textColor
                            border.width: 1

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    colorDialog.targetIndex = itemDelegate.index;
                                    colorDialog.selectedColor = itemDelegate.itemData.color || "#00000000";
                                    colorDialog.open();
                                }
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            QQC2.ToolTip.text: i18n("Remove spacer")
                            QQC2.ToolTip.visible: hovered
                            onClicked: {
                                var items = root.layoutItems.slice();
                                items.splice(itemDelegate.index, 1);
                                root.layoutItems = items;
                            }
                        }
                    }
                }

                // ════════════════════════════════════
                // Group item card
                // ════════════════════════════════════
                Rectangle {
                    visible: itemDelegate.isGroup
                    Layout.fillWidth: true
                    implicitHeight: groupContent.implicitHeight + Kirigami.Units.largeSpacing * 2
                    color: itemDelegate.isUngrouped
                        ? Qt.lighter(Kirigami.Theme.alternateBackgroundColor, 1.05)
                        : Kirigami.Theme.alternateBackgroundColor
                    border.color: itemDelegate.isUngrouped
                        ? Kirigami.Theme.disabledTextColor
                        : Qt.darker(Kirigami.Theme.backgroundColor, 1.1)
                    border.width: 1
                    radius: 6

                    ColumnLayout {
                        id: groupContent
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        // Group header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.ToolButton {
                                icon.name: "go-up"
                                enabled: itemDelegate.index > 0
                                onClicked: {
                                    var items = root.layoutItems.slice();
                                    var tmp = items[itemDelegate.index];
                                    items[itemDelegate.index] = items[itemDelegate.index - 1];
                                    items[itemDelegate.index - 1] = tmp;
                                    root.layoutItems = items;
                                }
                            }
                            QQC2.ToolButton {
                                icon.name: "go-down"
                                enabled: itemDelegate.index < root.layoutItems.length - 1
                                onClicked: {
                                    var items = root.layoutItems.slice();
                                    var tmp = items[itemDelegate.index];
                                    items[itemDelegate.index] = items[itemDelegate.index + 1];
                                    items[itemDelegate.index + 1] = tmp;
                                    root.layoutItems = items;
                                }
                            }

                            // Group name / Ungrouped label
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                QQC2.TextField {
                                    Layout.fillWidth: true
                                    visible: !itemDelegate.isUngrouped
                                    text: itemDelegate.itemData.name || ""
                                    placeholderText: i18n("Group name")
                                    onEditingFinished: {
                                        var items = root.layoutItems.slice();
                                        items[itemDelegate.index] = Object.assign({}, items[itemDelegate.index], {name: text});
                                        root.layoutItems = items;
                                    }
                                }
                                RowLayout {
                                    visible: itemDelegate.isUngrouped
                                    spacing: Kirigami.Units.smallSpacing

                                    Kirigami.Icon {
                                        source: "view-list-icons"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    }
                                    ColumnLayout {
                                        spacing: 0
                                        QQC2.Label {
                                            text: i18n("Ungrouped")
                                            font.bold: true
                                        }
                                        QQC2.Label {
                                            text: i18n("Shows all apps not assigned to a named group")
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.6
                                        }
                                    }
                                }
                            }

                            // Color picker
                            Rectangle {
                                width: 28; height: 28
                                radius: 4
                                color: itemDelegate.itemData.color || "transparent"
                                border.color: Kirigami.Theme.textColor
                                border.width: 1

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        colorDialog.targetIndex = itemDelegate.index;
                                        colorDialog.selectedColor = itemDelegate.itemData.color || "#00000000";
                                        colorDialog.open();
                                    }
                                }
                            }

                            // Delete group
                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                QQC2.ToolTip.text: i18n("Delete group")
                                QQC2.ToolTip.visible: hovered
                                onClicked: {
                                    var items = root.layoutItems.slice();
                                    items.splice(itemDelegate.index, 1);
                                    root.layoutItems = items;
                                }
                            }
                        }

                        // App list (only for named groups, not ungrouped)
                        ColumnLayout {
                            visible: !itemDelegate.isUngrouped
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: (itemDelegate.itemData.appIds || []).length > 0

                                Repeater {
                                    model: itemDelegate.itemData.appIds || []

                                    Rectangle {
                                        required property int index
                                        required property string modelData

                                        width: chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                                        height: chipRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                                        radius: height / 2
                                        color: Kirigami.Theme.highlightColor

                                        RowLayout {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: Kirigami.Units.smallSpacing

                                            Kirigami.Icon {
                                                source: root.appIconName(modelData)
                                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                            }
                                            QQC2.Label {
                                                text: root.appDisplayName(modelData)
                                                color: Kirigami.Theme.highlightedTextColor
                                            }
                                            QQC2.ToolButton {
                                                icon.name: "edit-delete-remove"
                                                icon.width: Kirigami.Units.iconSizes.small
                                                icon.height: Kirigami.Units.iconSizes.small
                                                icon.color: Kirigami.Theme.highlightedTextColor
                                                implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                                                implicitHeight: implicitWidth
                                                onClicked: {
                                                    var li = itemDelegate.index;
                                                    var items = root.layoutItems.slice();
                                                    var ids = (items[li].appIds || []).slice();
                                                    ids.splice(index, 1);
                                                    items[li] = Object.assign({}, items[li], {appIds: ids});
                                                    root.layoutItems = items;
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            QQC2.Button {
                                text: i18n("Add Apps...")
                                icon.name: "list-add"
                                onClicked: {
                                    root.pickerTargetGroup = itemDelegate.index;
                                    appPickerPopup.open();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Add buttons ──
        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Add Group")
                icon.name: "list-add"
                onClicked: {
                    var items = root.layoutItems.slice();
                    items.push({type: "group", name: i18n("New Group"), appIds: [], color: ""});
                    root.layoutItems = items;
                }
            }

            QQC2.Button {
                text: i18n("Add Spacer")
                icon.name: "distribute-horizontal-x"
                onClicked: {
                    var items = root.layoutItems.slice();
                    items.push({type: "spacer", width: 8, color: ""});
                    root.layoutItems = items;
                }
            }

            QQC2.Button {
                visible: !root.hasUngrouped
                text: i18n("Add Ungrouped")
                icon.name: "view-list-icons"
                onClicked: {
                    var items = root.layoutItems.slice();
                    items.push({type: "group", name: "__ungrouped", appIds: [], color: ""});
                    root.layoutItems = items;
                }
            }
        }
    }

    // ── Color dialog ──
    ColorDialog {
        id: colorDialog
        property int targetIndex: -1
        title: i18n("Choose background color")
        options: ColorDialog.ShowAlphaChannel
        onAccepted: {
            if (targetIndex >= 0 && targetIndex < root.layoutItems.length) {
                var items = root.layoutItems.slice();
                items[targetIndex] = Object.assign({}, items[targetIndex], {color: selectedColor.toString()});
                root.layoutItems = items;
            }
        }
    }

    // ── App picker popup ──
    QQC2.Popup {
        id: appPickerPopup
        parent: QQC2.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 500)
        height: Math.min(parent.height * 0.8, 600)
        modal: true
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 3
                text: i18n("Add Apps to Group")
            }

            Kirigami.SearchField {
                id: pickerSearch
                Layout.fillWidth: true
                placeholderText: i18n("Search applications...")
                onTextChanged: root.searchQuery = text.toLowerCase()
            }

            QQC2.BusyIndicator {
                visible: !root.appsLoaded
                running: visible
                Layout.alignment: Qt.AlignHCenter
            }

            ListView {
                id: pickerList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: allAppsModel

                delegate: Item {
                    id: pickerDel
                    required property int index
                    required property string appId
                    required property string name
                    required property string icon
                    required property string genericName
                    required property string comment

                    readonly property bool alreadyInGroup: {
                        if (root.pickerTargetGroup < 0) return false;
                        var g = root.layoutItems[root.pickerTargetGroup];
                        if (!g || g.type !== "group") return false;
                        return (g.appIds || []).indexOf(appId) >= 0;
                    }

                    readonly property bool matchesSearch: {
                        if (root.searchQuery === "") return true;
                        var q = root.searchQuery;
                        return name.toLowerCase().indexOf(q) >= 0
                            || appId.toLowerCase().indexOf(q) >= 0
                            || genericName.toLowerCase().indexOf(q) >= 0
                            || comment.toLowerCase().indexOf(q) >= 0;
                    }

                    visible: matchesSearch
                    width: pickerList.width
                    implicitHeight: matchesSearch ? pickerButton.implicitHeight : 0
                    height: implicitHeight

                    QQC2.ItemDelegate {
                        id: pickerButton
                        anchors.fill: parent
                        highlighted: pickerDel.alreadyInGroup
                        onClicked: {
                            if (pickerDel.alreadyInGroup) return;
                            var gi = root.pickerTargetGroup;
                            if (gi < 0 || gi >= root.layoutItems.length) return;
                            var items = root.layoutItems.slice();
                            var ids = (items[gi].appIds || []).slice();
                            ids.push(pickerDel.appId);
                            items[gi] = Object.assign({}, items[gi], {appIds: ids});
                            root.layoutItems = items;
                        }

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: pickerDel.icon || "application-x-executable"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                QQC2.Label {
                                    text: pickerDel.name
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: pickerDel.alreadyInGroup
                                }
                                QQC2.Label {
                                    text: pickerDel.appId
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.55
                                }
                            }
                            Kirigami.Icon {
                                source: pickerDel.alreadyInGroup ? "dialog-ok-apply" : "list-add"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                opacity: pickerDel.alreadyInGroup ? 1.0 : 0.4
                            }
                        }
                    }
                }
            }

            QQC2.Button {
                text: i18n("Close")
                Layout.alignment: Qt.AlignRight
                onClicked: appPickerPopup.close()
            }
        }
    }
}
