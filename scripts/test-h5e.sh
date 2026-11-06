#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if (( $# < 1 )); then
    print -u2 "Usage: ./scripts/test-h5e.sh /path/to/fixtures [--save-frames]"
    exit 1
fi
export CLANG_MODULE_CACHE_PATH=/private/tmp/sofatv-clang
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/CmgRecoveryPolicy.swift Sources/SofaTV/CmgRuntime.swift Sources/SofaTV/H5eRuntime.swift tests/H5eDecodeChecks.swift -o /private/tmp/sofatv-h5e-check
/private/tmp/sofatv-h5e-check "$1" "$PWD/native/h5e/libSofaTVH5e.dylib" "${@:2}"
