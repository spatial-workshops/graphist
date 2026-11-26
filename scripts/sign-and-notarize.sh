#!/usr/bin/env bash
# Signs build/Graphist.app with your Developer ID certificate (hardened runtime),
# notarizes it with Apple, staples the ticket and produces a distributable zip.
#
# One-time setup: see docs/SIGNING.md.
#
# Required:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
# Optional:
#   NOTARY_PROFILE=graphist-notary   keychain profile created with `xcrun notarytool store-credentials`
#
# Usage:
#   scripts/sign-and-notarize.sh              # sign + notarize + staple + zip
#   scripts/sign-and-notarize.sh --sign-only  # just sign (e.g. to test on another Mac you own)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Graphist.app"
ENTITLEMENTS="$ROOT/Packaging/Graphist.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-graphist-notary}"
: "${DEVELOPER_ID:?Set DEVELOPER_ID, e.g. DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\" (list identities with: security find-identity -v -p codesigning)}"

SIGN_ONLY=0
[[ "${1:-}" == "--sign-only" ]] && SIGN_ONLY=1

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found. Run scripts/build-app.sh (or make app) first." >&2
  exit 1
fi

echo "==> Signing with: $DEVELOPER_ID"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID" \
  "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$SIGN_ONLY" == "1" ]]; then
  echo "==> Signed (not notarized): $APP"
  exit 0
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
UPLOAD_ZIP="$ROOT/build/Graphist-notarize.zip"
DIST_ZIP="$ROOT/build/Graphist-$VERSION.zip"

echo "==> Submitting to Apple notary service (profile: $NOTARY_PROFILE)"
rm -f "$UPLOAD_ZIP"
ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"
OUTPUT="$(xcrun notarytool submit "$UPLOAD_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
echo "$OUTPUT"
rm -f "$UPLOAD_ZIP"
if ! grep -q "status: Accepted" <<<"$OUTPUT"; then
  echo "error: notarization failed. Inspect the log with:" >&2
  echo "       xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE" >&2
  exit 1
fi

echo "==> Stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

echo "==> Creating $DIST_ZIP"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"
echo "==> Done. Distribute $DIST_ZIP"
