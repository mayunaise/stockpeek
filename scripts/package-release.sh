#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
app='build/StockPeek.app'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p dist
staging=$(mktemp -d "${TMPDIR:-/tmp}/stockpeek-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/StockPeek.app"
ln -s /Applications "$staging/Applications"
codesign --verify --deep --strict "$staging/StockPeek.app"
archive="dist/StockPeek-${version}-macOS-arm64.dmg"
hdiutil create -volname StockPeek -srcfolder "$staging" -format UDZO -ov "$archive"
hdiutil verify "$archive"
(cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'Release image: %s\n' "$archive"
