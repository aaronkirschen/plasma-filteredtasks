/*
    SPDX-FileCopyrightText: 2024 Filtered Task Manager contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    property string cfg_filterAppIds

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.TextField {
            id: filterField
            Kirigami.FormData.label: i18n("Application IDs:")
            Layout.fillWidth: true
            text: cfg_filterAppIds
            placeholderText: i18n("e.g. firefox,org.kde.dolphin,steam")
            onTextChanged: cfg_filterAppIds = text
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            type: Kirigami.MessageType.Information
            text: i18n("Enter a comma-separated list of application IDs to show in this widget. Leave empty to show all tasks. Application IDs are typically the .desktop file name without the .desktop extension (e.g. \"firefox\", \"org.kde.dolphin\").")
        }
    }
}
