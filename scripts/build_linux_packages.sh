#!/usr/bin/env bash
set -euo pipefail

# Builds the Linux release bundle and packages it twice:
#   dist/files_utility-<version>-linux-x64.tar.gz  (portable bundle)
#   dist/files-utility_<version>_amd64.deb         (installs to /usr/lib/files_utility,
#                                                   with launcher entry and icons)
#
# Version is read from pubspec.yaml. Build deps on Ubuntu:
#   sudo apt-get install ninja-build libgtk-3-dev
# Runtime deps are declared in the .deb control file.
#
# Pass --skip-build to package an existing build/linux/x64/release/bundle.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# The executable and install directory use the pubspec name (BINARY_NAME in
# linux/CMakeLists.txt). The Debian package name must not contain underscores,
# so it is spelled with a hyphen instead.
BINARY_NAME="files_utility"
DEB_PKG="files-utility"
APP_ID="dev.genexis.filesutility"

VERSION="$(sed -n 's/^version: *"\{0,1\}\([0-9][^+"]*\).*/\1/p' pubspec.yaml)"
if [[ -z "$VERSION" ]]; then
  echo "Error: could not read version from pubspec.yaml" >&2
  exit 1
fi

if [ "${1:-}" != "--skip-build" ]; then
  echo "==> Building Flutter Linux release bundle ($BINARY_NAME $VERSION)..."
  flutter build linux --release
fi

BUNDLE="build/linux/x64/release/bundle"
if [ ! -d "$BUNDLE" ]; then
  echo "Error: $BUNDLE not found!" >&2
  exit 1
fi

DIST_DIR="dist"
mkdir -p "$DIST_DIR"

# --- tar.gz -------------------------------------------------------------------
TARBALL="$DIST_DIR/$BINARY_NAME-$VERSION-linux-x64.tar.gz"
echo "==> Creating $TARBALL..."
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$BUNDLE" .

# --- .deb ---------------------------------------------------------------------
DEB_NAME="${DEB_PKG}_${VERSION}_amd64"
DEB_ROOT="$(mktemp -d)/$DEB_NAME"
echo "==> Staging $DEB_NAME.deb..."

install -d "$DEB_ROOT/DEBIAN" \
           "$DEB_ROOT/usr/lib/$BINARY_NAME" \
           "$DEB_ROOT/usr/bin" \
           "$DEB_ROOT/usr/share/applications"
cp -r "$BUNDLE"/. "$DEB_ROOT/usr/lib/$BINARY_NAME/"
ln -s "../lib/$BINARY_NAME/$BINARY_NAME" "$DEB_ROOT/usr/bin/$BINARY_NAME"

install -m 644 "linux/packaging/$APP_ID.desktop" "$DEB_ROOT/usr/share/applications/"
for size in 128 256 512; do
  install -d "$DEB_ROOT/usr/share/icons/hicolor/${size}x${size}/apps"
  install -m 644 "linux/packaging/icons/app_icon_$size.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/${size}x${size}/apps/$APP_ID.png"
done

INSTALLED_SIZE="$(du -sk "$DEB_ROOT/usr" | cut -f1)"
# libsqlite3-0 is required because sqflite_common_ffi loads the system SQLite on
# Linux - unlike Windows, where the sqlite3 DLL ships inside the bundle.
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: $DEB_PKG
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_SIZE
Depends: libgtk-3-0 (>= 3.24), libsqlite3-0
Maintainer: genexis.dev <bluegene37@gmail.com>
Homepage: https://github.com/bluegene37/files_utility
Description: File transfer and cleanup utility for network shares and NAS
 Files Utility moves, copies, counts, and cleans up files across network
 shares, SMB mounts, local drives, and NAS storage, with progress tracking
 and a searchable history of past operations.
EOF

DEB_PATH="$DIST_DIR/$DEB_NAME.deb"
rm -f "$DEB_PATH"
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB_PATH"
rm -rf "$(dirname "$DEB_ROOT")"

echo "==> Done:"
ls -lh "$TARBALL" "$DEB_PATH"
