# Filtered Task Manager

A KDE Plasma 6 panel widget that extends the default Icons-Only Task Manager with **layout profiles**, **synchronized panels**, **app sections**, **colored sections**, and **spacers** — giving you full control over how your taskbar is organized across one or more displays.

![Section configuration](screenshots/group-config.png)

## Features

- **Layout Profiles** — Give a panel layout a name, then select the same profile in another Filtered Task Manager widget to keep both copies identical.
- **Live Multi-Panel Sync** — Changes made by any widget using a profile are shared immediately, including sections, spacers, app assignments and ordering, colors, and placement. This is useful for keeping taskbars on multiple monitors in sync.
- **App Sections** — Create named sections and assign apps to them. Each section becomes a distinct area on your panel.
- **Color-Coded Sections** — Set a background color per section so you can visually distinguish them at a glance.
- **Spacers** — Add spacers between sections with configurable pixel widths to control spacing.
- **Default Section** — A movable catch-all section displays apps that have not been assigned elsewhere and remembers their order.
- **Flexible Placement** — Float sections and spacers toward either end of a horizontal or vertical panel.
- **Drag-and-Drop Reordering** — Reorder sections, spacers, and apps directly. Drag app chips between sections to reassign them.
- **Keyboard Navigation** — Arrow keys navigate between cards; Alt+Up/Down reorders them. A focus indicator shows the selected card.
- **Compact View** — Toggle a collapsed view for easier reordering when you have many sections.
- **Synced Grouping Preferences** — Optionally share per-app grouping exceptions between widgets using the same layout profile.
- **Exclusive Mode** — Prevent apps assigned to this widget's sections from also appearing in other Filtered Task Manager instances.
- **Undo Delete** — Accidentally delete a section? A toast appears with an Undo button for 5 seconds.
- **App Picker** — Searchable list of all installed applications for easy section assignment.

## Tested On

- **Arch Linux (rolling), KDE Plasma 6.7.4, Qt 6.11.2**
- **KDE Plasma 6.5.5**
- **Plasma API minimum version: 6.0**

This widget is a fork of the stock KDE Plasma Icons-Only Task Manager.

## Installation

### Build from source

Requires KDE Plasma 6 development packages (ECM, Plasma, KF6, etc.).

On Arch Linux, install the build tools with:

```bash
sudo pacman -S --needed base-devel cmake extra-cmake-modules
```

Build and install:

```bash
git clone https://github.com/aaronkirschen/plasma-filteredtasks.git
cd plasma-filteredtasks
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

`KDE_INSTALL_USE_QT_SYS_PATHS=ON` is required on Arch so the compiled applet is installed in Qt 6's plugin directory (`/usr/lib/qt6/plugins/plasma/applets`) and appears in Plasma's widget picker.

Then refresh KDE's service cache and restart Plasma Shell:

```bash
kbuildsycoca6
systemctl --user restart plasma-plasmashell.service
```

### Adding to Your Panel

1. Right-click your panel → **Add Widgets...**
2. Search for **Filtered Task Manager**
3. Drag it onto your panel
4. Right-click the widget → **Configure Filtered Tasks Manager...**

To mirror a layout on another monitor, add another widget to that panel and select the same layout profile in its **Sections** settings.

### Uninstall

From the repository directory:

```bash
sudo cmake --build build --target uninstall
kbuildsycoca6
systemctl --user restart plasma-plasmashell.service
```

## Configuration

Right-click the widget on your panel and choose **Configure...** → **Sections**.

- **Layout Profile** — Create or select a named profile. Widgets using the same profile mirror the layout and remain synchronized.
- **Leave Profile** — Stop synchronizing a widget while retaining its current layout.
- **Add Section** — Create a named section. Click **Add Apps...** to assign applications.
- **Add Spacer** — Insert a spacer with a configurable width in pixels.
- **Add Default Section** — Add the catch-all section for apps not explicitly assigned elsewhere.
- **Reorder** — Drag the handle, use the arrow buttons, or press Alt+Up/Down. Arrow keys navigate between cards.
- **Color** — Click a section's color swatch to set its background color.
- **Move Apps** — Drag app chips from one section to another.
- **Compact View** — Use Compact/Expand to collapse cards for easier sorting.
- **Sync per-app grouping** — In **Behavior**, choose whether grouping exceptions are shared by widgets using the same profile.

## License

GPL-2.0-or-later. Based on the KDE Plasma Task Manager by Eike Hein.
