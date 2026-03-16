/*
    SPDX-FileCopyrightText: 2012-2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Aaron Kirschen <aaronkirschen@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import org.kde.kirigami as Kirigami

const iconMargin = Math.round(Kirigami.Units.smallSpacing / 4);
const labelMargin = Kirigami.Units.smallSpacing;

function horizontalMargins() {
    const spacingAdjustment = Kirigami.Settings.tabletMode ? 3 : tasks.plasmoid.configuration.iconSpacing;
    return (taskFrame.margins.left + taskFrame.margins.right) * (tasks.vertical ? 1 : spacingAdjustment);
}

function verticalMargins() {
    const spacingAdjustment = Kirigami.Settings.tabletMode ? 3 : tasks.plasmoid.configuration.iconSpacing;
    return (taskFrame.margins.top + taskFrame.margins.bottom) * (tasks.vertical ? spacingAdjustment : 1);
}

function adjustMargin(height, margin) {
    const available = height - verticalMargins();

    if (available < Kirigami.Units.iconSizes.small) {
        return Math.floor((margin * (Kirigami.Units.iconSizes.small / available)) / 3);
    }

    return margin;
}

function maxStripes() {
    const length = tasks.vertical ? tasks.width : tasks.height;
    const minimum = tasks.vertical ? preferredMinWidth() : preferredMinHeight();

    return Math.min(tasks.plasmoid.configuration.maxStripes, Math.max(1, Math.floor(length / minimum)));
}

function preferredMinWidth() {
    return preferredMinLauncherWidth();
}

function preferredMaxWidth() {
    if (tasks.vertical) {
        return tasks.width === 0 ? 0 : tasks.width + verticalMargins();
    }
    return tasks.height === 0 ? 0 : tasks.height + horizontalMargins();
}

function preferredMinHeight() {
    // TODO FIXME UPSTREAM: Port to proper font metrics for descenders once we have access to them.
    return Kirigami.Units.iconSizes.sizeForLabels + 4;
}

function preferredMaxHeight() {
    if (tasks.vertical) {
        return verticalMargins() + tasks.width / maxStripes();
    }
    return verticalMargins() +
        Math.min(Kirigami.Units.iconSizes.small * 3,
                 Kirigami.Units.iconSizes.sizeForLabels * 3);
}

function preferredHeightInPopup() {
    return verticalMargins() + Math.max(Kirigami.Units.iconSizes.sizeForLabels,
                                        Kirigami.Units.iconSizes.medium);
}

function spaceRequiredToShowText() {
    // gridUnit is the height of the default font, but only one isn't enough to
    // show anything but the elision character. 2 is too high and results in
    // text appearing only at excessively high widths.
    return Math.round(Kirigami.Units.gridUnit * 1.5);
}

function preferredMinLauncherWidth() {
    const baseWidth = tasks.vertical ? preferredMinHeight() : Math.min(tasks.height, Kirigami.Units.iconSizes.small * 3);

    return (baseWidth + horizontalMargins())
        - (adjustMargin(baseWidth, taskFrame.margins.top) + adjustMargin(baseWidth, taskFrame.margins.bottom));
}

function maximumContextMenuTextWidth() {
    return (Kirigami.Units.iconSizes.sizeForLabels * 28);
}

