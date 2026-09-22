#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
destination="${1:-$project_dir/dist}"
app_dir="$destination/Codex Accounts.app"
cd "$project_dir"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/CodexAccounts "$app_dir/Contents/MacOS/CodexAccounts"
swift tools/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Codex Accounts</string>
<key>CFBundleDisplayName</key><string>Codex 账号管理器</string>
<key>CFBundleIdentifier</key><string>local.codex.accounts</string>
<key>CFBundleExecutable</key><string>CodexAccounts</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Local personal account manager. Not affiliated with OpenAI.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf '%s\n' "$app_dir"
