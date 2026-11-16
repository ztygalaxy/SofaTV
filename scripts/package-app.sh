#!/bin/zsh
set -eu
cd "${0:A:h:h}"

application="dist/SofaTV.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application/Contents/Info.plist")"
arch="${1:-$(uname -m)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print -u2 "Invalid VERSION: $version"; exit 1; }
[[ "$arch" == arm64 || "$arch" == x86_64 ]] || { print -u2 "Unsupported architecture: $arch"; exit 1; }
[[ "$(lipo -archs "$application/Contents/MacOS/SofaTV")" == "$arch" ]] || { print -u2 "Application architecture does not match $arch"; exit 1; }
codesign --verify --deep --strict "$application"

package_name="SofaTV-$version-$arch"
staging="$(mktemp -d /private/tmp/sofatv-package.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/zip" "$staging/dmg"

# Released updaters require the ZIP's app name to match the archive name.
ditto "$application" "$staging/zip/$package_name.app"
ditto -c -k --sequesterRsrc --keepParent \
    "$staging/zip/$package_name.app" "dist/$package_name.zip"

# Finder localizes this name when the app basename matches CFBundleDisplayName.
ditto "$application" "$staging/dmg/${application:t}"
ln -s /Applications "$staging/dmg/Applications"
hdiutil create -ov -format UDZO -imagekey zlib-level=9 -fs HFS+ \
    -volname "沙发电视 $version" -srcfolder "$staging/dmg" "dist/$package_name.dmg"
hdiutil verify "dist/$package_name.dmg"
print "Created dist/$package_name.zip and dist/$package_name.dmg"
