#!/usr/bin/env bash
# Removes the Gamepad Display plugin from KineticWE's noctalia-kwe fork.
# noctalia-kwe installs plugins in ~/.local/share/noctalia-kwe/plugins and
# writes widget instances to ~/.local/state/noctalia-kwe/settings.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="noctalia-kwe"
CLI="noctalia-kwe"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
STATE_HOME="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/dualsense"
SETTINGS="$STATE_HOME/$APP_DIR/settings.toml"
PLUGIN_DATA="$STATE_HOME/$APP_DIR/plugins/data/deadYokai/dualsense"
LOCK="$RUNTIME_DIR/noctalia-dualsense-battery.lock"
STATE="$RUNTIME_DIR/noctalia-dualsense-battery.json"
INPUT_LOCK="$RUNTIME_DIR/noctalia-dualsense-inputs.lock"
INPUT_STATE="$RUNTIME_DIR/noctalia-dualsense-inputs.json"
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes]

Removes the Gamepad Display plugin from noctalia-kwe:
  $PLUGIN_DIR
  $PLUGIN_DATA
  its desktop widget instances in $SETTINGS
  $LOCK, $STATE
  $INPUT_LOCK and $INPUT_STATE

Options:
  -y, --yes   Do not ask for confirmation
  -h, --help  Show this help
EOF
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will remove the Gamepad Display plugin:"
    echo "  $PLUGIN_DIR"
    echo "  $PLUGIN_DATA"
    echo "  its desktop widget instances in $SETTINGS"
    echo "  $LOCK, $STATE"
    echo "  $INPUT_LOCK and $INPUT_STATE"
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# Stop the service through the running shell so its onExit hook cleans up.
if [ -z "${NOCTALIA_DATA_HOME:-}" ] && [ -z "${NOCTALIA_STATE_HOME:-}" ] \
    && command -v "$CLI" >/dev/null 2>&1; then
    if "$CLI" msg plugins disable deadYokai/dualsense >/dev/null 2>&1; then
        echo "==> Disabled deadYokai/dualsense"
        sleep 0.5
    fi
fi

# Remove only this plugin's desktop-widget instances; other widgets stay.
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$SCRIPT_DIR/remove-plugin-widgets.py" ]; then
    python3 "$SCRIPT_DIR/remove-plugin-widgets.py" \
        "$SETTINGS" "deadYokai/dualsense:inputs" || true
    python3 "$SCRIPT_DIR/remove-plugin-widgets.py" \
        "$SETTINGS" "deadYokai/dualsense:card" || true
else
    echo "==> Skipping widget cleanup (no settings file, python3, or helper)"
fi

# Kill a daemon left behind if the service was not running.
kill_daemon() {
    local lock="$1" pattern="$2" pid
    [ -f "$lock" ] || return 0
    pid="$(tr -dc '0-9' < "$lock" || true)"
    if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; then
        if [ -r "/proc/$pid/cmdline" ] \
            && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q "$pattern"; then
            kill "$pid" 2>/dev/null || true
            sleep 0.3
        fi
    fi
}
kill_daemon "$LOCK" "ds_battery_daemon.py"
kill_daemon "$INPUT_LOCK" "ds_inputs_daemon.py"
rm -f "$LOCK" "$STATE" "$INPUT_LOCK" "$INPUT_STATE"

rm -rf "$PLUGIN_DIR" "$PLUGIN_DATA"
echo "==> Removed $PLUGIN_DIR"
echo "==> Removed $PLUGIN_DATA"
echo "==> Removed runtime state and lock"
echo "Done."
