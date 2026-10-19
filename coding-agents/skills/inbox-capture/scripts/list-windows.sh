#!/usr/bin/env bash
# list-windows.sh — list the currently open Chrome windows
# Output: number|window id|tab count|active tab title
#   number is the current z-order index (front to back) and shifts whenever a window
#   is focused; window id is stable for the window's lifetime. Show the number to the
#   user, but pass the id to window-urls.sh.
# Limitation: macOS + Google Chrome only (depends on osascript)

set -euo pipefail

osascript -e 'tell application "Google Chrome"
  set outStr to ""
  repeat with i from 1 to count of windows
    try
      set w to window i
      set outStr to outStr & i & "|" & (id of w) & "|" & (count of tabs of w) & "|" & (title of active tab of w) & linefeed
    end try
  end repeat
  return outStr
end tell'
