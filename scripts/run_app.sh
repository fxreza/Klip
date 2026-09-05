#!/bin/bash
set -euo pipefail

# =============================================================================
# Run locally built app
# Usage: scripts/run_app.sh [--data-dir <dir>] [--kill]
#
# Debug window control (implemented by app):
#   notifyutil -p com.fxreza.klip.debug.show   - show window
#   notifyutil -p com.fxreza.klip.debug.hide   - hide window
#   notifyutil -p com.fxreza.klip.debug.toggle - toggle window
#   notifyutil -p com.fxreza.klip.debug.quit   - quit app
#   notifyutil -p com.fxreza.klip.debug.selectNext     - move selection down
#   notifyutil -p com.fxreza.klip.debug.selectPrevious - move selection up
#
# Screenshot:
#   screencapture -x file.png
# =============================================================================

# Environment-overridable constants
APP_NAME=${APP_NAME:-Klip}

# Parse arguments
DATA_DIR=""
KILL_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --kill)
            KILL_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Get absolute repo path
REPO_PATH="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="${REPO_PATH}/build.noindex/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# Default data directory
if [[ -z "$DATA_DIR" ]]; then
    DATA_DIR="${REPO_PATH}/build.noindex/test-data"
fi

# Kill function - only kills locally built instance
kill_local_instance() {
    # Kill only the locally built app, never the installed ones
    if pgrep -f "${REPO_PATH}/build.noindex/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
        echo "🛑 Killing locally built ${APP_NAME}..."
        pkill -f "${REPO_PATH}/build.noindex/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" || true
        sleep 0.5
        echo "✅ Killed"
    else
        echo "ℹ️  No local ${APP_NAME} instance running"
    fi
}

# If --kill flag, just kill and exit
if [[ "$KILL_ONLY" == true ]]; then
    kill_local_instance
    exit 0
fi

# Kill any existing local instance before launching new one
kill_local_instance

# A local test build must never share the installed app's bundle identifier.
# Two live copies of one identifier wedged macOS's per-identifier menu bar
# state so badly that the status item stopped being laid out at all, and it
# survived a logout and a LaunchServices rebuild — the identifier had to be
# changed to recover. Rebuild with a dev identifier instead of reusing the
# installed one.
BUNDLE_ID_IN_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    "${REPO_PATH}/build.noindex/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "")
INSTALLED_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    "/Applications/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "")
if [[ -n "$BUNDLE_ID_IN_BUILD" && "$BUNDLE_ID_IN_BUILD" == "$INSTALLED_ID" ]]; then
    echo "❌ build.noindex/${APP_NAME}.app has the same bundle ID as /Applications (${INSTALLED_ID})."
    echo "   Rebuild it with its own identifier first:"
    echo "     BUNDLE_ID=${INSTALLED_ID}.dev scripts/build_local.sh"
    exit 1
fi

# Check if binary exists
if [[ ! -f "$BINARY" ]]; then
    echo "❌ Error: Binary not found at ${BINARY}"
    echo "   Run: scripts/build_local.sh"
    exit 1
fi

# Create data directory if needed
mkdir -p "$DATA_DIR"

# Prepare log file
LOG_FILE="${REPO_PATH}/build.noindex/run.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Launch binary directly with environment variables
# Using nohup to keep it running after shell closes
echo "🚀 Launching ${APP_NAME}..."
echo "📁 Data directory: ${DATA_DIR}"
echo "📝 Log: ${LOG_FILE}"

nohup env \
    KLIP_DATA_DIR="$DATA_DIR" \
    KLIP_DEBUG=1 \
    "$BINARY" \
    >"$LOG_FILE" 2>&1 &

PID=$!
echo "✅ Started with PID: $PID"

# Brief delay to ensure it's actually running
sleep 0.5

# Verify it's still running
if ! pgrep -f "${REPO_PATH}/build.noindex/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    echo "❌ Failed to start. Last 20 lines of log:"
    tail -20 "$LOG_FILE" >&2
    exit 1
fi

echo "📌 To show/hide debug window:     notifyutil -p com.fxreza.klip.debug.{show,hide,toggle}"
echo "📌 To quit app:                   notifyutil -p com.fxreza.klip.debug.quit"
echo "📌 To take screenshot:            screencapture -x file.png"
echo "📌 To kill this instance:         scripts/run_app.sh --kill"
