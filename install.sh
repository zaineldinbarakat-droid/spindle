#!/bin/bash
# Builds Spindle and installs it in /Applications, then opens it.
# Its self-updates replace the copy installed here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.sh" release

osascript -e 'tell application id "com.spindle.notch" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x Spindle 2>/dev/null || true

rm -rf "/Applications/Spindle.app"
/usr/bin/ditto "$ROOT/build/Spindle.app" "/Applications/Spindle.app"
# Otherwise Spotlight finds two Spindles: this one and the build copy.
rm -rf "$ROOT/build/Spindle.app"
echo "Installed /Applications/Spindle.app"
open "/Applications/Spindle.app"
