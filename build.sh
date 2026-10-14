#!/bin/bash
# Builds Spindle and assembles a runnable .app bundle.
#
# Requires Xcode (not just the Command Line Tools): SwiftUI's @State and friends are
# macros in the macOS 26+ SDK, and libSwiftUIMacros.dylib ships only with Xcode.
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Spindle"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

if ! xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'MSG'
error: Xcode is required to build Spindle.

  SwiftUI property wrappers are macros in this SDK and the macro plugin
  (libSwiftUIMacros.dylib) is not part of the Command Line Tools.

  1. Install Xcode from the Mac App Store
  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. Re-run ./build.sh
MSG
    exit 1
fi

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/Packaging/AppIcon.icns" ]]; then
    cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Ad-hoc signature. Good enough to launch, but the code directory hash changes on every
# build, so macOS re-asks for Automation permission each time you rebuild. Sign with a
# real Developer ID certificate to make the grant stick across builds.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "warning: ad-hoc signing failed; the app will still run" >&2
}

echo
echo "Built: $APP"
echo "Run:   open \"$APP\""
