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

# Sleeve first, so its hiding is lifted before anything else changes.
for app in Sleeve Spindle; do
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

# Spindle first: an icon added while Sleeve is hiding apps lands among Apple's
# icons, far from the rest.
open "/Applications/Spindle.app"
sleep 2
open "/Applications/Sleeve.app"
