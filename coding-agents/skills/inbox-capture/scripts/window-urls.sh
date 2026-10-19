#!/usr/bin/env bash
# window-urls.sh — get the URLs of all tabs in a given Chrome window
# Output: one URL per line
# Args: window id (2nd column of list-windows.sh). Not the window number: numbers are
#   z-order indexes and point at a different window once focus changes.
#   If omitted, pick via fzf; auto-selected when only one window is open.
# Limitation: macOS + Google Chrome only (depends on osascript)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -gt 0 ]; then
  # The id is interpolated into AppleScript, so only digits may pass.
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "window-urls.sh: window id must be numeric: $1" >&2
    exit 2
  fi
  WIN_ID="$1"
else
  WINDOWS=$("$SCRIPT_DIR/list-windows.sh")
  if [ -z "$WINDOWS" ]; then
    echo "window-urls.sh: no Chrome windows are open" >&2
    exit 1
  fi
  if [ "$(echo "$WINDOWS" | grep -c '|')" -eq 1 ]; then
    SELECTED="$WINDOWS"
  else
    SELECTED=$(echo "$WINDOWS" | fzf --prompt="Chrome window> " --height=~40% --no-sort \
      --delimiter='|' --with-nth=1,3,4 < /dev/tty 2>/dev/tty)
  fi
  WIN_ID=$(echo "$SELECTED" | cut -d'|' -f2)
  if ! [[ "$WIN_ID" =~ ^[0-9]+$ ]]; then
    echo "window-urls.sh: no window selected" >&2
    exit 1
  fi
fi

# Output the URLs of all tabs in the chosen window
if ! osascript <<APPLESCRIPT
tell application "Google Chrome"
  set urlList to ""
  repeat with t in (tabs of (window id $WIN_ID))
    set urlList to urlList & (URL of t) & linefeed
  end repeat
  return urlList
end tell
APPLESCRIPT
then
  echo "window-urls.sh: no Chrome window with id $WIN_ID (closed?)" >&2
  exit 1
fi
