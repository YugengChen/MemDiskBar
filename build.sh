#!/bin/bash
# 编译 MemDiskBar 并安装到 ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MemDiskBar.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -o "$APP/Contents/MacOS/MemDiskBar" main.swift

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MemDiskBar</string>
    <key>CFBundleIdentifier</key><string>local.ychen.MemDiskBar</string>
    <key>CFBundleExecutable</key><string>MemDiskBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

pkill -x MemDiskBar 2>/dev/null || true
rm -rf ~/Applications/MemDiskBar.app
cp -R "$APP" ~/Applications/
open ~/Applications/MemDiskBar.app
echo "已安装并启动：~/Applications/MemDiskBar.app"
