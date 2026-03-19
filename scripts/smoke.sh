#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
TERMINAL_NAME="${SMOKE_TERMINAL:-ghostty}"
TITLE_HINT="${SMOKE_TITLE-codex}"
PROJECT_NAME="${SMOKE_PROJECT:-overwatchr}"
AGENT_ID="smoke-$(date +%s)"
APP_PID=""
EXIT_CODE=0

cleanup() {
  "$ROOT_DIR/.build/${BUILD_CONFIGURATION}/overwatchr" done --agent "$AGENT_ID" --project "$PROJECT_NAME" >/dev/null 2>&1 || true
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Building release binaries..."
swift build -c "$BUILD_CONFIGURATION" --package-path "$ROOT_DIR" >/dev/null

echo "Launching menu bar app..."
"$ROOT_DIR/.build/${BUILD_CONFIGURATION}/overwatchr-app" >/tmp/overwatchr-smoke.log 2>&1 &
APP_PID="$!"
sleep 2

echo "Writing temporary alert for $TERMINAL_NAME..."
ALERT_COMMAND=(
  "$ROOT_DIR/.build/${BUILD_CONFIGURATION}/overwatchr"
  alert
  --agent "$AGENT_ID"
  --project "$PROJECT_NAME"
  --terminal "$TERMINAL_NAME"
)

if [[ -n "$TITLE_HINT" ]]; then
  ALERT_COMMAND+=(--title "$TITLE_HINT")
fi

"${ALERT_COMMAND[@]}" >/dev/null

sleep 2

EXPECTED_FRONTMOST="$TERMINAL_NAME"
TERMINAL_NAME_LOWER="$(printf '%s' "$TERMINAL_NAME" | tr '[:upper:]' '[:lower:]')"
case "$TERMINAL_NAME_LOWER" in
  ghostty) EXPECTED_FRONTMOST="ghostty" ;;
  iterm|iterm2) EXPECTED_FRONTMOST="iTerm2" ;;
  terminal|terminal.app) EXPECTED_FRONTMOST="Terminal" ;;
esac

if command -v osascript >/dev/null 2>&1; then
  echo "Forcing Finder frontmost before hotkey jump..."
  osascript -e 'tell application "Finder" to activate' >/dev/null
  sleep 1

  echo "Sending Cmd+Shift+A..."
  osascript -e 'tell application "System Events" to keystroke "A" using {command down, shift down}' >/dev/null
  sleep 2

  FRONTMOST="$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' | tr -d '\r')"
  echo "Frontmost app after hotkey: $FRONTMOST"

  FRONTMOST_LOWER="$(printf '%s' "$FRONTMOST" | tr '[:upper:]' '[:lower:]')"
  EXPECTED_FRONTMOST_LOWER="$(printf '%s' "$EXPECTED_FRONTMOST" | tr '[:upper:]' '[:lower:]')"

  if [[ "$FRONTMOST_LOWER" != "$EXPECTED_FRONTMOST_LOWER" ]]; then
    echo "Smoke test failed: expected ${EXPECTED_FRONTMOST}, got ${FRONTMOST}" >&2
    EXIT_CODE=1
  fi
else
  echo "osascript is unavailable; skipped hotkey/focus verification."
fi

if [[ "${CAPTURE_SCREEN:-0}" == "1" ]]; then
  SCREENSHOT_PATH="${SCREENSHOT_PATH:-/tmp/overwatchr-smoke.png}"
  screencapture -x "$SCREENSHOT_PATH"
  echo "Captured screenshot at $SCREENSHOT_PATH"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "Smoke test passed."
fi

exit "$EXIT_CODE"
