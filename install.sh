#!/bin/bash
# Local installer for jovibe.notify-center.
#
# The marketplace/git path is:
#   omarchy plugin add <git-url> --enable
#   omarchy plugin disable omarchy.notifications
#
# This script additionally handles the migration from the old partial
# notify-center plugin, installs the CLI, and seeds config/state.

set -euo pipefail

ID="jovibe.notify-center"
NAME="Notification Center"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
DEST="$PLUGINS_DIR/$ID"
CONFIG_DIR="$HOME/.config/omarchy-notify-center"
STATE_DIR="$HOME/.local/state/omarchy-notify-center"
CONFIG_FILE="$CONFIG_DIR/config.toml"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"
BIN_DIR="$HOME/.local/bin"

fail() {
  echo "install: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

have omarchy || fail "omarchy command not found"
have omarchy-shell || fail "omarchy-shell command not found"
have jq || fail "jq command not found"

mkdir -p "$PLUGINS_DIR" "$CONFIG_DIR" "$STATE_DIR" "$BIN_DIR"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=""
if [[ -f $SHELL_CONFIG ]]; then
  backup="$SHELL_CONFIG.bak.$stamp"
  cp -a "$SHELL_CONFIG" "$backup"
fi

if [[ $(realpath "$SOURCE_DIR") != $(realpath -m "$DEST") ]]; then
  echo "Installing files into $DEST"
  mkdir -p "$DEST/bin" "$DEST/examples"
  cp -a "$SOURCE_DIR/Service.qml" "$DEST/Service.qml"
  cp -a "$SOURCE_DIR/NotificationCard.qml" "$DEST/NotificationCard.qml"
  cp -a "$SOURCE_DIR/BarWidget.qml" "$DEST/BarWidget.qml"
  cp -a "$SOURCE_DIR/Panel.qml" "$DEST/Panel.qml"
  cp -a "$SOURCE_DIR/PanelButton.qml" "$DEST/PanelButton.qml"
  cp -a "$SOURCE_DIR/Toml.js" "$DEST/Toml.js"
  cp -a "$SOURCE_DIR/manifest.json" "$DEST/manifest.json"
  cp -a "$SOURCE_DIR/config.toml" "$DEST/config.toml"
  cp -a "$SOURCE_DIR/README.md" "$DEST/README.md" 2>/dev/null || true
  cp -a "$SOURCE_DIR/LICENSE" "$DEST/LICENSE" 2>/dev/null || true
  cp -a "$SOURCE_DIR/bin/notify-center" "$DEST/bin/notify-center"
  cp -a "$SOURCE_DIR/bin/notify-center-focus" "$DEST/bin/notify-center-focus"
  cp -a "$SOURCE_DIR/bin/notify-center-devices" "$DEST/bin/notify-center-devices"
else
  echo "Using plugin checkout at $DEST"
fi

chmod 755 "$DEST/bin/notify-center" "$DEST/bin/notify-center-focus" "$DEST/bin/notify-center-devices"

if [[ ! -f $CONFIG_FILE ]]; then
  cp -a "$SOURCE_DIR/config.toml" "$CONFIG_FILE"
  echo "Seeded $CONFIG_FILE"
fi
touch "$STATE_DIR/.keep"

previous_builtin="unknown"
if omarchy plugin list --json 2>/dev/null | jq -e '.[] | select(.id == "omarchy.notifications") | .enabled == true' >/dev/null 2>&1; then
  previous_builtin="enabled"
else
  previous_builtin="disabled"
fi

old_plugin="absent"
if [[ -d $PLUGINS_DIR/notify-center ]]; then
  old_plugin="present"
fi

cat > "$STATE_DIR/install-state.json" <<EOF
{
  "plugin": "$ID",
  "version": "1.1.0",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "shellConfigBackup": "$backup",
  "previousBuiltinNotifications": "$previous_builtin",
  "oldNotifyCenter": "$old_plugin"
}
EOF

# The notification bus allows exactly one owner. Turn off the built-in daemon
# and the old half-finished plugin before starting this one.
echo "Disabling built-in notifications"
omarchy plugin disable omarchy.notifications >/dev/null 2>&1 || true
if [[ -d $PLUGINS_DIR/notify-center ]]; then
  echo "Disabling old notify-center plugin"
  omarchy plugin disable notify-center >/dev/null 2>&1 || true
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

for _ in $(seq 1 60); do
  if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$ID" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

already_enabled=0
if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null 2>&1; then
  already_enabled=1
fi

if (( already_enabled )); then
  echo "$ID already enabled"
else
  echo "Enabling $ID in the right bar section"
  omarchy plugin enable "$ID" --section right >/dev/null
fi

ln -sfn "$DEST/bin/notify-center" "$BIN_DIR/notify-center"

# Add the notification-center shortcut without taking over an existing
# SUPER + N binding. The marker lets uninstall.sh remove only our block.
if [[ -f $BINDINGS_FILE ]] && ! grep -q 'jovibe.notify-center shortcut' "$BINDINGS_FILE"; then
  if command -v omarchy >/dev/null 2>&1 && omarchy menu keybindings --print 2>/dev/null |
    grep -Eq '^SUPER \+ N([[:space:]]|$)'; then
    echo "SUPER + N is already bound; leaving keybindings untouched." >&2
  else
    bindings_backup="$BINDINGS_FILE.bak.$stamp"
    cp -a "$BINDINGS_FILE" "$bindings_backup"
    cat >> "$BINDINGS_FILE" <<'EOF'

-- >>> jovibe.notify-center shortcut >>>
o.bind("SUPER + N", "Notification center", "omarchy-shell notify-center toggle")
-- <<< jovibe.notify-center shortcut <<<
EOF
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl reload >/dev/null 2>&1 || true
    fi
    echo "Bound SUPER + N to the notification center."
  fi
fi

ready=0
for _ in $(seq 1 80); do
  if [[ $(omarchy-shell notify-center ping 2>/dev/null || true) == "ok" ]]; then
    ready=1
    break
  fi
  sleep 0.1
done

if (( ready )); then
  echo "Service is running."
  echo "Try: notify-send 'Notification Center' 'It works'"
else
  echo "Warning: the service has not answered yet." >&2
  echo "Check: journalctl --user -u omarchy-shell -n 80 --no-pager" >&2
fi

echo
echo "Installed $NAME."
echo "Shortcut: SUPER + N"
echo "CLI:     notify-center {toggle,status,dnd,clear,settings,position}"
echo "Config:  $CONFIG_FILE"
echo "State:   $STATE_DIR/history.json"
echo "Backup:  ${backup:-none}"
