#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/sofatv-clang
reminder_sources=(Sources/SofaTV/ProgramReminder.swift Sources/SofaTV/ProgramReminderStore.swift Sources/SofaTV/SystemProgramReminderNotifications.swift)
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/CmgRecoveryPolicy.swift Sources/SofaTV/CmgRuntime.swift Sources/SofaTV/CmgAssetLoader.swift Sources/SofaTV/H5eRuntime.swift Sources/SofaTV/HlsQualitySelection.swift tests/CmgChecks.swift -o /private/tmp/sofatv-cmg-check
/private/tmp/sofatv-cmg-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/PlaybackRace.swift tests/PlaybackRaceChecks.swift -o /private/tmp/sofatv-race-check
/private/tmp/sofatv-race-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/PlaybackSleepPrevention.swift tests/PlaybackSleepChecks.swift -o /private/tmp/sofatv-sleep-check
/private/tmp/sofatv-sleep-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/AppWindows.swift tests/AppWindowsChecks.swift -o /private/tmp/sofatv-app-windows-check
/private/tmp/sofatv-app-windows-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/VideoWindowHost.swift tests/VideoWindowHostChecks.swift -o /private/tmp/sofatv-video-windows-check
/private/tmp/sofatv-video-windows-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/SidebarToggleButton.swift tests/SidebarToggleButtonChecks.swift -o /private/tmp/sofatv-sidebar-button-check
/private/tmp/sofatv-sidebar-button-check
python3 tests/check-playlist.py
# Standalone Command Line Tools may omit Swift Testing's macro plugin from
# swiftbuild's automatic plugin discovery. Resolve it from the active toolchain.
testing_plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
testing_flags=()
if [[ -f "$testing_plugin" ]]; then testing_flags=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin"); fi
swift test --disable-sandbox --cache-path /private/tmp/sofatv-cache "${testing_flags[@]}"
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/SofaTheme.swift Sources/SofaTV/ChannelListPinnedHeader.swift tests/ChannelListPinnedHeaderChecks.swift -o /private/tmp/sofatv-pinned-header-check
/private/tmp/sofatv-pinned-header-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/SofaTheme.swift Sources/SofaTV/ChannelListPinnedHeader.swift Sources/SofaTV/AppScrollView.swift Sources/SofaTV/ChannelListScrollStyle.swift tests/ChannelListScrollStyleChecks.swift -o /private/tmp/sofatv-scroll-style-check
/private/tmp/sofatv-scroll-style-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuidePreview.swift Sources/SofaTV/ChannelRow.swift Sources/SofaTV/FavoriteStar.swift Sources/SofaTV/ChannelLogoResolver.swift Sources/SofaTV/ChannelLogoView.swift Sources/SofaTV/ChannelListPinnedHeader.swift Sources/SofaTV/AppScrollView.swift Sources/SofaTV/ChannelListScrollStyle.swift Sources/SofaTV/SofaTheme.swift Sources/SofaTV/ViewState.swift tests/ChannelRowChecks.swift -o /private/tmp/sofatv-channel-row-check
/private/tmp/sofatv-channel-row-check
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
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift tests/ProgramGuideScheduleChecks.swift -o /private/tmp/sofatv-guide-schedule-check
/private/tmp/sofatv-guide-schedule-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuidePreview.swift tests/ProgramGuidePreviewChecks.swift -o /private/tmp/sofatv-guide-preview-check
/private/tmp/sofatv-guide-preview-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuidePreview.swift Sources/SofaTV/ChannelListFocus.swift Sources/SofaTV/ViewState.swift tests/ChannelListFocusChecks.swift -o /private/tmp/sofatv-channel-focus-check
/private/tmp/sofatv-channel-focus-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ProgramGuidePayload.swift tests/ProgramGuidePayloadChecks.swift -o /private/tmp/sofatv-program-guide-payload-check
/private/tmp/sofatv-program-guide-payload-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift Sources/SofaTV/ProgramGuidePayload.swift Sources/SofaTV/ProgramGuideRepository.swift tests/ProgramGuideRepositoryChecks.swift -o /private/tmp/sofatv-program-guide-repository-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang -framework AppKit Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift Sources/SofaTV/ProgramGuidePayload.swift Sources/SofaTV/ProgramGuideRepository.swift Sources/SofaTV/ProgramGuideStore.swift "${reminder_sources[@]}" tests/ProgramGuideStoreChecks.swift -o /private/tmp/sofatv-program-guide-store-check
/private/tmp/sofatv-program-guide-store-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/ChannelCatalog.swift Sources/SofaTV/ProgramGuide.swift Sources/SofaTV/ProgramGuidePayload.swift Sources/SofaTV/ProgramGuideRepository.swift Sources/SofaTV/ProgramGuideStore.swift Sources/SofaTV/ProgramGuidePreview.swift Sources/SofaTV/ProgramGuideDrawer.swift Sources/SofaTV/ProgramReminderWindow.swift Sources/SofaTV/AppWindows.swift "${reminder_sources[@]}" Sources/SofaTV/ChannelLogoResolver.swift Sources/SofaTV/ChannelLogoView.swift Sources/SofaTV/ChannelListPinnedHeader.swift Sources/SofaTV/AppScrollView.swift Sources/SofaTV/ChannelListScrollStyle.swift Sources/SofaTV/SofaTheme.swift Sources/SofaTV/ViewState.swift tests/ProgramGuideDrawerChecks.swift -o /private/tmp/sofatv-guide-drawer-check
/private/tmp/sofatv-guide-drawer-check
/private/tmp/sofatv-program-guide-repository-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/VideoVolumeScroll.swift tests/VideoVolumeScrollChecks.swift -o /private/tmp/sofatv-video-volume-check
/private/tmp/sofatv-video-volume-check
swiftc -swift-version 6 -module-cache-path /private/tmp/sofatv-clang Sources/SofaTV/PlaybackVolume.swift tests/PlaybackVolumeChecks.swift -o /private/tmp/sofatv-playback-volume-check
/private/tmp/sofatv-playback-volume-check
./scripts/test-updates.sh
