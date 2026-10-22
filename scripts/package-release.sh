#!/bin/bash
# Package the application only. This script does not publish or upload anything.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/一读·One Read.app"
VERSION="$(tr -d '\r\n' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
[ -d "$APP" ] || { echo "Run bash scripts/build.sh first." >&2; exit 1; }
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$VERSION" = "$BUILT_VERSION" ] || { echo "Version mismatch; rebuild first." >&2; exit 1; }
for KEY in OneReadDataDirectory OneReadKeychainService; do
    if /usr/libexec/PlistBuddy -c "Print :$KEY" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
        echo "Refusing to package a test app with $KEY override." >&2; exit 1
    fi
done
codesign --verify --deep --strict "$APP"
ARCH="$(lipo -archs "$APP/Contents/MacOS/OneRead")"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported archive architecture: $ARCH" >&2; exit 1 ;;
esac
ARCHIVE="OneRead-v${VERSION}-macos-${ARCH}.zip"
TEMP_ARCHIVE="$PWD/dist/.package-$$.zip"
trap 'rm -f "$TEMP_ARCHIVE"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP" "$TEMP_ARCHIVE"
unzip -tq "$TEMP_ARCHIVE"
mv "$TEMP_ARCHIVE" "$PWD/dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
printf 'Release archive: dist/%s\nChecksum: dist/SHA256SUMS.txt\n' "$ARCHIVE"
