#!/usr/bin/env bash
# list-windows.sh — 開いているChromeウィンドウの一覧を取得
# 出力: 番号|タブ数|アクティブタブタイトル
# 制限: macOS + Google Chrome 専用(osascript依存)

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
