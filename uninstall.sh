#!/bin/bash
# Uninstall jovibe.notify-center and restore Omarchy's built-in notifications.

set -euo pipefail

ID="jovibe.notify-center"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
DEST="$PLUGINS_DIR/$ID"
CONFIG_DIR="$HOME/.config/omarchy-notify-center"
STATE_DIR="$HOME/.local/state/omarchy-notify-center"
BIN_LINK="$HOME/.local/bin/notify-center"
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"
PURGE=0

usage() {
  echo "Usage: uninstall.sh [--purge]"
  echo "  --purge  Also remove config.toml, history, and install state."
}

while (( $# > 0 )); do
  case "$1" in
    --purge) PURGE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_is_install=0
if [[ $(realpath "$self_dir") == $(realpath -m "$DEST") ]]; then
  source_is_install=1
fi

if command -v omarchy >/dev/null 2>&1 && command -v omarchy-shell >/dev/null 2>&1; then
  omarchy plugin disable "$ID" >/dev/null 2>&1 || true
fi

if [[ -f $BINDINGS_FILE ]] && grep -q '^-- >>> jovibe.notify-center shortcut >>>$' "$BINDINGS_FILE"; then
  cp -a "$BINDINGS_FILE" "$BINDINGS_FILE.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  sed -i '/^-- >>> jovibe.notify-center shortcut >>>$/,/^-- <<< jovibe.notify-center shortcut <<<$/d' "$BINDINGS_FILE"
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
fi

if [[ -L $BIN_LINK ]]; then
  target=$(readlink "$BIN_LINK" || true)
  if [[ $target == "$DEST/bin/notify-center" ]]; then
    rm -f "$BIN_LINK"
  fi
elif [[ -f $BIN_LINK ]] && grep -q "omarchy-shell notify-center" "$BIN_LINK" 2>/dev/null; then
  rm -f "$BIN_LINK"
fi

if [[ -d $DEST ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    if (( source_is_install )); then
      # omarchy plugin remove deletes this directory, including this script;
      # bash has already read it, so continue safely afterwards.
      omarchy plugin remove "$ID" --yes >/dev/null 2>&1 || rm -rf "$DEST"
    else
      omarchy plugin remove "$ID" --yes >/dev/null 2>&1 || rm -rf "$DEST"
    fi
  else
    rm -rf "$DEST"
  fi
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable omarchy.notifications >/dev/null 2>&1 || true
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if (( PURGE )); then
  rm -rf "$CONFIG_DIR" "$STATE_DIR"
  echo "Removed config and notification history."
else
  echo "Kept $CONFIG_DIR and $STATE_DIR (use --purge to remove)."
fi

echo "Uninstalled Notification Center; built-in notifications restored."
