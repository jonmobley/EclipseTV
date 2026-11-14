#!/bin/bash
#
# upload_testflight.sh
#
# Signs an Eclipse .xcarchive (iPhone/iPad or Apple TV, picked from the archive) for the
# App Store and uploads it to TestFlight
# without Xcode's Apple sign-in (which lapses every few hours and broke uploads with
# "Failed to Use Accounts").
#
#   Scripts/upload_testflight.sh <path/to/archive.xcarchive> [--validate-only]
#
# Signing: the "Apple Distribution: Jonathan Mobley (2YBTPD32DW)" certificate in this
# Mac's login keychain (cert 9W52VA48F9, expires 2027-11-14) plus the App Store profiles
# "Eclipse iPhone App Store (Mac CLI)" and "Eclipse Apple TV App Store (Mac CLI)" (UUIDs
# below, same expiry). Backup of the cert and
# its key: vault Moxie, APPLE_DISTRIBUTION_2YBTPD32DW_P12_B64 / _P12_PASSWORD.
# Upload: the App Store Connect key "Moxie Builder" from vault Moxie (never printed).
#
# Archive as usual first (xcodebuild archive … -allowProvisioningUpdates); the archive
# step signs for development only and still works without the Apple sign-in.

set -euo pipefail

ARCHIVE="${1:?usage: upload_testflight.sh <archive> [--validate-only]}"
MODE="${2:-}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$ARCHIVE/Info.plist")"
case "$BUNDLE_ID" in
    com.mobleypro.eclipse.EclipseiPhone) PROFILE_UUID="71a1beaf-5878-4b6a-b58f-f53061a6454c"; PLATFORM=ios ;;
    com.mobleypro.eclipse.EclipseTV)     PROFILE_UUID="187cf52c-4be0-46a1-8c7e-6854b04f718c"; PLATFORM=appletvos ;;
    *) echo "error: no App Store profile set up for $BUNDLE_ID" >&2; exit 1 ;;
esac
echo "App: $BUNDLE_ID ($PLATFORM)"
MOP="$HOME/.moxie/bin/mop"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

if [ ! -f "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$PROFILE_UUID.mobileprovision" ] &&
   [ ! -f "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision" ]; then
    echo "error: App Store profile $PROFILE_UUID is not installed on this Mac." >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution: .*(2YBTPD32DW)"; then
    echo "error: no Apple Distribution certificate for team 2YBTPD32DW in the keychain." >&2
    echo "       Restore it from vault Moxie (APPLE_DISTRIBUTION_2YBTPD32DW_P12_B64)." >&2
    exit 1
fi

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>teamID</key><string>2YBTPD32DW</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Apple Distribution</string>
<key>provisioningProfiles</key><dict><key>$BUNDLE_ID</key><string>$PROFILE_UUID</string></dict>
</dict></plist>
EOF

echo "Signing for the App Store…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/export.plist" \
    -exportPath "$WORK/ipa" > "$WORK/export.log" 2>&1 || { grep -E 'error' "$WORK/export.log" >&2; exit 2; }
IPA="$(ls "$WORK"/ipa/*.ipa)"

KEY_ID="$("$MOP" read op://Moxie/secrets/ASC_KEY_ID)"
ISSUER="$("$MOP" read op://Moxie/secrets/ASC_ISSUER_ID)"
(umask 077; "$MOP" read op://Moxie/secrets/ASC_KEY_P8 > "$WORK/AuthKey_$KEY_ID.p8")

ACTION="--upload-app"
[ "$MODE" = "--validate-only" ] && ACTION="--validate-app"
echo "Sending to Apple ($ACTION)…"
xcrun altool "$ACTION" -f "$IPA" -t "$PLATFORM" --api-key "$KEY_ID" --api-issuer "$ISSUER" \
    --p8-file-path "$WORK/AuthKey_$KEY_ID.p8" > "$WORK/altool.log" 2>&1 || true
grep -E 'SUCCEEDED|FAILED|ERROR|error' "$WORK/altool.log" || tail -5 "$WORK/altool.log"
grep -q 'SUCCEEDED' "$WORK/altool.log"
