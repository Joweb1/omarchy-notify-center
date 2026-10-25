# Notification Center for Omarchy

Android/iOS-style notification pills and an iPhone-lock-screen-style stacked
notification center for the Omarchy 4 shell (Quickshell). One plugin replaces
the built-in notification daemon, adds a bar bell with unread badge, and keeps
persistent history.

> Omarchy 4 uses Quickshell for notifications. This plugin is QML, not Mako or
> Waybar. It requires `omarchy-shell` and writes only to your user config/state.

## Features

- Floating notification pills anchored left, center, or right.
- Stacked deck with a `+N more` affordance.
- Compact red close button with a theme-aware background (light disc on dark
  themes, dark disc on light themes).
- Click a pill to invoke its default action or focus/launch its app.
- Action buttons, a `⋯` menu with Dismiss, Mute app, and Settings.
- Hover pauses the auto-dismiss timer.
- Critical notifications use the urgent color and can be kept until dismissed.
- Persistent history in `~/.local/state/omarchy-notify-center/history.json`.
- Bar bell with unread count and DND state.
- Notification center: a borderless, translucent glass panel tinted by the
  active theme, with stacked cards that expand into a scrollable list, plus
  per-item close, Mark read, Clear, and live settings.
- Device strip at the bottom of the notification center with icons for
  plugged-in USB peripherals (mice, keyboards, audio devices, drives,
  printers, phones, generic devices) and connected external monitors.
  Drives/devices/phones open Files; printers open Print Settings; monitors
  open the monitor configuration menu. Integrated USB hardware (camera,
  Bluetooth, hubs) and the internal laptop panel are not shown.
- A notification when a new peripheral is plugged in, with the matching icon
  and a click action where one is available.
- Do Not Disturb, per-app mute, configurable timeout, visible card count,
  animation, and popup position.
- `replace_id` support, action identifiers, transient filtering, and image/app
  icons.
- Live theme changes through Omarchy's `Color` and `Style` singletons.

## Requirements

- Omarchy 4 (`omarchy-shell`, Quickshell 0.3+)
- `jq` and `hyprctl` for the focus helper and install scripts
- `omarchy-notification-send` (ships with Omarchy) for device notifications
- `notify-send` (usually from `libnotify`) for testing
- Optional device click actions: Nautilus (or `omarchy-launch-nautilus`),
  `system-config-printer`, and `omarchy-menu`

## Install

### From the marketplace or git

```bash
omarchy plugin disable omarchy.notifications
omarchy plugin add https://github.com/Joweb1/omarchy-notify-center.git --enable
omarchy plugin enable jovibe.notify-center --section right
```

The notification bus allows one owner, so disable the built-in
`omarchy.notifications` service before adding this plugin. `--enable` installs
the bar widget; the last command only moves/keeps it in the right section.

The official `omarchy plugin add` command clones, validates, and enables the
plugin. It does not run install hooks. The plugin creates its config, state
directory, and history on first start. Run the optional `install.sh` from the
installed plugin directory if you also want the `notify-center` CLI, the
`SUPER + N` shortcut, and migration from the old partial plugin:

```bash
~/.config/omarchy/plugins/jovibe.notify-center/install.sh
```

### From this checkout

```bash
cd omarchy-notify-center
./install.sh
```

The installer:

1. backs up `~/.config/omarchy/shell.json`,
2. disables `omarchy.notifications` and the old partial `notify-center` plugin,
3. copies the plugin to `~/.config/omarchy/plugins/jovibe.notify-center`,
4. enables the bar widget in the right section,
5. seeds `~/.config/omarchy-notify-center/config.toml`,
6. links `notify-center` into `~/.local/bin`.

It is safe to run again. It does not start a second notification daemon.

After install:

```bash
notify-send "Notification Center" "It works"
omarchy-shell notify-center status
# after running the optional install.sh:
notify-center status
```

### Migrating from `notify-center`

The installer disables the old plugin but leaves its folder in place. Remove it
when you are happy with the new one:

```bash
omarchy plugin remove notify-center --yes
```

## Usage

- **`SUPER + N`**: open/close the notification center. The installer adds this
  binding to `~/.config/hypr/bindings.lua` unless the key is already in use.
- **Left click the bell**: open/close the notification center.
- **Right click the bell**: toggle Do Not Disturb.
- **Middle click the bell**: mark all read.
- **Click a pill**: invoke the default action, or focus its application.
- **Click `⋯`**: dismiss, mute the app, or open settings.
- **Click the red `✕`**: dismiss without opening.

### Notification center

The center opens at the right edge of the screen by default. Unread/current
notifications are shown as a stack: the newest card is expanded with slightly
rounded corners, while older cards tuck underneath at full pill
radius. Scroll down with the mouse wheel/trackpad, press an arrow key, click
a stacked card, or use the `Stack` button to expand into the full scrollable
list, where every card uses the smaller radius and wheel/arrow scrolling
continues normally. When the expanded list is at the very top, scrolling up
once more collapses back to the stack. `Stack`/`Collapse` toggles explicitly.
Escape closes; `d` toggles DND, `s` opens settings, `m` marks all read.

The surrounding panel has no border or outline. Its surface is translucent and
theme-adaptive: a dark glass tint in dark themes and a whiter glass tint in
light themes, so the wallpaper or app behind it shows through.

The settings page writes to `config.toml` immediately and applies live.

### Devices and displays

The bottom of the notification center shows an icon for each peripheral that a
user can plug in or attach. They are grouped by the interfaces the device
exposes:

- mouse, keyboard, audio device, drive, printer, phone, generic USB device, or
  unknown device (question-mark icon)
- external monitors connected through HDMI, DisplayPort, DVI, or VGA
- drives, generic USB devices, and phones open Files
- printers open Print Settings (or the available printer configuration app)
- monitors open Omarchy's monitor configuration menu
- devices with no supported app/menu, such as a mouse or keyboard, are
  detected but their icon does nothing when clicked

Soldered internal USB hardware is filtered out: the built-in webcam, internal
Bluetooth adapter, root hubs, and hubs are not shown. The internal eDP/LVDS/DSI
laptop panel is also excluded. Devices are rescanned when the panel opens and
every few seconds in the background, so plugging or unplugging a device updates
the strip without restarting the shell. The first scan after a shell restart
establishes the baseline silently; devices connected after that produce a
notification such as `USB mouse connected`, `Phone connected`, or `External
monitor connected`. Notifications are sent through `omarchy-notification-send`
and support the same click actions as the footer icons.

To add the shortcut manually:

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + N", "Notification center", "omarchy-shell notify-center toggle")
```

## Configuration

`~/.config/omarchy-notify-center/config.toml`:

```toml
[general]
position = "right"         # left | center | right
timeout = 5                # seconds, 0 = never expire
critical_timeout = 5
sticky_critical = false
max_visible = 3            # popup cards in the deck: 1-3
max_stack = 50             # live queue cap
history_limit = 200
animation = true
width = 380
dnd = false

[mute]
apps = []                  # lowercase app names
```

The file is watched; edits reload without restarting the shell. Use the panel
or `notify-center` for changes if you do not want to hand-edit TOML.

## CLI

```bash
notify-center open
notify-center close
notify-center toggle
notify-center settings
notify-center status
notify-center history
notify-center dnd on|off|toggle
notify-center read-all
notify-center clear
notify-center mute "Google Chrome"
notify-center unmute "Google Chrome"
notify-center remove <key>
notify-center invoke <key>
notify-center position left|center|right
notify-center reload
```

All commands are thin wrappers around `omarchy-shell notify-center ...`.

## Uninstall

```bash
omarchy plugin disable jovibe.notify-center
omarchy plugin remove jovibe.notify-center --yes
omarchy plugin enable omarchy.notifications
```

Or, from this checkout:

```bash
./uninstall.sh          # keeps config and history
./uninstall.sh --purge  # removes config and history too
```

Uninstall disables the plugin, removes its bar entry, deletes the CLI link, and
restores Omarchy's built-in notification service. It leaves unrelated plugins
and shell settings alone.

## How it works

- `Service.qml` is the notification server for `org.freedesktop.Notifications`,
  owns the popup model, action invocation, history file, config watcher, and
  the `notify-center` IPC target.
- `NotificationCard.qml` is one presentational pill.
- `BarWidget.qml` is the bar bell, badge, DND state, and panel host.
- `Panel.qml` is the stacked/scrolling notification center and settings page.
- `PanelButton.qml` is the shared small control.
- `bin/notify-center-focus` matches Hyprland clients by app/desktop class and
  falls back to `gtk-launch`/`xdg-open`.
- `bin/notify-center-devices` enumerates pluggable USB peripherals from
  `/sys/bus/usb/devices` and external DRM connectors from `/sys/class/drm`,
  classifies them, and emits JSON for the footer strip.

Theme colors come from Omarchy's live `Color`/`Style` singletons, so switching
themes updates pills, buttons, and the close disc without a restart.

## Troubleshooting

- **Notifications stopped after install**: make sure only one daemon is on the
  bus. `omarchy plugin list | grep -E 'notifications|notify-center'` should show
  `jovibe.notify-center` enabled and `omarchy.notifications` disabled.
- **No bar icon**: `omarchy plugin enable jovibe.notify-center --section right`.
- **Shortcut missing**: confirm `SUPER + N` is not bound elsewhere, or add the
  snippet above to `~/.config/hypr/bindings.lua` and run `hyprctl reload`.
- **Service did not start**: `journalctl --user -u omarchy-shell -n 100 --no-pager`.
- **Old plugin still visible**: it is disabled by `install.sh`, but you can
  remove its folder with `omarchy plugin remove notify-center --yes`.
- **Config changes ignored**: check TOML syntax; the watcher reloads on save.

## License

MIT. See `LICENSE`.
