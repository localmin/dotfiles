#!/usr/bin/env bash
# list-windows.sh — list the currently open Chrome windows
# Output: number|tab count|active tab title
# Limitation: macOS + Google Chrome only (depends on osascript)

set -euo pipefail

osascript -e 'tell application "Google Chrome"
  set outStr to ""
  repeat with i from 1 to count of windows
    try
      set w to window i
      set outStr to outStr & i & "|" & (count of tabs of w) & "|" & (title of active tab of w) & linefeed
    end try
  end repeat
  return outStr
end tell'
