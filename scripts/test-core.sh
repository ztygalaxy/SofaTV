#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/sofatv-clang
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/CmgRecoveryPolicy.swift Sources/SofaTV/CmgRuntime.swift Sources/SofaTV/CmgAssetLoader.swift Sources/SofaTV/H5eRuntime.swift Sources/SofaTV/HlsQualitySelection.swift tests/CmgChecks.swift -o /private/tmp/sofatv-cmg-check
/private/tmp/sofatv-cmg-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/PlaybackRace.swift tests/PlaybackRaceChecks.swift -o /private/tmp/sofatv-race-check
/private/tmp/sofatv-race-check
python3 tests/check-playlist.py
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelLogoResolver.swift tests/ChannelLogoResolverChecks.swift -o /private/tmp/sofatv-logo-check
/private/tmp/sofatv-logo-check
clang -O2 -I scripts tests/H5ePesChecks.c -o /private/tmp/sofatv-h5e-pes-check
/private/tmp/sofatv-h5e-pes-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/HlsQualitySelection.swift tests/HlsQualityChecks.swift -o /private/tmp/sofatv-hls-quality-check
/private/tmp/sofatv-hls-quality-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/UpdateManifest.swift tests/UpdateManifestChecks.swift -o /private/tmp/sofatv-update-check
/private/tmp/sofatv-update-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang -framework AppKit Sources/SofaTV/DockIconBadgeView.swift tests/DockIconBadgeChecks.swift -o /private/tmp/sofatv-dock-icon-check
/private/tmp/sofatv-dock-icon-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift tests/ProgramGuideChecks.swift -o /private/tmp/sofatv-program-guide-check
/private/tmp/sofatv-program-guide-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ProgramGuidePayload.swift tests/ProgramGuidePayloadChecks.swift -o /private/tmp/sofatv-program-guide-payload-check
/private/tmp/sofatv-program-guide-payload-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift Sources/SofaTV/ProgramGuidePayload.swift Sources/SofaTV/ProgramGuideRepository.swift tests/ProgramGuideRepositoryChecks.swift -o /private/tmp/sofatv-program-guide-repository-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang -framework AppKit Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift Sources/SofaTV/ProgramGuidePayload.swift Sources/SofaTV/ProgramGuideRepository.swift Sources/SofaTV/ProgramGuideStore.swift tests/ProgramGuideStoreChecks.swift -o /private/tmp/sofatv-program-guide-store-check
/private/tmp/sofatv-program-guide-store-check
/private/tmp/sofatv-program-guide-repository-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/VideoVolumeScroll.swift tests/VideoVolumeScrollChecks.swift -o /private/tmp/sofatv-video-volume-check
/private/tmp/sofatv-video-volume-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/PlaybackVolume.swift tests/PlaybackVolumeChecks.swift -o /private/tmp/sofatv-playback-volume-check
/private/tmp/sofatv-playback-volume-check
