#!/bin/bash
# Builds ODM.app from source.
#   ./build.sh            -> build/ODM.app
#   ./build.sh --install  -> also installs it to /Applications and opens it
#
# The .app is assembled and signed on the internal disk (in a temp folder), because
# external drives formatted as exFAT/FAT add hidden "._" files that make codesign fail.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift not found. Install Apple's Command Line Tools first:"
  echo "    xcode-select --install"
  exit 1
fi

echo "==> Compiling (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/odm.XXXXXX")"
APP="$STAGE/ODM.app"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Creating ODM.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ODM" "$APP/Contents/MacOS/ODM"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R ChromeExtension "$APP/Contents/Resources/ChromeExtension"

echo "==> Making app icon"
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Remove AppleDouble (._*) files and extended attributes copied from the external drive
find "$APP" -name '._*' -delete
xattr -cr "$APP"

echo "==> Signing (ad-hoc, for this Mac)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x ODM 2>/dev/null || true
  # Earlier builds were called TurboDM; remove that copy so two apps don't share the browser bridge port.
  if [[ -d /Applications/TurboDM.app ]]; then
    echo "    removing the old TurboDM.app (renamed to ODM)"
    pkill -x TurboDM 2>/dev/null || true
    rm -rf /Applications/TurboDM.app
  fi
  sleep 1
  rm -rf /Applications/ODM.app
  ditto --norsrc --noextattr "$APP" /Applications/ODM.app
  open /Applications/ODM.app
  echo ""
  echo "Installed and launched: /Applications/ODM.app"
else
  rm -rf build/ODM.app
  mkdir -p build
  ditto --norsrc --noextattr "$APP" build/ODM.app
  echo ""
  echo "Done: $(pwd)/build/ODM.app"
  echo "(Run ./build.sh --install to put it in /Applications.)"
fi
