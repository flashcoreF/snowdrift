#!/bin/bash
# Builds Snowdrift.app from source.
#   bash build.sh           build and open the app
#   bash build.sh install   build, copy into /Applications, and open it
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Apple's developer tools aren't installed yet."
  echo "Run this, click Install in the window that appears, then run build.sh again:"
  echo "    xcode-select --install"
  exit 1
fi

echo "❄  Building Snowdrift (the first build takes a minute)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="Snowdrift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Snowdrift" "$APP/Contents/MacOS/Snowdrift"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# Stop a copy that is already running, so the new one takes over.
pkill -x Snowdrift >/dev/null 2>&1 || true

if [[ "${1:-}" == "install" ]]; then
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  echo "✅ Installed to /Applications/$APP"
  open "/Applications/$APP"
else
  echo "✅ Built $(pwd)/$APP"
  open "$APP"
fi
echo "Look for the ❄ snowflake in your menu bar."
