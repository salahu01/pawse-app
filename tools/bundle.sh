#!/bin/bash
# Builds Pawse and assembles build/Pawse.app.
#
#   ./tools/bundle.sh                 # release, universal, ad-hoc signed (this Mac only)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./tools/bundle.sh
#   SIGN_IDENTITY=… NOTARY_PROFILE=pawse ./tools/bundle.sh   # + notarise and staple
#   PAWSE_ARCHS=arm64 ./tools/bundle.sh                       # faster local builds
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Pawse.app"

# Universal by default: macOS 14 still runs on Intel Macs.
ARCHS="${PAWSE_ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> Building ($CONFIG, ${ARCHS// /+})"
cd "$ROOT"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/Pawse"
[ -f "$BIN" ] || { echo "build produced no binary at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pawse"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/Resources/Sounds/"*.wav "$APP/Contents/Resources/"
cp "$ROOT/CREDITS.md" "$ROOT/LICENSE" "$APP/Contents/Resources/"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/Pawse")"

# Gatekeeper only trusts a Developer ID signature with the hardened runtime,
# a secure timestamp, and (for downloads) a stapled notarisation ticket.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing (Developer ID, hardened runtime)"
    codesign --force --deep --options runtime --timestamp \
             --entitlements "$ROOT/Resources/Pawse.entitlements" \
             --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    # One-time: xcrun notarytool store-credentials pawse --apple-id … --team-id … --password <app-specific>
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        ZIP="$ROOT/build/Pawse-notarize.zip"
        echo "==> Notarising (profile: $NOTARY_PROFILE)"
        ditto -c -k --keepParent "$APP" "$ZIP"
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
    fi
else
    echo "==> Signing (ad-hoc — runs here; others must right-click → Open)"
    codesign --force --deep --sign - "$APP"
fi
echo "==> Done: $APP"
