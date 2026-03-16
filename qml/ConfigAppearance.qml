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

KCMUtils.SimpleKCM {
    readonly property bool plasmaPaAvailable: Qt.createComponent("PulseAudio.qml").status === Component.Ready
    readonly property bool plasmoidVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    property alias cfg_showToolTips: showToolTips.checked
    property bool cfg_showToolTipsDefault
    property alias cfg_highlightWindows: highlightWindows.checked
    property bool cfg_highlightWindowsDefault
    property bool cfg_indicateAudioStreams
    property bool cfg_indicateAudioStreamsDefault
    property bool cfg_interactiveMute
    property bool cfg_interactiveMuteDefault
    property bool cfg_tooltipControls
    property bool cfg_tooltipControlsDefault
    property bool cfg_fill
    property bool cfg_fillDefault
    property alias cfg_maxStripes: maxStripes.value
    property int cfg_maxStripesDefault
    property alias cfg_forceStripes: forceStripes.checked
    property bool cfg_forceStripesDefault
    property int cfg_taskMaxWidth
    property int cfg_taskMaxWidthDefault
    property int cfg_iconSpacing: 0
    property int cfg_iconSpacingDefault
    // Stubs for keys managed by other pages
    property bool cfg_showOnlyCurrentScreen
    property bool cfg_showOnlyCurrentScreenDefault
    property bool cfg_showOnlyCurrentDesktop
    property bool cfg_showOnlyCurrentDesktopDefault
    property bool cfg_showOnlyCurrentActivity
    property bool cfg_showOnlyCurrentActivityDefault
    property bool cfg_showOnlyMinimized
    property bool cfg_showOnlyMinimizedDefault
    property bool cfg_unhideOnAttention
    property bool cfg_unhideOnAttentionDefault
    property int cfg_groupingStrategy
    property int cfg_groupingStrategyDefault
    property int cfg_groupedTaskVisualization
    property int cfg_groupedTaskVisualizationDefault
    property bool cfg_groupPopups
    property bool cfg_groupPopupsDefault
    property bool cfg_onlyGroupWhenFull
    property bool cfg_onlyGroupWhenFullDefault
    property var cfg_groupingAppIdBlacklist
    property var cfg_groupingAppIdBlacklistDefault
    property var cfg_groupingLauncherUrlBlacklist
    property var cfg_groupingLauncherUrlBlacklistDefault
    property int cfg_sortingStrategy
    property int cfg_sortingStrategyDefault
    property bool cfg_separateLaunchers
    property bool cfg_separateLaunchersDefault
    property bool cfg_hideLauncherOnStart
    property bool cfg_hideLauncherOnStartDefault
    property var cfg_launchers
    property var cfg_launchersDefault
    property int cfg_middleClickAction
    property int cfg_middleClickActionDefault
    property bool cfg_taskHoverEffect
    property bool cfg_taskHoverEffectDefault
    property int cfg_maxTextLines
    property int cfg_maxTextLinesDefault
    property bool cfg_minimizeActiveTaskOnClick
    property bool cfg_minimizeActiveTaskOnClickDefault
    property bool cfg_reverseMode
    property bool cfg_reverseModeDefault
    property int cfg_wheelEnabled
    property int cfg_wheelEnabledDefault
    property bool cfg_wheelSkipMinimized
    property bool cfg_wheelSkipMinimizedDefault
    property string cfg_taskSections
    property string cfg_taskSectionsDefault
    property bool cfg_exclusiveMode
    property bool cfg_exclusiveModeDefault
    property string cfg_syncGroup
    property string cfg_syncGroupDefault
    property bool cfg_syncGroupingBlacklist
    property bool cfg_syncGroupingBlacklistDefault

    Component.onCompleted: {
        /* Don't rely on bindings for checking the radiobuttons
           When checking forceStripes, the condition for the checked value for the allow stripes button
           became true and that one got checked instead, stealing the checked state for the just clicked checkbox
        */
        if (maxStripes.value === 1) {
            forbidStripes.checked = true;
        } else if (!Plasmoid.configuration.forceStripes && maxStripes.value > 1) {
            allowStripes.checked = true;
        } else if (Plasmoid.configuration.forceStripes && maxStripes.value > 1) {
            forceStripes.checked = true;
        }
    }
    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showToolTips
            Kirigami.FormData.label: i18nc("@label for several checkboxes", "General:")
            text: i18nc("@option:check section General", "Show small window previews when hovering over tasks")
        }

        QQC2.CheckBox {
            id: highlightWindows
            text: i18nc("@option:check section General", "Hide other windows when hovering over previews")
        }

        QQC2.CheckBox {
            id: indicateAudioStreams
            text: i18nc("@option:check section General", "Show an indicator when a task is playing audio")
            checked: cfg_indicateAudioStreams && plasmaPaAvailable
            onToggled: cfg_indicateAudioStreams = checked
            enabled: plasmaPaAvailable
        }

        QQC2.CheckBox {
            id: interactiveMute
            leftPadding: mirrored ? 0 : (indicateAudioStreams.indicator.width + indicateAudioStreams.spacing)
            rightPadding: mirrored ? (indicateAudioStreams.indicator.width + indicateAudioStreams.spacing) : 0
            text: i18nc("@option:check section General", "Mute task when clicking indicator")
            checked: cfg_interactiveMute && plasmaPaAvailable
            onToggled: cfg_interactiveMute = checked
            enabled: indicateAudioStreams.checked && plasmaPaAvailable
        }

        QQC2.CheckBox {
            id: tooltipControls
            text: i18nc("@option:check section General", "Show media and volume controls in tooltip")
            checked: cfg_tooltipControls && plasmaPaAvailable
            onToggled: cfg_tooltipControls = checked
            enabled: plasmaPaAvailable
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.RadioButton {
            id: forbidStripes
            Kirigami.FormData.label: plasmoidVertical
                ? i18nc("@label for radio button group, completes sentence: … when panel is low on space etc.", "Use multi-column view:")
                : i18nc("@label for radio button group, completes sentence: … when panel is low on space etc.", "Use multi-row view:")
            onToggled: {
                if (checked) {
                    maxStripes.value = 1
                }
            }
            text: i18nc("@option:radio Never use multi-column view for Task Manager", "Never")
        }

        QQC2.RadioButton {
            id: allowStripes
            onToggled: {
                if (checked) {
                    maxStripes.value = Math.max(2, maxStripes.value)
                }
            }
            text: i18nc("@option:radio completes sentence: Use multi-column/row view", "When panel is low on space and thick enough")
        }

        QQC2.RadioButton {
            id: forceStripes
            onToggled: {
                if (checked) {
                    maxStripes.value = Math.max(2, maxStripes.value)
                }
            }
            text: i18nc("@option:radio completes sentence: Use multi-column/row view", "Always when panel is thick enough")
        }

        QQC2.SpinBox {
            id: maxStripes
            enabled: maxStripes.value > 1
            Kirigami.FormData.label: plasmoidVertical
            ? i18nc("@label:spinbox maximum number of columns for tasks", "Maximum columns:")
            : i18nc("@label:spinbox maximum number of rows for tasks", "Maximum rows:")
            from: 1
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Spacing between icons:")

            model: [
                {
                    "label": i18nc("@item:inlistbox Icon spacing", "Small"),
                    "spacing": 0
                },
                {
                    "label": i18nc("@item:inlistbox Icon spacing", "Normal"),
                    "spacing": 1
                },
                {
                    "label": i18nc("@item:inlistbox Icon spacing", "Large"),
                    "spacing": 3
                },
            ]

            textRole: "label"
            enabled: !Kirigami.Settings.tabletMode

            currentIndex: {
                if (Kirigami.Settings.tabletMode) {
                    return 2; // Large
                }

                switch (cfg_iconSpacing) {
                    case 0: return 0; // Small
                    case 1: return 1; // Normal
                    case 3: return 2; // Large
                }
            }
            onActivated: index => {
                cfg_iconSpacing = model[currentIndex]["spacing"];
            }
        }

        QQC2.Label {
            visible: Kirigami.Settings.tabletMode
            text: i18nc("@info:usagetip under a set of radio buttons when Touch Mode is on", "Automatically set to Large when in Touch mode")
            font: Kirigami.Theme.smallFont
        }
    }
}
