/*
    SPDX-FileCopyrightText: 2024 Filtered Task Manager fork
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQml.Models
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
    property bool collapsed: false
    property int focusIndex: -1
    property var deletedItem: null
    property int deletedIndex: -1
    property string draggedAppId: ""
    property int dragSourceGroup: -1

    // ── Layout model for DelegateModel ──
    ListModel { id: layoutModel }

    function rebuildLayoutModel() {
        layoutModel.clear();
        for (var i = 0; i < layoutItems.length; i++) {
            layoutModel.append({origIndex: i});
        }
    }

    function commitVisualOrder() {
        var newItems = [];
        for (var i = 0; i < visualModel.items.count; i++) {
            var origIdx = visualModel.items.get(i).model.origIndex;
            newItems.push(layoutItems[origIdx]);
        }
        layoutItems = newItems;
    }

    onLayoutItemsChanged: {
        if (_loading) return;
        cfg_taskGroups = JSON.stringify(layoutItems);
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
        rebuildLayoutModel();
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
        rebuildLayoutModel();
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
        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 3
                text: i18n("Panel Layout")
                Layout.fillWidth: true
            }

            QQC2.ToolButton {
                icon.name: root.collapsed ? "view-list-details" : "view-list-tree"
                text: root.collapsed ? i18n("Expand") : i18n("Compact")
                display: QQC2.AbstractButton.TextBesideIcon
                checked: root.collapsed
                onClicked: root.collapsed = !root.collapsed
            }
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Arrange groups and spacers in the order they appear on the panel.")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
            QQC2.Label {
                text: i18n("↑/↓ to navigate, Alt+↑/↓ to reorder")
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
        }

        // ── Layout item list (ListView + DelegateModel) ──
        DelegateModel {
            id: visualModel
            model: layoutModel

            delegate: Item {
                id: delegateRoot
                required property int origIndex

                readonly property var itemData: root.layoutItems[origIndex] || {}
                readonly property bool isGroup: (itemData.type || "group") === "group"
                readonly property bool isSpacer: itemData.type === "spacer"
                readonly property bool isUngrouped: isGroup && itemData.name === "__ungrouped"

                property bool dragActive: card.handleArea.drag.active

                width: layoutListView.width
                height: content.implicitHeight + Kirigami.Units.smallSpacing

                z: dragActive ? 1000 : (root.dragSourceGroup === origIndex ? 999 : 0)

                // Keyboard reorder
                Timer {
                    interval: 1
                    running: delegateRoot.origIndex === root.focusIndex
                    onTriggered: delegateRoot.forceActiveFocus()
                }
                Keys.onPressed: event => {
                    if (event.modifiers & Qt.AltModifier) {
                        if (event.key === Qt.Key_Up && origIndex > 0) {
                            root.focusIndex = origIndex - 1;
                            card.moveUp();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && origIndex < root.layoutItems.length - 1) {
                            root.focusIndex = origIndex + 1;
                            card.moveDown();
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Down && origIndex < root.layoutItems.length - 1) {
                        var next = layoutListView.itemAtIndex(origIndex + 1);
                        if (next) { next.forceActiveFocus(); root.focusIndex = origIndex + 1; }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up && origIndex > 0) {
                        var prev = layoutListView.itemAtIndex(origIndex - 1);
                        if (prev) { prev.forceActiveFocus(); root.focusIndex = origIndex - 1; }
                        event.accepted = true;
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: mouse => {
                        delegateRoot.forceActiveFocus();
                        root.focusIndex = delegateRoot.origIndex;
                        mouse.accepted = false;
                    }
                }

                Item {
                    id: content
                    width: delegateRoot.width
                    implicitHeight: card.implicitHeight
                    height: implicitHeight

                    opacity: delegateRoot.dragActive ? 0.85 : 1.0

                    Drag.active: delegateRoot.dragActive
                    Drag.source: delegateRoot
                    Drag.keys: ["card"]
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: Kirigami.Units.gridUnit

                    StandardCard {
                        id: card
                        width: parent.width
                        name: delegateRoot.isUngrouped ? i18n("Ungrouped") : (delegateRoot.itemData.name || "")
                        nameEditable: !delegateRoot.isSpacer && !delegateRoot.isUngrouped
                        icon: delegateRoot.isUngrouped ? "application-x-executable" : (delegateRoot.isSpacer ? "distribute-horizontal-x" : (delegateRoot.itemData.icon || "view-list-icons"))
                        itemColor: delegateRoot.itemData.color || ""
                        collapsed: root.collapsed
                        collapsable: !delegateRoot.isSpacer && !delegateRoot.isUngrouped
                        extraContentVisible: !root.collapsed && delegateRoot.isGroup && !delegateRoot.isUngrouped
                        dragTarget: content
                        upEnabled: delegateRoot.origIndex > 0
                        downEnabled: delegateRoot.origIndex < root.layoutItems.length - 1
                        outlineColor: delegateRoot.activeFocus ? Kirigami.Theme.highlightColor : (delegateRoot.isSpacer ? Qt.darker(Kirigami.Theme.backgroundColor, 1.3) : Kirigami.Theme.disabledTextColor)

                        collapsedInfo: {
                            var ids = delegateRoot.itemData.appIds || [];
                            if (ids.length === 0) return "";
                            var names = [];
                            for (var i = 0; i < ids.length; i++) names.push(root.appDisplayName(ids[i]));
                            return "(" + ids.length + " apps: " + names.join(", ") + ")";
                        }

                        onNameEdited: function(newName) {
                            var items = root.layoutItems.slice();
                            items[delegateRoot.origIndex] = Object.assign({}, items[delegateRoot.origIndex], {name: newName});
                            root.layoutItems = items;
                        }
                        onDeleteClicked: {
                            root.deletedItem = Object.assign({}, delegateRoot.itemData);
                            root.deletedIndex = delegateRoot.origIndex;
                            var items = root.layoutItems.slice();
                            items.splice(delegateRoot.origIndex, 1);
                            root.layoutItems = items;
                            undoTimer.restart();
                        }
                        onColorClicked: {
                            colorDialog.targetIndex = delegateRoot.origIndex;
                            colorDialog.selectedColor = delegateRoot.itemData.color || "#00000000";
                            colorDialog.open();
                        }
                        onMoveUp: {
                            var items = root.layoutItems.slice();
                            var idx = delegateRoot.origIndex;
                            var tmp = items[idx]; items[idx] = items[idx - 1]; items[idx - 1] = tmp;
                            root.layoutItems = items;
                        }
                        onMoveDown: {
                            var items = root.layoutItems.slice();
                            var idx = delegateRoot.origIndex;
                            var tmp = items[idx]; items[idx] = items[idx + 1]; items[idx + 1] = tmp;
                            root.layoutItems = items;
                        }

                        handleArea.onReleased: { content.y = 0; root.commitVisualOrder(); }
                        handleArea.onCanceled: { content.y = 0; }

                        rightControls: [
                            QQC2.Label {
                                visible: delegateRoot.isSpacer
                                text: i18n("Width:")
                                opacity: 0.6
                            },
                            QQC2.SpinBox {
                                visible: delegateRoot.isSpacer
                                from: 1; to: 128
                                value: delegateRoot.itemData.width || 8
                                onValueModified: {
                                    var items = root.layoutItems.slice();
                                    items[delegateRoot.origIndex] = Object.assign({}, items[delegateRoot.origIndex], {width: value});
                                    root.layoutItems = items;
                                }
                            },
                            QQC2.Label {
                                visible: delegateRoot.isSpacer
                                text: i18n("px")
                                opacity: 0.5
                            }
                        ]

                        // App list
                        RowLayout {
                            visible: (delegateRoot.itemData.appIds || []).length > 0
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Button {
                                text: i18n("Add Apps...")
                                icon.name: "list-add"
                                Layout.alignment: Qt.AlignTop
                                onClicked: {
                                    root.pickerTargetGroup = delegateRoot.origIndex;
                                    appPickerPopup.open();
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: delegateRoot.itemData.appIds || []

                                    Rectangle {
                                        id: chipRect
                                        required property int index
                                        required property string modelData
                                        width: chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                                        height: chipRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                                        radius: height / 2
                                        color: Kirigami.Theme.highlightColor
                                        opacity: chipDragArea.drag.active ? 0.7 : 1.0

                                        Drag.active: chipDragArea.drag.active
                                        Drag.keys: ["appChip"]
                                        Drag.hotSpot.x: width / 2
                                        Drag.hotSpot.y: height / 2

                                        property real _origX: 0
                                        property real _origY: 0

                                        MouseArea {
                                            id: chipDragArea
                                            anchors.fill: parent
                                            drag.target: chipRect
                                            drag.axis: Drag.XAndYAxis
                                            cursorShape: Qt.SizeAllCursor
                                            preventStealing: true
                                            onPressed: {
                                                chipRect._origX = chipRect.x;
                                                chipRect._origY = chipRect.y;
                                                root.draggedAppId = chipRect.modelData;
                                                root.dragSourceGroup = delegateRoot.origIndex;
                                            }
                                            onReleased: {
                                                chipRect.Drag.drop();
                                                chipRect.x = chipRect._origX;
                                                chipRect.y = chipRect._origY;
                                                root.draggedAppId = "";
                                                root.dragSourceGroup = -1;
                                            }
                                        }

                                        RowLayout {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: Kirigami.Units.smallSpacing
                                            Kirigami.Icon {
                                                source: "handle-sort"
                                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                                opacity: 0.5
                                            }
                                            Kirigami.Icon {
                                                source: root.appIconName(chipRect.modelData)
                                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                            }
                                            QQC2.Label {
                                                text: root.appDisplayName(chipRect.modelData)
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
                                                    var li = delegateRoot.origIndex;
                                                    var items = root.layoutItems.slice();
                                                    var ids = (items[li].appIds || []).slice();
                                                    ids.splice(chipRect.index, 1);
                                                    items[li] = Object.assign({}, items[li], {appIds: ids});
                                                    root.layoutItems = items;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Add Apps button (shown when no apps yet)
                        QQC2.Button {
                            visible: (delegateRoot.itemData.appIds || []).length === 0
                            text: i18n("Add Apps...")
                            icon.name: "list-add"
                            onClicked: {
                                root.pickerTargetGroup = delegateRoot.origIndex;
                                appPickerPopup.open();
                            }
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["card"]
                    onEntered: drag => {
                        var from = drag.source.DelegateModel.itemsIndex;
                        var to = delegateRoot.DelegateModel.itemsIndex;
                        if (from !== to)
                            visualModel.items.move(from, to);
                    }
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["appChip"]
                    enabled: delegateRoot.isGroup && !delegateRoot.isUngrouped
                    onEntered: card.outlineColor = Kirigami.Theme.highlightColor
                    onExited: card.outlineColor = Qt.binding(function() {
                        return delegateRoot.activeFocus ? Kirigami.Theme.highlightColor : (delegateRoot.isSpacer ? Qt.darker(Kirigami.Theme.backgroundColor, 1.3) : Kirigami.Theme.disabledTextColor);
                    })
                    onDropped: drop => {
                        card.outlineColor = Qt.binding(function() {
                            return delegateRoot.activeFocus ? Kirigami.Theme.highlightColor : (delegateRoot.isSpacer ? Qt.darker(Kirigami.Theme.backgroundColor, 1.3) : Kirigami.Theme.disabledTextColor);
                        });
                        var appId = root.draggedAppId;
                        var srcIdx = root.dragSourceGroup;
                        var dstIdx = delegateRoot.origIndex;
                        if (!appId || srcIdx < 0 || srcIdx === dstIdx) return;
                        var items = root.layoutItems.slice();
                        // Remove from source
                        var srcIds = (items[srcIdx].appIds || []).slice();
                        var ai = srcIds.indexOf(appId);
                        if (ai >= 0) srcIds.splice(ai, 1);
                        items[srcIdx] = Object.assign({}, items[srcIdx], {appIds: srcIds});
                        // Add to target
                        var dstIds = (items[dstIdx].appIds || []).slice();
                        if (dstIds.indexOf(appId) < 0) dstIds.push(appId);
                        items[dstIdx] = Object.assign({}, items[dstIdx], {appIds: dstIds});
                        root.layoutItems = items;
                    }
                }
            }
        }

        ListView {
            id: layoutListView
            Layout.fillWidth: true
            implicitHeight: contentHeight
            interactive: false
            model: visualModel
            clip: false

            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    easing.type: Easing.OutQuad
                    duration: 200
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
                    items.push({type: "group", name: i18n("New Group"), icon: "view-list-icons", appIds: [], color: ""});
                    root.layoutItems = items;
                }
            }

            QQC2.Button {
                text: i18n("Add Spacer")
                icon.name: "distribute-horizontal-x"
                onClicked: {
                    var items = root.layoutItems.slice();
                    items.push({type: "spacer", name: "Spacer", width: 8, color: ""});
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

    // ── Undo delete toast ──
    Timer {
        id: undoTimer
        interval: 5000
        onTriggered: { root.deletedItem = null; root.deletedIndex = -1; }
    }

    Rectangle {
        id: undoToast
        visible: root.deletedItem !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.largeSpacing
        width: undoRow.implicitWidth + Kirigami.Units.largeSpacing * 2
        height: undoRow.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: 4
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1

        RowLayout {
            id: undoRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Deleted")
                opacity: 0.7
            }
            QQC2.ToolButton {
                text: i18n("Undo")
                icon.name: "edit-undo"
                onClicked: {
                    if (root.deletedItem && root.deletedIndex >= 0) {
                        var items = root.layoutItems.slice();
                        var idx = Math.min(root.deletedIndex, items.length);
                        items.splice(idx, 0, root.deletedItem);
                        root.layoutItems = items;
                    }
                    root.deletedItem = null;
                    root.deletedIndex = -1;
                    undoTimer.stop();
                }
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
