#!/bin/zsh
set -eu
cd "${0:A:h:h}"

version="$(tr -d '[:space:]' < VERSION)"
arch="${1:-$(uname -m)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print -u2 "Invalid VERSION: $version"; exit 1; }
[[ "$arch" == arm64 || "$arch" == x86_64 ]] || { print -u2 "Unsupported architecture: $arch"; exit 1; }
application="dist/沙发电视.app"
[[ "$(lipo -archs "$application/Contents/MacOS/SofaTV")" == "$arch" ]] || { print -u2 "Application architecture does not match $arch"; exit 1; }
codesign --verify --deep --strict "$application"

package_name="SofaTV-$version-$arch"
staging="$(mktemp -d /private/tmp/sofatv-package.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/zip" "$staging/dmg"

# The ZIP's application name follows the archive name, including version/chip.
ditto "$application" "$staging/zip/$package_name.app"
ditto -c -k --sequesterRsrc --keepParent \
    "$staging/zip/$package_name.app" "dist/$package_name.zip"

# DMG installations keep a stable name when dragged into Applications.
ditto "$application" "$staging/dmg/沙发电视.app"
ln -s /Applications "$staging/dmg/Applications"
hdiutil create -ov -format UDZO -imagekey zlib-level=9 -fs HFS+ \
    -volname "沙发电视 $version" -srcfolder "$staging/dmg" "dist/$package_name.dmg"
hdiutil verify "dist/$package_name.dmg"
print "Created dist/$package_name.zip and dist/$package_name.dmg"
