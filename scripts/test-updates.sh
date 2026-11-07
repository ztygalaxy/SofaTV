#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/sofatv-clang
test_dir="$(mktemp -d /private/tmp/sofatv-update-check.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang \
  -emit-library -emit-module -module-name UpdateSupport Sources/UpdateSupport/UpdateInstallation.swift \
  -emit-module-path "$test_dir/UpdateSupport.swiftmodule" -o "$test_dir/libUpdateSupport.dylib"
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang \
  -I "$test_dir" -L "$test_dir" -lUpdateSupport -Xlinker -rpath -Xlinker "$test_dir" \
  Sources/SofaTVUpdater/main.swift -o "$test_dir/SofaTVUpdater"
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang \
  -I "$test_dir" -L "$test_dir" -lUpdateSupport -Xlinker -rpath -Xlinker "$test_dir" \
  Sources/SofaTV/UpdateManifest.swift Sources/SofaTV/AutomaticUpdateCheck.swift \
  Sources/SofaTV/UpdateDownload.swift Sources/SofaTV/UpdateInstaller.swift \
  Sources/SofaTV/UpdateWindowController.swift Sources/SofaTV/AppWindows.swift \
  tests/Updates/*.swift -o "$test_dir/checks"
"$test_dir/checks" "$test_dir/SofaTVUpdater"
