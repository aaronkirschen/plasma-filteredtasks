/*
    SPDX-FileCopyrightText: 2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager

KCMUtils.SimpleKCM {
    property alias cfg_groupingStrategy: groupingStrategy.currentIndex
    property int cfg_groupingStrategyDefault
    property alias cfg_groupedTaskVisualization: groupedTaskVisualization.currentIndex
    property int cfg_groupedTaskVisualizationDefault
    property alias cfg_groupPopups: groupPopups.checked
    property bool cfg_groupPopupsDefault
    property alias cfg_onlyGroupWhenFull: onlyGroupWhenFull.checked
    property bool cfg_onlyGroupWhenFullDefault
    property var cfg_groupingAppIdBlacklist
    property var cfg_groupingAppIdBlacklistDefault
    property var cfg_groupingLauncherUrlBlacklist
    property var cfg_groupingLauncherUrlBlacklistDefault
    property int cfg_sortingStrategy
    property int cfg_sortingStrategyDefault
    property alias cfg_separateLaunchers: separateLaunchers.checked
    property bool cfg_separateLaunchersDefault
    property alias cfg_hideLauncherOnStart: hideLauncherOnStart.checked
    property bool cfg_hideLauncherOnStartDefault
    property alias cfg_middleClickAction: middleClickAction.currentIndex
    property int cfg_middleClickActionDefault
    property alias cfg_wheelEnabled: wheelEnabled.currentIndex
    property int cfg_wheelEnabledDefault
    property alias cfg_wheelSkipMinimized: wheelSkipMinimized.checked
    property bool cfg_wheelSkipMinimizedDefault
    property alias cfg_showOnlyCurrentScreen: showOnlyCurrentScreen.checked
    property bool cfg_showOnlyCurrentScreenDefault
    property alias cfg_showOnlyCurrentDesktop: showOnlyCurrentDesktop.checked
    property bool cfg_showOnlyCurrentDesktopDefault
    property alias cfg_showOnlyCurrentActivity: showOnlyCurrentActivity.checked
    property bool cfg_showOnlyCurrentActivityDefault
    property alias cfg_showOnlyMinimized: showOnlyMinimized.checked
    property bool cfg_showOnlyMinimizedDefault
    property alias cfg_minimizeActiveTaskOnClick: minimizeActive.checked
    property bool cfg_minimizeActiveTaskOnClickDefault
    property alias cfg_unhideOnAttention: unhideOnAttention.checked
    property bool cfg_unhideOnAttentionDefault
    property alias cfg_reverseMode: reverseMode.checked
    property bool cfg_reverseModeDefault
    // Stubs for keys managed by other pages
    property bool cfg_showToolTips
    property bool cfg_showToolTipsDefault
    property bool cfg_highlightWindows
    property bool cfg_highlightWindowsDefault
    property bool cfg_indicateAudioStreams
    property bool cfg_indicateAudioStreamsDefault
    property bool cfg_interactiveMute
    property bool cfg_interactiveMuteDefault
    property bool cfg_tooltipControls
    property bool cfg_tooltipControlsDefault
    property bool cfg_fill
    property bool cfg_fillDefault
    property int cfg_maxStripes
    property int cfg_maxStripesDefault
    property bool cfg_forceStripes
    property bool cfg_forceStripesDefault
    property int cfg_taskMaxWidth
    property int cfg_taskMaxWidthDefault
    property int cfg_iconSpacing
    property int cfg_iconSpacingDefault
    property var cfg_launchers
    property var cfg_launchersDefault
    property bool cfg_taskHoverEffect
    property bool cfg_taskHoverEffectDefault
    property int cfg_maxTextLines
    property int cfg_maxTextLinesDefault
    property string cfg_taskGroups
    property string cfg_taskGroupsDefault
    property bool cfg_exclusiveMode
    property bool cfg_exclusiveModeDefault
    property string cfg_syncGroup
    property string cfg_syncGroupDefault

    headerPaddingEnabled: false
    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            id: annoyingAppWorkaroundMessage

            Layout.fillWidth: true
            position: Kirigami.InlineMessage.Position.Header

            text: i18nc("@info", "If you're using this setting to work around an application that demands attention too often, first look for a setting in the app to disable that behavior. If you don't find one, consider reporting this as a bug to the app's developer.")
        }
    }

    DBus.DBusServiceWatcher {
        id: effectWatcher
        busType: DBus.BusType.Session
        watchedService: "org.kde.KWin.Effect.WindowView1"
    }

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.ComboBox {
            id: groupingStrategy
            Kirigami.FormData.label: i18nc("@label:listbox how to group tasks", "Group:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            model: [
                i18nc("@item:inlistbox how to group tasks", "Do not group"),
                i18nc("@item:inlistbox how to group tasks", "By program name")
            ]
        }

        QQC2.ComboBox {
            id: groupedTaskVisualization
            Kirigami.FormData.label: i18nc("@label:listbox completes sentence like: … cycles through tasks", "Clicking grouped task:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14

            enabled: groupingStrategy.currentIndex !== 0

            model: [
                i18nc("@item:inlistbox Completes the sentence 'Clicking grouped task cycles through tasks' ", "Cycles through tasks"),
                i18nc("@item:inlistbox Completes the sentence 'Clicking grouped task shows small window previews' ", "Shows small window previews"),
                i18nc("@item:inlistbox Completes the sentence 'Clicking grouped task shows large window previews' ", "Shows large window previews"),
                i18nc("@item:inlistbox Completes the sentence 'Clicking grouped task shows textual list' ", "Shows textual list"),
            ]

            Accessible.name: currentText
            Accessible.onPressAction: currentIndex = currentIndex === count - 1 ? 0 : (currentIndex + 1)
        }
        // "You asked for Window View but Window View is not available" message
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: groupedTaskVisualization.currentIndex === 2 && !effectWatcher.registered
            type: Kirigami.MessageType.Warning
            text: i18nc("@info displayed as InlineMessage", "The compositor does not support displaying windows side by side, so a textual list will be displayed instead.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: groupPopups
            visible: (Plasmoid.pluginName !== "org.kde.plasma.icontasks" && Plasmoid.pluginName !== "org.kde.plasma.filteredtasks")
            text: i18nc("@option:check grouped task", "Combine into single button")
            enabled: groupingStrategy.currentIndex > 0
        }

        QQC2.CheckBox {
            id: onlyGroupWhenFull
            visible: (Plasmoid.pluginName !== "org.kde.plasma.icontasks" && Plasmoid.pluginName !== "org.kde.plasma.filteredtasks")
            text: i18nc("@option:check grouped task","Group only when the Task Manager is full")
            enabled: groupingStrategy.currentIndex > 0 && groupPopups.checked
            Accessible.onPressAction: toggle()
        }

        Item {
            Kirigami.FormData.isSection: true
            visible: (Plasmoid.pluginName !== "org.kde.plasma.icontasks" && Plasmoid.pluginName !== "org.kde.plasma.filteredtasks")
        }

        QQC2.ComboBox {
            id: sortingStrategy
            Kirigami.FormData.label: i18nc("@label:listbox sort tasks in grouped task", "Sort:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    "text": i18nc("@item:inlistbox sort tasks in grouped task", "Do not sort"),
                    "value": TaskManager.TasksModel.SortDisabled,
                },
                {
                    "text": i18nc("@item:inlistbox sort tasks in grouped task", "Manually"),
                    "value": TaskManager.TasksModel.SortManual,
                },
                {
                    "text": i18nc("@item:inlistbox sort tasks in grouped task", "Alphabetically"),
                    "value": TaskManager.TasksModel.SortAlpha,
                },
                {
                    "text": i18nc("@item:inlistbox sort tasks in grouped task", "By desktop"),
                    "value": TaskManager.TasksModel.SortVirtualDesktop,
                },
                {
                    "text": i18nc("@item:inlistbox sort tasks in grouped task", "By activity"),
                    "value": TaskManager.TasksModel.SortActivity,
                },
                {
                    "text": i18nc("@item:inlistbox sort tasks in grouped task", "By horizontal window position"),
                    "value": TaskManager.TasksModel.SortWindowPositionHorizontal,
                },
            ]
            onActivated: cfg_sortingStrategy = currentValue
            Component.onCompleted: currentIndex = indexOfValue(cfg_sortingStrategy)
        }

        QQC2.CheckBox {
            id: separateLaunchers
            visible: (Plasmoid.pluginName !== "org.kde.plasma.icontasks" && Plasmoid.pluginName !== "org.kde.plasma.filteredtasks")
            text: i18nc("@option:check configure task sorting", "Keep launchers separate")
            enabled: sortingStrategy.currentValue === TaskManager.TasksModel.SortManual
        }

        QQC2.CheckBox {
            id: hideLauncherOnStart
            visible: (Plasmoid.pluginName !== "org.kde.plasma.icontasks" && Plasmoid.pluginName !== "org.kde.plasma.filteredtasks")
            text: i18nc("@option:check for icons-and-text task manager", "Hide launchers after application startup")
        }

        Item {
            Kirigami.FormData.isSection: true
            visible: (Plasmoid.pluginName !== "org.kde.plasma.icontasks" && Plasmoid.pluginName !== "org.kde.plasma.filteredtasks")
        }

        QQC2.CheckBox {
            id: minimizeActive
            Kirigami.FormData.label: i18nc("@label for checkbox Part of a sentence: 'Clicking active task minimizes the task'", "Clicking active task:")
            text: i18nc("@option:check Part of a sentence: 'Clicking active task minimizes the task'", "Minimizes the task")
        }

        QQC2.ComboBox {
            id: middleClickAction
            Kirigami.FormData.label: i18nc("@label:listbox completes sentence like: … does nothing", "Middle-clicking any task:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            model: [
                i18nc("@item:inlistbox Part of a sentence: 'Middle-clicking any task does nothing'", "Does nothing"),
                i18nc("@item:inlistbox Part of a sentence: 'Middle-clicking any task closes window or group'", "Closes window or group"),
                i18nc("@item:inlistbox Part of a sentence: 'Middle-clicking any task opens a new window'", "Opens a new window"),
                i18nc("@item:inlistbox Part of a sentence: 'Middle-clicking any task minimizes/restores window or group'", "Minimizes/Restores window or group"),
                i18nc("@item:inlistbox Part of a sentence: 'Middle-clicking any task toggles grouping'", "Toggles grouping"),
                i18nc("@item:inlistbox Part of a sentence: 'Middle-clicking any task brings it to the current virtual desktop'", "Brings it to the current virtual desktop")
            ]
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: wheelEnabled
            Kirigami.FormData.label: i18nc("@label:listbox Part of a sentence: 'Scrolling behavior does nothing/cycles through tasks/cycles through the selected task's windows'", "Scrolling behavior:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            model: [
                i18nc("@item:inlistbox Part of a sentence: 'Scrolling behavior does nothing'", "Does nothing"),
                i18nc("@item:inlistbox Part of a sentence: 'Scrolling behavior cycles through all tasks'", "Cycles through all tasks"),
                i18nc("@item:inlistbox Part of a sentence: 'Scrolling behavior cycles through the hovered task's windows'", "Cycles through the hovered task’s windows"),
            ]
        }

        QQC2.CheckBox {
            id: wheelSkipMinimized
            leftPadding: mirrored ? 0 : (wheelEnabled.indicator.width + wheelEnabled.spacing)
            rightPadding: mirrored ? (wheelEnabled.indicator.width + wheelEnabled.spacing) : 0
            text: i18nc("@option:check mouse wheel task cycling", "Skip minimized tasks")
            enabled: wheelEnabled.currentIndex !== 0 // None
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showOnlyCurrentDesktop
            Kirigami.FormData.label: i18nc("@label for checkbox group, completes sentence like: … from current screen", "Show only tasks:")
            text: i18nc("@option:check completes sentence: show only tasks", "From the current desktop")
        }

        QQC2.CheckBox {
            id: showOnlyCurrentActivity
            text: i18nc("@option:check completes sentence: show only tasks", "From the current activity")
        }

        QQC2.CheckBox {
            id: showOnlyCurrentScreen
            text: i18nc("@option:check completes sentence: show only tasks", "From the current screen")
        }

        QQC2.CheckBox {
            id: showOnlyMinimized
            text: i18nc("@option:check completes sentence: show only tasks", "That are minimized")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: unhideOnAttention
            Kirigami.FormData.label: i18nc("@label for checkbox, completes sentence: … unhide if window wants attention", "When panel is hidden:")
            text: i18nc("@option:check completes sentence: When panel is hidden", "Unhide when a window wants attention")
            onToggled: {
                annoyingAppWorkaroundMessage.visible = !unhideOnAttention.checked;
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ButtonGroup {
            id: reverseModeRadioButtonGroup
        }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18nc("@label for radiobutton group completes sentence like: … on the bottom", "New tasks appear:")
            checked: !reverseMode.checked
            text: {
                if (Plasmoid.formFactor === PlasmaCore.Types.Vertical) {
                    return i18nc("@option:check completes sentence: New tasks appear", "On the bottom")
                }
                // horizontal
                if (Qt.application.layoutDirection === Qt.LeftToRight) {
                    return i18nc("@option:check completes sentence: New tasks appear", "To the right");
                } else {
                    return i18nc("@option:check completes sentence: New tasks appear", "To the left")
                }
            }
            QQC2.ButtonGroup.group: reverseModeRadioButtonGroup
        }

        QQC2.RadioButton {
            id: reverseMode
            checked: Plasmoid.configuration.reverseMode === true
            text: {
                if (Plasmoid.formFactor === PlasmaCore.Types.Vertical) {
                    return i18nc("@option:check completes sentence: New tasks appear", "On the top")
                }
                // horizontal
                if (Qt.application.layoutDirection === Qt.LeftToRight) {
                    return i18nc("@option:check completes sentence: New tasks appear", "To the left");
                } else {
                    return i18nc("@option:check completes sentence: New tasks appear", "To the right");
                }
            }
            QQC2.ButtonGroup.group: reverseModeRadioButtonGroup
        }
    }
}
