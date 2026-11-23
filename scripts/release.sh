#!/bin/bash
# Builds a Hush release: a universal Hush.app and a universal `hush` CLI, zipped into dist/.
#
# Without signing credentials it produces ad-hoc signed builds for local testing.
# With them it signs with Developer ID, notarizes and staples:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID="TEAMID"
#   # notarization, either a keychain profile (local) ...
#   NOTARY_PROFILE="hush-notary"          # created with: xcrun notarytool store-credentials
#   # ... or an App Store Connect API key (CI)
#   NOTARY_KEY_PATH=/path/AuthKey.p8 NOTARY_KEY_ID=... NOTARY_ISSUER=...
#
# Usage: scripts/release.sh [version]     (default: MARKETING_VERSION from App/project.yml)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
VERSION=${1:-$(awk '/MARKETING_VERSION:/ {print $2; exit}' App/project.yml)}
VERSION=${VERSION#v}
DIST=$ROOT/dist
BUILD=$ROOT/.build/release-app
APP=$BUILD/Build/Products/Release/Hush.app

SIGNED=0
if [[ -n "${DEVELOPER_ID:-}" && -n "${TEAM_ID:-}" ]]; then SIGNED=1; fi

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

notarize() { # notarize <zip>
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
        xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
    else
        echo "error: DEVELOPER_ID is set but no notarization credentials (NOTARY_PROFILE or NOTARY_KEY_PATH)" >&2
        exit 1
    fi
}

rm -rf "$DIST"
mkdir -p "$DIST"

log "Hush $VERSION ($([[ $SIGNED == 1 ]] && echo "Developer ID" || echo "ad-hoc, not for distribution"))"

log "Testing HushCore"
swift test --package-path Core

log "Building Hush.app (universal)"
(cd App && xcodegen generate)
SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
if [[ $SIGNED == 1 ]]; then
    SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp)
fi
xcodebuild -project App/Hush.xcodeproj -scheme Hush -configuration Release \
    -derivedDataPath "$BUILD" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" "${SIGN_ARGS[@]}" \
    clean build | grep -E "error:|warning: |BUILD" || true
[[ -d "$APP" ]] || { echo "error: app build failed" >&2; exit 1; }

log "Building hush CLI (universal)"
swift build -c release --product hush --arch arm64 --arch x86_64
CLI=$(swift build -c release --product hush --arch arm64 --arch x86_64 --show-bin-path)/hush
cp "$CLI" "$DIST/hush"
if [[ $SIGNED == 1 ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$DIST/hush"
else
    codesign --force --sign - "$DIST/hush"
fi

APP_ZIP="$DIST/Hush-$VERSION.zip"
CLI_ZIP="$DIST/hush-cli-$VERSION.zip"

if [[ $SIGNED == 1 ]]; then
    log "Notarizing Hush.app"
    ditto -c -k --keepParent "$APP" "$DIST/notarize-app.zip"
    notarize "$DIST/notarize-app.zip"
    xcrun stapler staple "$APP"
    rm "$DIST/notarize-app.zip"

    log "Notarizing hush CLI"
    (cd "$DIST" && ditto -c -k hush notarize-cli.zip)
    notarize "$DIST/notarize-cli.zip"   # a bare binary cannot be stapled; Gatekeeper checks online
    rm "$DIST/notarize-cli.zip"
fi

log "Packaging"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
(cd "$DIST" && ditto -c -k hush "$(basename "$CLI_ZIP")" && rm hush)
(cd "$DIST" && shasum -a 256 ./*.zip > SHA256SUMS.txt)

log "Verifying"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "network" && { echo "error: network entitlement found" >&2; exit 1; }
lipo -archs "$APP/Contents/MacOS/Hush"
if [[ $SIGNED == 1 ]]; then spctl --assess --type execute --verbose "$APP"; fi

log "Done"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
