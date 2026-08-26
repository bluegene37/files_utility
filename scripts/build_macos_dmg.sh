#!/usr/bin/env bash
# Build a release .app and package it into a drag-to-/Applications DMG.
#
# Usage: scripts/build_macos_dmg.sh
# Output: build/macos/Files Utility-<version>.dmg
#
# NOTE: the app is currently UNSIGNED (no Developer ID certificate).
# Gatekeeper will quarantine the app on other Macs: users must right-click >
# Open the first time, or clear quarantine with
#   xattr -dr com.apple.quarantine "/Applications/Files Utility.app"
# See RELEASING.md for signing status.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Files Utility"
VERSION="$(sed -n 's/^version: *"\{0,1\}\([0-9][^+"]*\).*/\1/p' pubspec.yaml)"
if [[ -z "$VERSION" ]]; then
  echo "error: could not read version from pubspec.yaml" >&2
  exit 1
fi

echo "Building $APP_NAME $VERSION (macOS release)..."
flutter build macos --release

APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found after build" >&2
  exit 1
fi

DMG_DIR="build/macos"
DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

echo "Created $DMG_PATH"
