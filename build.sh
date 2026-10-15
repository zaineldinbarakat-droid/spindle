#!/bin/bash
# Builds Spindle and Sleeve and assembles runnable .app bundles.
#
# Requires Xcode (not just the Command Line Tools): SwiftUI's @State and friends are
# macros in the macOS 26+ SDK, and libSwiftUIMacros.dylib ships only with Xcode.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"

if ! xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'MSG'
error: Xcode is required to build Spindle and Sleeve.

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
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

# assemble NAME PLIST — copies the binary into NAME.app and signs it.
assemble() {
    local name="$1" plist="$2"
    local app="$BUILD_DIR/$name.app"
    local bin="$BIN_DIR/$name"
    if [[ ! -x "$bin" ]]; then
        echo "error: built binary not found at $bin" >&2
        exit 1
    fi

    echo "==> Assembling $name.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin" "$app/Contents/MacOS/$name"
    cp "$plist" "$app/Contents/Info.plist"
    printf 'APPL????' > "$app/Contents/PkgInfo"

    if [[ -f "$ROOT/Packaging/$name.icns" ]]; then
        cp "$ROOT/Packaging/$name.icns" "$app/Contents/Resources/AppIcon.icns"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist" 2>/dev/null || true
    fi

    # Ad-hoc signature. Good enough to launch, but the code directory hash changes on
    # every build, so macOS re-asks for Automation (Spindle) and Accessibility (Sleeve)
    # each time you rebuild. A real Developer ID certificate makes grants stick.
    codesign --force --sign - --timestamp=none "$app" >/dev/null 2>&1 || {
        echo "warning: ad-hoc signing failed for $name; the app will still run" >&2
    }
    echo "Built: $app"
}

assemble Spindle "$ROOT/Packaging/Info.plist"
assemble Sleeve "$ROOT/Packaging/Sleeve-Info.plist"

echo
echo "Run:   open \"$BUILD_DIR/Spindle.app\" \"$BUILD_DIR/Sleeve.app\""
