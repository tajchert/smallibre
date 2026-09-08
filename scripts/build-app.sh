#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="build/Calibre Nova.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/CalibreNova "$app/Contents/MacOS/CalibreNova"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp 'Tests/NovaCoreTests/Fixtures/Small Hours.epub' "$app/Contents/Resources/Small Hours.epub"
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
du -sh "$app"
