/*
    SPDX-FileCopyrightText: 2024 Filtered Task Manager fork
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Qt.labs.settings as LabSettings

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: root

    property string cfg_filterAppIds

    // ── Derived state ──────────────────────────────────────────────
    readonly property var selectedIds: {
        var raw = cfg_filterAppIds;
        if (!raw || raw.trim() === "") return [];
        return raw.split(",").map(function(s) { return s.trim(); })
                              .filter(function(s) { return s !== ""; });
    }

    property string searchQuery: ""
    property bool appsLoaded: false

    // Master app database
    ListModel { id: allAppsModel }
    // Separate model for selected apps (rebuilt when selection or db changes)
    ListModel { id: selectedAppsModel }

    onSelectedIdsChanged: rebuildSelectedModel()

    // ── Home directory detection from our own package path ────────
    readonly property string homeDir: {
        var url = Qt.resolvedUrl(".").toString();
        var m = url.match(/^file:\/\/(\/[^\/]+\/[^\/]+)\//);
        return m ? m[1] : "";
    }

    // ── Directory scanners ───────────────────────────────────────
    // FolderListModels list the .desktop files; Instantiators reliably
    // expose each entry's fileName via required-property binding
    // (FolderListModel.get() is unreliable in some Qt 6 builds).

    FolderListModel {
        id: systemApps
        folder: "file:///usr/share/applications"
        nameFilters: ["*.desktop"]
        showDirs: false
    }
    Instantiator {
        id: systemInst
        model: systemApps
        delegate: QtObject { required property string fileName }
        onCountChanged: scanDebounce.restart()
    }

    FolderListModel {
        id: localApps
        folder: root.homeDir !== ""
            ? ("file://" + root.homeDir + "/.local/share/applications")
            : "file:///nonexistent"
        nameFilters: ["*.desktop"]
        showDirs: false
    }
    Instantiator {
        id: localInst
        model: localApps
        delegate: QtObject { required property string fileName }
        onCountChanged: scanDebounce.restart()
    }

    FolderListModel {
        id: flatpakApps
        folder: "file:///var/lib/flatpak/exports/share/applications"
        nameFilters: ["*.desktop"]
        showDirs: false
    }
    Instantiator {
        id: flatpakInst
        model: flatpakApps
        delegate: QtObject { required property string fileName }
        onCountChanged: scanDebounce.restart()
    }

    Timer {
        id: scanDebounce
        interval: 500
        onTriggered: root.scanAllApps()
    }

    // ── .desktop file reading via Qt.labs.settings (INI reader) ──
    // Qt.labs.settings.Settings has a writable QString fileName property
    // and value(key, default) method — confirmed from plugins.qmltypes.
    Component {
        id: desktopReaderComponent
        LabSettings.Settings {
            category: "Desktop Entry"
        }
    }

    function readDesktopEntry(filePath) {
        var reader;
        try {
            // fileName is QString — pass a plain local path, not a URL
            reader = desktopReaderComponent.createObject(root, { fileName: filePath });
        } catch (e) { return null; }
        if (!reader) return null;

        var type = String(reader.value("Type", ""));
        if (type !== "Application") { reader.destroy(); return null; }

        var noDisplay = String(reader.value("NoDisplay", "false"));
        var hidden = String(reader.value("Hidden", "false"));
        if (noDisplay === "true" || hidden === "true") { reader.destroy(); return null; }

        var result = {
            name:        String(reader.value("Name", "")),
            icon:        String(reader.value("Icon", "application-x-executable")),
            genericName: String(reader.value("GenericName", "")),
            comment:     String(reader.value("Comment", ""))
        };
        reader.destroy();
        return result;
    }

    function processInstantiator(inst, dirPath, map) {
        for (var i = 0; i < inst.count; i++) {
            var obj = inst.objectAt(i);
            if (!obj) continue;
            var fileName = obj.fileName;
            if (!fileName || !fileName.endsWith(".desktop")) continue;
            var appId = fileName.replace(/\.desktop$/, "");
            if (map.hasOwnProperty(appId)) continue;       // dedup (first wins)
            var filePath = dirPath + fileName;
            var info = readDesktopEntry(filePath);
            if (!info) continue;
            map[appId] = {
                appId:       appId,
                name:        info.name || appId,
                genericName: info.genericName || "",
                icon:        info.icon || "application-x-executable",
                comment:     info.comment || ""
            };
        }
    }

    function scanAllApps() {
        var map = {};
        if (root.homeDir !== "")
            processInstantiator(localInst, root.homeDir + "/.local/share/applications/", map);
        processInstantiator(flatpakInst, "/var/lib/flatpak/exports/share/applications/", map);
        processInstantiator(systemInst, "/usr/share/applications/", map);

        var list = [];
        for (var id in map) list.push(map[id]);
        list.sort(function(a, b) { return a.name.localeCompare(b.name); });

        allAppsModel.clear();
        for (var i = 0; i < list.length; i++) allAppsModel.append(list[i]);
        appsLoaded = true;
        rebuildSelectedModel();
    }

    // ── Selection helpers ────────────────────────────────────────
    function addApp(id) {
        var ids = selectedIds.slice();
        if (ids.indexOf(id) < 0) ids.push(id);
        cfg_filterAppIds = ids.join(",");
    }

    function removeApp(id) {
        cfg_filterAppIds = selectedIds.filter(function(x) { return x !== id; }).join(",");
    }

    function toggleApp(id) {
        if (selectedIds.indexOf(id) >= 0) removeApp(id);
        else addApp(id);
    }

    function appInfo(id) {
        for (var i = 0; i < allAppsModel.count; i++) {
            var item = allAppsModel.get(i);
            if (item.appId === id) return item;
        }
        return { appId: id, name: id, genericName: "", icon: "application-x-executable", comment: "" };
    }

    function rebuildSelectedModel() {
        selectedAppsModel.clear();
        var ids = selectedIds;
        for (var i = 0; i < ids.length; i++) {
            selectedAppsModel.append(appInfo(ids[i]));
        }
    }

    Component.onCompleted: scanDebounce.start()

    // ══════════════════════════════════════════════════════════════
    // ██  UI  █████████████████████████████████████████████████████
    // ══════════════════════════════════════════════════════════════

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.largeSpacing

        // ── Header row ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                level: 3
                text: selectedIds.length > 0
                    ? i18n("Showing %1 App(s)", selectedIds.length)
                    : i18n("No Filter Active")
            }

            Item { Layout.fillWidth: true }

            QQC2.Button {
                visible: selectedIds.length > 0
                text: i18n("Clear Filter")
                icon.name: "edit-clear-all"
                flat: true
                onClicked: cfg_filterAppIds = ""
            }
        }

        // ── Empty state ──────────────────────────────────────────
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: selectedIds.length === 0
            type: Kirigami.MessageType.Information
            text: i18n("All applications are currently shown. Add apps below to filter this task manager instance to specific applications only. Each widget instance has its own independent filter.")
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── Selected apps (chips) ────────────────────────────────
        Flow {
            id: chipFlow
            visible: selectedAppsModel.count > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: selectedAppsModel

                // ─ Chip delegate ─
                Rectangle {
                    id: chip
                    required property int index
                    required property string appId
                    required property string name
                    required property string icon

                    width: chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                    height: chipRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: height / 2
                    color: chipArea.hovered
                        ? Qt.darker(Kirigami.Theme.highlightColor, 1.15)
                        : Kirigami.Theme.highlightColor

                    Behavior on color {
                        ColorAnimation { duration: Kirigami.Units.shortDuration }
                    }

                    HoverHandler { id: chipArea }

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: chip.icon || "application-x-executable"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        QQC2.Label {
                            text: chip.name
                            color: Kirigami.Theme.highlightedTextColor
                        }

                        QQC2.ToolButton {
                            icon.name: "edit-delete-remove"
                            icon.width: Kirigami.Units.iconSizes.small
                            icon.height: Kirigami.Units.iconSizes.small
                            implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                            implicitHeight: implicitWidth
                            onClicked: root.removeApp(chip.appId)
                            QQC2.ToolTip.text: i18n("Remove %1 from filter", chip.name)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── "Add Apps" section ───────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                level: 3
                text: {
                    if (!appsLoaded) return i18n("Loading Applications\u2026");
                    if (searchQuery !== "")
                        return i18n("Search Results");
                    return i18n("All Applications (%1)", allAppsModel.count);
                }
            }

            Item { Layout.fillWidth: true }

            QQC2.Label {
                visible: searchQuery !== "" && appsLoaded
                text: {
                    var n = 0;
                    for (var i = 0; i < allAppsModel.count; i++) {
                        var item = allAppsModel.get(i);
                        var q = searchQuery;
                        if (item.name.toLowerCase().indexOf(q) >= 0
                            || item.appId.toLowerCase().indexOf(q) >= 0
                            || item.genericName.toLowerCase().indexOf(q) >= 0
                            || item.comment.toLowerCase().indexOf(q) >= 0)
                            n++;
                    }
                    return i18n("%1 match(es)", n);
                }
                opacity: 0.6
            }
        }

        Kirigami.SearchField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: i18n("Search by name, ID, or description\u2026")
            onTextChanged: root.searchQuery = text.toLowerCase()
        }

        // Loading spinner
        QQC2.BusyIndicator {
            visible: !appsLoaded
            running: visible
            Layout.alignment: Qt.AlignHCenter
        }

        // ── Application list ─────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(
                Kirigami.Units.gridUnit * 22,
                appList.contentHeight + 2
            )
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            color: Kirigami.Theme.backgroundColor
            border.color: Qt.darker(Kirigami.Theme.backgroundColor, 1.15)
            border.width: 1
            radius: 4

            ListView {
                id: appList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: allAppsModel
                reuseItems: true

                // Smooth scrolling
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                    active: true
                }

                delegate: Item {
                    id: del

                    required property int index
                    required property string appId
                    required property string name
                    required property string genericName
                    required property string icon
                    required property string comment

                    // Live selection tracking (re-evaluates when cfg changes)
                    readonly property bool isInFilter: {
                        void root.cfg_filterAppIds;   // dependency
                        return root.selectedIds.indexOf(appId) >= 0;
                    }

                    // Search filter
                    readonly property bool matchesSearch: {
                        if (root.searchQuery === "") return true;
                        var q = root.searchQuery;
                        return name.toLowerCase().indexOf(q) >= 0
                            || appId.toLowerCase().indexOf(q) >= 0
                            || genericName.toLowerCase().indexOf(q) >= 0
                            || comment.toLowerCase().indexOf(q) >= 0;
                    }

                    visible: matchesSearch
                    width: appList.width
                    implicitHeight: matchesSearch ? delegateButton.implicitHeight : 0
                    height: implicitHeight

                    QQC2.ItemDelegate {
                        id: delegateButton
                        anchors.fill: parent
                        highlighted: del.isInFilter
                        onClicked: root.toggleApp(del.appId)

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.Icon {
                                source: del.icon || "application-x-executable"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                QQC2.Label {
                                    text: del.name
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: del.isInFilter
                                }

                                QQC2.Label {
                                    visible: text !== ""
                                    text: {
                                        var parts = [];
                                        if (del.genericName) parts.push(del.genericName);
                                        parts.push(del.appId);
                                        return parts.join(" \u2014 ");
                                    }
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.55
                                }
                            }

                            Kirigami.Icon {
                                source: del.isInFilter ? "dialog-ok-apply" : "list-add"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                opacity: del.isInFilter ? 1.0 : 0.4
                            }
                        }
                    }
                }
            }

            // "No results" overlay
            QQC2.Label {
                anchors.centerIn: parent
                visible: appsLoaded && appList.count > 0 && !hasVisibleItems()
                text: i18n("No applications match \"%1\"", searchField.text)
                opacity: 0.5

                function hasVisibleItems() {
                    if (root.searchQuery === "") return true;
                    for (var i = 0; i < allAppsModel.count; i++) {
                        var item = allAppsModel.get(i);
                        var q = root.searchQuery;
                        if (item.name.toLowerCase().indexOf(q) >= 0
                            || item.appId.toLowerCase().indexOf(q) >= 0
                            || item.genericName.toLowerCase().indexOf(q) >= 0
                            || item.comment.toLowerCase().indexOf(q) >= 0)
                            return true;
                    }
                    return false;
                }
            }
        }

        // ── Manual entry fallback ────────────────────────────────
        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label {
            text: i18n("Can't find an app? Enter its .desktop ID manually:")
            opacity: 0.6
        }

        RowLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: manualField
                Layout.fillWidth: true
                placeholderText: i18n("e.g. com.example.myapp")
                onAccepted: addManual()
            }

            QQC2.Button {
                text: i18n("Add")
                icon.name: "list-add"
                enabled: manualField.text.trim() !== ""
                onClicked: addManual()
            }

            function addManual() {
                var ids = manualField.text.split(",");
                for (var i = 0; i < ids.length; i++) {
                    var id = ids[i].trim();
                    if (id !== "") root.addApp(id);
                }
                manualField.text = "";
            }
        }
    }
}
