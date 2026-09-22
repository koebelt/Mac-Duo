#!/usr/bin/env bash
#
# Builds Mac Duo.app from the SwiftPM package.
#
#   ./build.sh            build and sign
#   ./build.sh --run      build, sign, and relaunch the app
#   ./build.sh --install  build, sign, and install into /Applications
#   ./build.sh --universal  build for Apple Silicon and Intel
#
# Signs with the local "Mac Duo Dev" certificate when the keychain holds one,
# and ad-hoc otherwise. Set SIGN_IDENTITY to use your own signing identity.
#
# The identity matters for permissions: macOS ties the Screen Recording grant
# to the designated requirement, and an ad-hoc signature puts the binary's own
# hash in there, so every rebuild asks for the permission again. Signing with a
# certificate pins the requirement to the certificate instead, and the grant
# survives rebuilds. See README.md for creating the local certificate.

set -euo pipefail
cd "$(dirname "$0")"

LOCAL_IDENTITY="Mac Duo Dev"
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -p codesigning | grep -q "\"${LOCAL_IDENTITY}\""; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
  else
    SIGN_IDENTITY=-
  fi
fi
APP_NAME="Mac Duo"
BUNDLE="build/${APP_NAME}.app"
INSTALLED="/Applications/${APP_NAME}.app"

BUILD_ARGS=(-c release)
RUN_APP=false
INSTALL_APP=false
for argument in "$@"; do
  case "$argument" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --run) RUN_APP=true ;;
    --install) INSTALL_APP=true ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

swift build "${BUILD_ARGS[@]}" --product MacDuo
swift build "${BUILD_ARGS[@]}" --product lidprobe

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/MacDuo"
PROBE="$BIN_PATH/lidprobe"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/MacDuo"
# SwiftPM resolves Bundle.module relative to the application bundle.
cp -R "$BIN_PATH/MacDuo_MacDuo.bundle" "$BUNDLE/Contents/Resources/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp LICENSE NOTICE "$BUNDLE/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp "$PROBE" build/lidprobe

TIMESTAMP=--timestamp
if [[ "$SIGN_IDENTITY" == - ]]; then
  TIMESTAMP=--timestamp=none
fi
codesign --force --options runtime "$TIMESTAMP" \
  --sign "$SIGN_IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"

echo "built ${BUNDLE}"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

# The copy that runs. Installing keeps it at one path across rebuilds, which
# keeps the Screen Recording entry in System Settings to one line.
TARGET="$PWD/$BUNDLE"
if "$INSTALL_APP"; then
  pkill -f -x "$INSTALLED/Contents/MacOS/MacDuo" 2>/dev/null || true
  sleep 0.5
  rm -rf "$INSTALLED"
  cp -R "$BUNDLE" "$INSTALLED"
  TARGET="$INSTALLED"
  echo "installed ${INSTALLED}"
fi

if "$RUN_APP"; then
  # Either copy may be running, and two at once would fight over the overlay.
  pkill -f -x "$PWD/$BUNDLE/Contents/MacOS/MacDuo" 2>/dev/null || true
  pkill -f -x "$INSTALLED/Contents/MacOS/MacDuo" 2>/dev/null || true
  sleep 0.5
  open "$TARGET"
  echo "launched"
fi
