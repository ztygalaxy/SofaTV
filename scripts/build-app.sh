#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/sofatv-clang
version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print -u2 "Invalid VERSION: $version"; exit 1; }
python3 scripts/build-cmg-macos.py
python3 scripts/build-h5e-macos.py
swift build -c release --disable-sandbox --cache-path /private/tmp/sofatv-cache
app_bundle="dist/沙发电视.app"
# Recreate generated output so renamed executables and frameworks cannot leave stale files.
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS"
cp .build/release/SofaTV "$app_bundle/Contents/MacOS/SofaTV"
mkdir -p "$app_bundle/Contents/Frameworks"
cp native/cmg/libSofaTVCmg.dylib "$app_bundle/Contents/Frameworks/"
codesign --force --sign - "$app_bundle/Contents/Frameworks/libSofaTVCmg.dylib"
cp native/h5e/libSofaTVH5e.dylib "$app_bundle/Contents/Frameworks/"
codesign --force --sign - "$app_bundle/Contents/Frameworks/libSofaTVH5e.dylib"
swift -module-cache-path /private/tmp/sofatv-clang scripts/build-icon.swift Assets/AppIcon.svg .build/SofaTV.iconset .build/Television.png .build/AppIcon.icns
mkdir -p "$app_bundle/Contents/Resources"
cp .build/AppIcon.icns "$app_bundle/Contents/Resources/"
cp .build/Television.png "$app_bundle/Contents/Resources/"
cp -R Assets/ChannelLogos "$app_bundle/Contents/Resources/"
cp -R Assets/PlaybackControls "$app_bundle/Contents/Resources/"
mkdir -p "$app_bundle/Contents/Resources/zh-Hans.lproj"
cp Assets/zh-Hans.lproj/InfoPlist.strings "$app_bundle/Contents/Resources/zh-Hans.lproj/"
cp Sources/SofaTV/Resources/builtin_channels.txt "$app_bundle/Contents/Resources/"
mkdir -p "$app_bundle/Contents/Resources/Licenses"
cp LICENSE "$app_bundle/Contents/Resources/Licenses/SofaTV-GPL-3.0.txt"
cp Assets/ChannelLogos/SOURCE.md "$app_bundle/Contents/Resources/Licenses/Channel-Logos-Source.md"
cp Assets/ChannelLogos/LICENSE-GPL-3.0.txt "$app_bundle/Contents/Resources/Licenses/Channel-Logos-GPL-3.0.txt"
# 版本号和构建号仅在用户明确要求时调整，日常构建保持不变。
cat > "$app_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SofaTV</string>
<key>CFBundleIdentifier</key><string>local.sofatv.app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleName</key><string>沙发电视</string>
<key>CFBundleDisplayName</key><string>沙发电视</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Keep a stable designated requirement across ad-hoc development builds. Without
# this, macOS identifies every rebuild by its changing CDHash and can treat data
# from the previous build as belonging to a different app.
codesign --force --sign - --requirements '=designated => identifier "local.sofatv.app"' "$app_bundle"
