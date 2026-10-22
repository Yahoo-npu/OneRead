#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/一读·One Read.app"
VERSION="$(tr -d '\r\n' < VERSION)"
BUILD_NUMBER="${ONEREAD_BUILD_NUMBER:-30}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
SDK="${ONEREAD_SDK:-$(xcrun --show-sdk-path)}"
# This machine may contain a newer SDK than its compiler.
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then SDK="${ONEREAD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"; fi
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -parse-as-library -O -module-cache-path "$PWD/.build/module-cache" Sources/OneRead/*.swift -o "$APP/Contents/MacOS/OneRead"
cp Sources/OneRead/AppIcon.png Sources/OneRead/AppIcon.icns "$APP/Contents/Resources/"
cp Sources/OneRead/Reader.html Sources/OneRead/ReaderScroll.js "$APP/Contents/Resources/"
cp Sources/OneRead/MagazineCatalogSeeds.json "$APP/Contents/Resources/"
cp Sources/OneRead/EconomistCatalogSeed.json "$APP/Contents/Resources/"
cp Sources/OneRead/ExamVocabulary.json "$APP/Contents/Resources/"
cp -R Sources/OneRead/ExamWordListNotices "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OneRead</string>
<key>CFBundleIdentifier</key><string>com.oneread.reader</string>
<key>CFBundleName</key><string>一读·One Read</string>
<key>CFBundleDisplayName</key><string>一读·One Read</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# Use the same real signing identity across releases when one is available.
# Ad-hoc releases keep reads non-interactive; they cannot inherit old Keychain trust across rebuilds.
codesign --force --sign "${ONEREAD_SIGNING_IDENTITY:--}" "$APP"
echo "Built: $APP"
