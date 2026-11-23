#!/bin/bash
# Archives the Mac App Store build ("Hush App Store" scheme, AppStore configuration: no direct
# paste, no update check) and exports a signed package for App Store Connect.
#
#   TEAM_ID=ABCDE12345 scripts/appstore.sh             # → dist/appstore/Hush.pkg
#   TEAM_ID=ABCDE12345 UPLOAD=1 scripts/appstore.sh    # export and upload
#
# Needs an Apple Developer Program membership, Xcode signed in to that account (Settings ›
# Accounts), and the app record created in App Store Connect with the same bundle ID.
# Signing is automatic (-allowProvisioningUpdates). See docs/APPSTORE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?set TEAM_ID to your 10-character Apple Developer Team ID}"
BUNDLE_ID=${BUNDLE_ID:-fyi.hushpass.Hush}
VERSION=$(awk '/^    MARKETING_VERSION:/ {print $2; exit}' App/project.yml)
BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}
OUT=dist/appstore
ARCHIVE="$OUT/Hush.xcarchive"

echo "==> Hush $VERSION ($BUILD_NUMBER) for the Mac App Store · $BUNDLE_ID"
rm -rf "$OUT"
mkdir -p "$OUT"
swift test --package-path Core
(cd App && xcodegen generate)

xcodebuild -project App/Hush.xcodeproj -scheme "Hush App Store" -configuration AppStore \
    -archivePath "$ARCHIVE" -destination "generic/platform=macOS" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    archive

# The App Store build must not contain the Accessibility paste path.
BIN="$ARCHIVE/Products/Applications/Hush.app/Contents/MacOS/Hush"
if nm -u "$BIN" | grep -qE "AXIsProcessTrusted|CGEventPost"; then
    echo "error: the App Store build still references Accessibility / CGEventPost" >&2
    exit 1
fi

DESTINATION=export
[[ "${UPLOAD:-0}" == 1 ]] && DESTINATION=upload
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates

if [[ "$DESTINATION" == upload ]]; then
    echo "==> Uploaded. It appears in App Store Connect › TestFlight after processing."
else
    echo "==> Exported to $OUT. Upload Hush.pkg with the Transporter app, or rerun with UPLOAD=1."
fi
