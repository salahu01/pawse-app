#!/bin/bash
# Packages build/Pawse.app into build/Pawse-<version>.dmg with a drag-to-Applications window.
# Run tools/bundle.sh first. If SIGN_IDENTITY is set, the DMG is signed (and notarised with NOTARY_PROFILE).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Pawse.app"
[ -d "$APP" ] || { echo "run tools/bundle.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Pawse-$VERSION.dmg"
STAGE="$ROOT/build/dmg/stage"
RW="$ROOT/build/dmg/rw.dmg"
VOL="Pawse $VERSION"

echo "==> Background"
python3 "$ROOT/tools/make_dmg_bg.py"
tiffutil -cathidpicheck "$ROOT/build/dmg/bg.png" "$ROOT/build/dmg/bg@2x.png" -out "$ROOT/build/dmg/bg.tiff" >/dev/null

echo "==> Staging"
rm -rf "$STAGE" "$RW" "$DMG"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/build/dmg/bg.tiff" "$STAGE/.background/bg.tiff"

echo "==> Laying out the window"
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size 200m "$RW"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$RW"
osascript <<OSA || echo "    (Finder layout skipped: no GUI session)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 562}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:bg.tiff"
    set position of item "Pawse.app" of container window to {170, 230}
    set position of item "Applications" of container window to {490, 230}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
# volume icon
cp "$ROOT/Resources/AppIcon.icns" "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOL" 2>/dev/null || true
sync
hdiutil detach "/Volumes/$VOL" -quiet

echo "==> Compressing"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi
echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
