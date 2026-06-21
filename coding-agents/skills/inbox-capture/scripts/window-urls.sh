#!/usr/bin/env bash
# window-urls.sh — get the URLs of all tabs in a given Chrome window
# Output: one URL per line
# Args: window number (if omitted, pick via fzf; auto-selected when only one window is open)
# Limitation: macOS + Google Chrome only (depends on osascript)

set -euo pipefail

# Get the window list: "number|tab count|active tab title"
WINDOWS=$(osascript <<'APPLESCRIPT'
tell application "Google Chrome"
  if (count of windows) is 0 then
    error "No Chrome windows are open"
  end if
  set outStr to ""
  repeat with i from 1 to count of windows
    set w to window i
    set tabCount to count of tabs of w
    set activeTitle to title of active tab of w
    set outStr to outStr & i & "|" & tabCount & "|" & activeTitle & linefeed
  end repeat
  return outStr
end tell
APPLESCRIPT)

WIN_COUNT=$(echo "$WINDOWS" | grep -c '|')

# Determine the window number
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
  WIN_INDEX="$1"
elif [ "$WIN_COUNT" -eq 1 ]; then
  WIN_INDEX=1
else
  DISPLAY_LINES=$(echo "$WINDOWS" | awk -F'|' '{
    printf "[%s]  %s tabs  —  %s\n", $1, $2, $3
  }')
  SELECTED=$(echo "$DISPLAY_LINES" | fzf --prompt="Chrome window> " --height=~40% --no-sort < /dev/tty 2>/dev/tty)
  WIN_INDEX=$(echo "$SELECTED" | grep -o '^\[[0-9]*\]' | tr -d '[]')
fi

# Output the URLs of all tabs in the chosen window
osascript <<APPLESCRIPT
tell application "Google Chrome"
  set urlList to ""
  repeat with t in (tabs of window $WIN_INDEX)
    set urlList to urlList & (URL of t) & linefeed
  end repeat
  return urlList
end tell
APPLESCRIPT
