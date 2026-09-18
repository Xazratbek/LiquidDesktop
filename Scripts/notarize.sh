#!/bin/bash
# Submits a Developer ID-signed DMG to Apple's notary service and staples the
# ticket so Gatekeeper opens it without warnings, even offline.
#
# One-time setup (needs an Apple Developer account):
#   xcrun notarytool store-credentials liquiddesktop \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
set -euo pipefail

DMG="$1"
PROFILE="${NOTARY_PROFILE:-liquiddesktop}"

if ! codesign -dv --verbose=2 "$DMG" 2>&1 | grep -q "Developer ID"; then
    echo "error: $DMG is not Developer ID signed."
    echo "Build with: make notarize CODESIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\""
    exit 1
fi

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Notarized $DMG"
