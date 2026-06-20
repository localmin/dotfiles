#!/usr/bin/env bash
# window-urls.sh — Chrome の指定ウィンドウから全タブの URL を取得
# 出力: 1行1URL
# 引数: ウィンドウ番号(省略時はfzfで選択、ウィンドウが1つなら自動選択)
# 制限: macOS + Google Chrome 専用(osascript依存)

set -euo pipefail

# ウィンドウ一覧を取得: "番号|タブ数|アクティブタブタイトル"
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

# ウィンドウ番号を決定
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

# 指定ウィンドウの全タブ URL を出力
osascript <<APPLESCRIPT
tell application "Google Chrome"
  set urlList to ""
  repeat with t in (tabs of window $WIN_INDEX)
    set urlList to urlList & (URL of t) & linefeed
  end repeat
  return urlList
end tell
APPLESCRIPT
