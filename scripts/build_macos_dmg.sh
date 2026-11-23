#!/usr/bin/env bash
# Gene - Oct, 07, 2026: Enhanced macOS packaging script to sign binaries with Developer ID Application, enable Hardened Runtime, sign DMG, and automate Apple Notarization & stapling
# Previous implementation:
# #!/usr/bin/env bash
# # Build a release .app and package it into a drag-to-/Applications DMG.
# #
# # Usage: scripts/build_macos_dmg.sh
# # Output: build/macos/Files Utility-<version>.dmg
# #
# # NOTE: the app is currently UNSIGNED (no Developer ID certificate).
# # Gatekeeper will quarantine the app on other Macs: users must right-click >
# # Open the first time, or clear quarantine with
# #   xattr -dr com.apple.quarantine "/Applications/Files Utility.app"
# # Signing status is documented in the local release notes.
# 
# set -euo pipefail
# 
# cd "$(dirname "$0")/.."
# 
# APP_NAME="Files Utility"
# VERSION="$(sed -n 's/^version: *"\{0,1\}\([0-9][^+"]*\).*/\1/p' pubspec.yaml)"
# if [[ -z "$VERSION" ]]; then
#   echo "error: could not read version from pubspec.yaml" >&2
#   exit 1
# fi
# 
# echo "Building $APP_NAME $VERSION (macOS release)..."
# flutter build macos --release
# 
# APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
# if [[ ! -d "$APP_PATH" ]]; then
#   echo "error: $APP_PATH not found after build" >&2
#   exit 1
# fi
# 
# DMG_DIR="build/macos"
# DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.dmg"
# STAGING="$(mktemp -d)"
# trap 'rm -rf "$STAGING"' EXIT
# 
# cp -R "$APP_PATH" "$STAGING/"
# ln -s /Applications "$STAGING/Applications"
# 
# rm -f "$DMG_PATH"
# hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
# 
# echo "Created $DMG_PATH"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="Files Utility"
VERSION="$(sed -n 's/^version: *"\{0,1\}\([0-9][^+"]*\).*/\1/p' pubspec.yaml)"
if [[ -z "$VERSION" ]]; then
  echo "error: could not read version from pubspec.yaml" >&2
  exit 1
fi

echo "Building $APP_NAME $VERSION (macOS release)..."
flutter build macos --release

APP_PATH="${REPO_ROOT}/build/macos/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found after build" >&2
  exit 1
fi

# Gene - Nov, 23, 2026: Removed hardcoded personal signing identity, Apple ID, Team ID, and Keychain profile; read via environment/Keychain instead.
SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"
if [ -z "${SIGNING_IDENTITY}" ]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application:' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
fi
ENTITLEMENTS="${REPO_ROOT}/macos/Runner/Release.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-files-utility-notary}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

# Check if signing identity is available in Keychain
if [ -n "${SIGNING_IDENTITY}" ] && security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
  echo "==> Code signing nested frameworks with Hardened Runtime using '${SIGNING_IDENTITY}'..."
  if [ -d "${APP_PATH}/Contents/Frameworks" ]; then
    find "${APP_PATH}/Contents/Frameworks" -depth \
      \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) \
      -print0 |
      while IFS= read -r -d '' nested; do
        echo "    Signing ${nested}..."
        codesign --force --verbose --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${nested}"
      done
  fi

  echo "==> Code signing main application bundle..."
  codesign --force --verbose --options runtime --timestamp --entitlements "${ENTITLEMENTS}" --sign "${SIGNING_IDENTITY}" "${APP_PATH}"

  echo "==> Verifying signature integrity..."
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
else
  echo "==> Note: Developer ID signing identity not configured or not found in keychain. Skipping Developer ID signing for .app bundle."
  echo "    (Set MACOS_SIGNING_IDENTITY or install a Developer ID Application certificate in your Keychain.)"
fi

DMG_DIR="${REPO_ROOT}/build/macos"
DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.dmg"
mkdir -p "$DMG_DIR"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
echo "==> Creating DMG at $DMG_PATH..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

if [ -n "${SIGNING_IDENTITY}" ] && security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
  echo "==> Code signing DMG..."
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "$DMG_PATH"

  # Check if direct credentials or notarytool profile is available for automated notarization
  if [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_ID}" ] && [ -n "${APPLE_TEAM_ID}" ]; then
    echo "==> Submitting DMG to Apple Notary Service using environment credentials..."
    xcrun notarytool submit "$DMG_PATH" --apple-id "${APPLE_ID}" --password "${APPLE_APP_SPECIFIC_PASSWORD}" --team-id "${APPLE_TEAM_ID}" --wait
    echo "==> Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    if [ -d "$APP_PATH" ]; then
      xcrun stapler staple "$APP_PATH"
    fi
    echo "==> Successfully notarized and stapled!"
  elif xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "==> Submitting DMG to Apple Notary Service using keychain profile '${NOTARY_PROFILE}'..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "${NOTARY_PROFILE}" --wait
    echo "==> Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    if [ -d "$APP_PATH" ]; then
      xcrun stapler staple "$APP_PATH"
    fi
    echo "==> Successfully notarized and stapled!"
  else
    echo ""
    echo "==> NOTE: Apple Notary credentials not configured."
    echo "    For automated CI/CD, set MACOS_SIGNING_IDENTITY, APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, and APPLE_TEAM_ID."
    echo "    Or for local builds, store credentials in your Keychain once by running:"
    echo "    xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id \"<your-apple-id>\" --team-id \"<your-team-id>\" --password \"<your-app-specific-password>\""
    echo ""
  fi
fi

echo "==> Successfully created $DMG_PATH"
