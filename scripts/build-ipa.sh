#!/bin/bash
# Builds an IPA for AltStore: a Release build for real devices, ad-hoc signed only so that the entitlements
# are embedded (AltStore re-signs the app with each user's own Apple ID).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
OUT=build/ipa
rm -rf "$OUT"
xcodebuild -project CompanionReader.xcodeproj -scheme CompanionReader -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$OUT" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build | tail -3

APP="$OUT/Build/Products/Release-iphoneos/CompanionReader.app"
codesign --force --sign - --entitlements CompanionWidgets/CompanionWidgets.entitlements "$APP/PlugIns/CompanionWidgets.appex"
codesign --force --sign - --entitlements CompanionReader/CompanionReader.entitlements "$APP"

rm -rf build/Payload build/BookOrb.ipa
mkdir build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry BookOrb.ipa Payload)
rm -rf build/Payload

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist")
echo "Built build/BookOrb.ipa  version $VERSION ($BUILD)  $(stat -f%z build/BookOrb.ipa) bytes"
