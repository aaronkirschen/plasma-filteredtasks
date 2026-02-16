# Filtered Task Manager

A KDE Plasma 6 panel widget that extends the default Icons-Only Task Manager with **app grouping**, **colored sections**, and **spacers** — giving you full control over how your taskbar is organized.

## Features

- **App Groups** — Create named groups and assign apps to them. Each group becomes a distinct section on your panel.
- **Color-Coded Groups** — Set a background color per group so you can visually distinguish sections at a glance.
- **Spacers** — Add spacers between groups with configurable pixel widths to control spacing.
- **Ungrouped Section** — A catch-all section for apps not assigned to any group. Can be positioned anywhere in the layout.
- **Drag-and-Drop Reordering** — Drag groups and spacers to rearrange your panel layout. Drag app chips between groups to reassign them.
- **Keyboard Navigation** — Tab between cards, Alt+Up/Down to reorder. Focus indicator shows which card is selected.
- **Compact View** — Toggle a collapsed view for easier reordering when you have many groups.
- **Exclusive Mode** — Prevent grouped apps from appearing in other Filtered Task Manager instances on the same panel.
- **Undo Delete** — Accidentally delete a group? A toast appears with an Undo button for 5 seconds.
- **App Picker** — Searchable list of all installed applications for easy group assignment.

## Tested On

- **KDE Plasma 6.5.5**
- **Plasma API minimum version: 6.0**

This widget is a fork of the stock KDE Plasma Icons-Only Task Manager.

## Installation

```bash
git clone https://github.com/aaronkirschen/plasma-filteredtasks.git
cp -r plasma-filteredtasks ~/.local/share/plasma/plasmoids/org.kde.plasma.filteredtasks
```

Then restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

### Adding to Your Panel

1. Right-click your panel → **Add Widgets...**
2. Search for **Filtered Task Manager**
3. Drag it onto your panel
4. Right-click the widget → **Configure Filtered Tasks Manager...** to set up groups

### Uninstall

```bash
rm -rf ~/.local/share/plasma/plasmoids/org.kde.plasma.filteredtasks
kquitapp6 plasmashell && kstart plasmashell
```

## Configuration

Right-click the widget on your panel and choose **Configure...** → **Groups** tab.

- **Add Group** — Creates a new named group. Click "Add Apps..." to assign applications.
- **Add Spacer** — Inserts a spacer with configurable width (in pixels).
- **Add Ungrouped** — Adds the catch-all section for unassigned apps.
- **Reorder** — Drag the handle on the left, use the arrow buttons, or press Alt+Up/Down.
- **Color** — Click the color swatch on any card to set a background color.
- **Move Apps** — Drag app chips from one group to another.
- **Compact View** — Click the Compact/Expand toggle to collapse cards for easier sorting.

## License

GPL-2.0-or-later. Based on the KDE Plasma Task Manager by Eike Hein.
