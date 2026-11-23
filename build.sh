#!/bin/zsh
# Builds Mac Hue Control, signs it, installs it in /Applications and launches it.
# Usage: ./build.sh            (build + install + launch)
#        ./build.sh --no-run   (build + install only)
set -euo pipefail
cd "$(dirname "$0")"

# Preflight: stop early with a plain message instead of a cryptic compiler error.
stop() { echo "\nCannot continue: $1\n" >&2; exit 1 }
[[ "$(uname -m)" == "arm64" ]] || stop "Mac Hue Control needs a Mac with Apple Silicon (M1 or newer)."
(( $(sw_vers -productVersion | cut -d. -f1) >= 15 )) || stop "Mac Hue Control needs macOS 15 (Sequoia) or newer.
  Update macOS in System Settings > General > Software Update, then run ./build.sh again."
xcodebuild -version >/dev/null 2>&1 || stop "Xcode is not ready.
  1. Install Xcode from the App Store (it's free; the download is large).
  2. Open Xcode once and accept the licence.
  3. Run ./build.sh again.
  If Xcode is already installed, run this in Terminal, then try again:
     sudo xcode-select -s /Applications/Xcode.app"

APP_NAME="Mac Hue Control"
DEST="/Applications/$APP_NAME.app"
# Assemble outside the Desktop/iCloud folders: they add hidden markings that break code signing.
BUILD_DIR="${TMPDIR:-/tmp}/mac-hue-control-build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "Running tests..."
# A broken build must never be installed over a working one.
if ! swift test > "${TMPDIR:-/tmp}/mac-hue-control-tests.log" 2>&1; then
  tail -30 "${TMPDIR:-/tmp}/mac-hue-control-tests.log"
  stop "some tests failed (shown above), so nothing was installed."
fi
tail -1 "${TMPDIR:-/tmp}/mac-hue-control-tests.log"

echo "Building..."
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacHueControl"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacHueControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Stamp the SDK that really built the app. SwiftPM stamps the minimum (15.0) instead, and macOS then gives the
# menu bar panel the older, nearly solid look. Must happen before signing, because it changes the file.
SDK_VERSION="$(xcrun --show-sdk-version)"
if vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace -output "$BUILD_DIR/stamped" "$APP/Contents/MacOS/MacHueControl" 2>/dev/null; then
  mv "$BUILD_DIR/stamped" "$APP/Contents/MacOS/MacHueControl"
else
  echo "NOTE: could not stamp the SDK version; the menu bar panel may look older than other menus."
fi

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
