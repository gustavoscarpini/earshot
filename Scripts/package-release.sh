#!/bin/bash
#
# Builds Earshot.app for a GitHub release and zips it.
#
# Two modes:
# - With TEAM_ID: signed with that team's "Developer ID Application"
#   certificate, notarized and stapled, so it opens without Gatekeeper warnings.
# - Without TEAM_ID: ad-hoc signed and not notarized; users approve it once in
#   System Settings › Privacy & Security (see README › Download).
#
# Used by .github/workflows/release.yml and by `make dist`.
#
# Environment:
#   VERSION            Marketing version, e.g. 0.1.0 (required).
#   TEAM_ID            Apple Developer team ID; empty for an ad-hoc build.
#   BUILD_NUMBER       Bundle version (default: 1).
#   Notarization, one of:
#     NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                      App Store Connect API key (.p8 file, key ID, issuer ID).
#     NOTARY_PROFILE   A keychain profile saved with
#                      `xcrun notarytool store-credentials`.
#   SKIP_NOTARIZE=1    Developer ID mode: sign only, for a quick local check.
#
# Output: build/release/Earshot-<VERSION>.zip and its .sha256 file.

set -euo pipefail

: "${VERSION:?set VERSION, e.g. 0.1.0}"
TEAM_ID="${TEAM_ID:-}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/release"
APP="$OUT/Build/Products/Release/Earshot.app"
ZIP="$OUT/Earshot-$VERSION.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

if [[ -n "$TEAM_ID" ]]; then
    MODE="Developer ID ($TEAM_ID)"
    SIGNING=(
        DEVELOPMENT_TEAM="$TEAM_ID"
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="Developer ID Application"
        PROVISIONING_PROFILE_SPECIFIER=
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
else
    MODE="ad-hoc, not notarized"
    SIGNING=(
        DEVELOPMENT_TEAM=
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY=-
    )
fi

echo "==> Building Earshot $VERSION ($BUILD_NUMBER), $MODE"
# Command-line settings override Config/Signing.xcconfig and Local.xcconfig.
xcodebuild \
    -project "$ROOT/Earshot.xcodeproj" \
    -scheme Earshot \
    -configuration Release \
    -derivedDataPath "$OUT" \
    "${SIGNING[@]}" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build

echo "==> Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -z "$TEAM_ID" ]]; then
    echo "==> Ad-hoc build: skipping notarization"
else
    SIGNED_TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [[ "$SIGNED_TEAM" != "$TEAM_ID" ]]; then
        echo "error: app is signed by team '$SIGNED_TEAM', expected '$TEAM_ID'" >&2
        exit 1
    fi
    if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
        echo "==> Skipping notarization (SKIP_NOTARIZE=1)"
    else
        echo "==> Notarizing"
        SUBMISSION="$OUT/Earshot-notarize.zip"
        ditto -c -k --keepParent "$APP" "$SUBMISSION"
        if [[ -n "${NOTARY_PROFILE:-}" ]]; then
            xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
        else
            : "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID, or NOTARY_PROFILE}"
            : "${NOTARY_KEY_ID:?set NOTARY_KEY_ID}"
            : "${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID}"
            xcrun notarytool submit "$SUBMISSION" \
                --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
                --wait
        fi
        rm -f "$SUBMISSION"

        echo "==> Stapling"
        xcrun stapler staple "$APP"
        spctl --assess --type execute --verbose=2 "$APP"
    fi
fi

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "$ZIP"
