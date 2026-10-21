#!/bin/bash
# Publishes an update that Spindle installs itself.
#
#   ./release.sh 0.3.1 "Works with macOS 28: …"
#
# Bumps VERSION, builds Spindle, zips it into updates/, and writes
# updates/latest.json. Commit and push afterwards: the app reads both from the
# repository's main branch (Settings → Updates, or automatically once a day).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION_NUMBER="${1:?usage: ./release.sh <version> \"<what changed>\"}"
NOTES="${2:-}"

echo "$VERSION_NUMBER" > "$ROOT/VERSION"
"$ROOT/build.sh" release

mkdir -p "$ROOT/updates"
for app in Spindle; do
    rm -f "$ROOT/updates/$app.zip"
    # ditto keeps the bundle's signature, symlinks and attributes intact.
    /usr/bin/ditto -c -k --keepParent "$ROOT/build/$app.app" "$ROOT/updates/$app.zip"
    # Only the zip is needed from here; a loose copy would show up in Spotlight.
    rm -rf "$ROOT/build/$app.app"
    echo "Packed updates/$app.zip ($(du -h "$ROOT/updates/$app.zip" | cut -f1))"
done

/usr/bin/python3 - "$ROOT/updates/latest.json" "$VERSION_NUMBER" "$NOTES" <<'PY'
import json, sys
path, version, notes = sys.argv[1:4]
json.dump({"version": version, "notes": notes, "minimumSystemVersion": "14.0"},
          open(path, "w"), indent=2, ensure_ascii=False)
PY
echo "Wrote updates/latest.json for $VERSION_NUMBER. Commit and push to publish."
