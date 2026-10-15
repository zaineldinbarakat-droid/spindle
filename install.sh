#!/bin/bash
# Builds Spindle and Sleeve and installs them in /Applications, then opens them.
#
# Sleeve needs to live in /Applications on macOS 27: MenuBarAgent only keeps an app's
# own icon on screen under a native hiding restriction when the app is installed
# there — run from anywhere else, Sleeve's icon vanished whenever apps were hidden.
# Both apps' self-updates replace the copies installed here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.sh" release

for app in Spindle Sleeve; do
    osascript -e "tell application id \"com.spindle.$( [ $app = Spindle ] && echo notch || echo sleeve )\" to quit" >/dev/null 2>&1 || true
done
sleep 1
pkill -x Spindle 2>/dev/null || true
pkill -x Sleeve 2>/dev/null || true

for app in Spindle Sleeve; do
    rm -rf "/Applications/$app.app"
    /usr/bin/ditto "$ROOT/build/$app.app" "/Applications/$app.app"
    echo "Installed /Applications/$app.app"
done

open "/Applications/Spindle.app" "/Applications/Sleeve.app"
