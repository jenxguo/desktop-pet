#!/bin/bash
# Builds build/<Pet name>.app from the current Pet/ folder: a real,
# double-clickable menu bar app you can drag into /Applications, with the
# pet folder copied inside and an icon made from Pet/sprites/portrait.png.
#
#   ./scripts/build-app.sh
#   open "build/Mars.app"
#
# The app is ad-hoc signed, which is enough to run it on the Mac that built
# it. Sharing the .app with other people needs a Developer ID + notarization
# (see README → Sharing your build).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=$(python3 -c "import sys; sys.path.insert(0, 'tools'); import petlib; print(petlib.load_pet('Pet')['name'])")
SLUG=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
BUNDLE_ID="${BUNDLE_ID:-local.desktoppet.${SLUG:-pet}}"
APP="build/$NAME.app"

echo "→ building $NAME ($BUNDLE_ID)"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DesktopPet "$APP/Contents/MacOS/DesktopPet"
rsync -a --exclude '.DS_Store' Pet/ "$APP/Contents/Resources/Pet/"

ICON_KEY=""
if [ -f Pet/sprites/portrait.png ]; then
  python3 tools/make_icon.py "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DesktopPet</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>$NAME tidies screenshots off your Desktop.</string>
  $ICON_KEY
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "✓ $APP"
echo "  open \"$APP\"   — or drag it into /Applications"
