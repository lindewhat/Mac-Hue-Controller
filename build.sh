#!/bin/zsh
# Builds Mac Hue Control, signs it, installs it in /Applications and launches it.
# Usage: ./build.sh            (build + install + launch)
#        ./build.sh --no-run   (build + install only)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Mac Hue Control"
DEST="/Applications/$APP_NAME.app"
# Assemble outside the Desktop/iCloud folders: they add hidden markings that break code signing.
BUILD_DIR="${TMPDIR:-/tmp}/mac-hue-control-build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "Running tests..."
swift test 2>&1 | tail -3

echo "Building..."
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacHueControl"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacHueControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Signing: a stable identity keeps the Keychain from asking for permission again after every rebuild.
# Override with SIGN_IDENTITY="..." if needed. Prefers Apple Development, then a local cert.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | grep -E 'Apple Development|Developer ID Application|Mac Hue Control Local' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "WARNING: no signing certificate found. Using ad-hoc signing:"
  echo "         macOS will ask for Keychain access again after every rebuild."
  IDENTITY="-"
else
  echo "Signing with: $IDENTITY"
fi
xattr -cr "$APP"  # remove Finder/iCloud markings, which codesign refuses
codesign --force --sign "$IDENTITY" --identifier com.lindewhat.mac-hue-control "$APP"

# Quit a running copy, install, launch.
pkill -x MacHueControl 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto --noextattr --noqtn "$APP" "$DEST"
codesign --verify --strict "$DEST"
echo "Installed and verified: $DEST"
if [[ "${1:-}" != "--no-run" ]]; then
  open "$DEST"
fi
