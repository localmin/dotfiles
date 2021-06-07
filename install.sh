#!/bin/bash
set -euxo pipefail
# Need to move the appications to APP folder after they star
# https://qiita.com/yukinoi/items/abdaa36a2252c81f312d
curl -OL http://ftp.mozilla.org/pub/thunderbird/releases/78.9.1/mac/ja-JP-mac/Thunderbird%2078.9.1.dmg
curl -OL https://github.com/coralw/xeyes/releases/download/v1.0/xeyes.app.zip
curl -OL https://github.com/keys-pub/app/releases/download/v0.2.3/Keys-0.2.3.dmg
curl -OL https://desktop.linear.app/mac/dmg/arm64
