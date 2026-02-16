/*
    SPDX-FileCopyrightText: 2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
         name: i18n("Appearance")
         icon: "preferences-desktop-color"
         source: "ConfigAppearance.qml"
    }
    ConfigCategory {
         name: i18n("Behavior")
         icon: "preferences-desktop"
         source: "ConfigBehavior.qml"
    }
    ConfigCategory {
         name: i18n("Groups")
         icon: "view-filter"
         source: "ConfigGroups.qml"
    }
}
