#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app='build/StockPeek.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/module-cache
if [ ! -f Assets/AppIcon.icns ] || [ Assets/AppIcon.png -nt Assets/AppIcon.icns ] || [ scripts/build-icon.sh -nt Assets/AppIcon.icns ] || [ scripts/render-icon.swift -nt Assets/AppIcon.icns ]; then
  bash scripts/build-icon.sh
fi
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
swiftc -O -target arm64-apple-macosx26.0 -module-cache-path .build/module-cache \
  Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Sources/Views.swift Sources/App.swift \
  -o "$app/Contents/MacOS/StockPeek"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>StockPeek</string>
<key>CFBundleDisplayName</key><string>StockPeek</string>
<key>CFBundleExecutable</key><string>StockPeek</string>
<key>CFBundleIdentifier</key><string>com.wayne.notchstocks.demo</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"
