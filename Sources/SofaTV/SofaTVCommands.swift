import AppKit
import SwiftUI

private struct ChannelLibraryKey: FocusedValueKey { typealias Value = Library }
extension FocusedValues {
    var channelLibrary: Library? {
        get { self[ChannelLibraryKey.self] }
        set { self[ChannelLibraryKey.self] = newValue }
    }
}

struct SofaTVCommands: Commands {
    @FocusedValue(\.channelLibrary) private var library
    let language: AppLanguage

    private func text(_ value: String.LocalizationValue) -> String {
        L10n.text(value, language: language)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(text("关于沙发电视")) { showAbout() }
            Divider()
            Button(text("检查更新…")) { checkForUpdates() }
        }
        CommandGroup(after: .appInfo) {
            Button(text("设置…")) { SofaSettings.show() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .help) {
            Button(text("新手引导")) { OnboardingWindow.show() }
        }
        CommandMenu(text("频道")) {
            Button(text("导入频道文件…")) { library?.importChannels() }.keyboardShortcut("o").disabled(library == nil)
            Button(text("导入在线列表…")) { library?.showAddressWindow(direct: false) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(library == nil)
            Button(text("打开直播地址…")) { library?.showAddressWindow(direct: true) }.keyboardShortcut("l").disabled(library == nil)
            Divider()
            if let library { ChannelSourceMenu(library: library) }
            Button(text("整理频道分组…")) { library?.showChannelOrganizer() }.disabled(library == nil)
            Button(text("编辑频道来源…")) { library?.showListManager() }.disabled(library == nil)
        }
        CommandMenu(text("播放")) {
            if let library { PlaybackMenu(library: library) }
            Divider()
            Button(text("节目预约…")) { ProgramReminderWindow.show() }
        }
    }
    @MainActor private func showAbout() { AboutWindowController.shared.show() }
    @MainActor private func checkForUpdates() { UpdateChecker.shared.check() }
}

private struct ChannelSourceMenu: View {
    @ObservedObject var library: Library
    var body: some View {
        Button(library.updatingSourceIDs.isEmpty ? L10n.text("更新频道列表") : L10n.text("正在更新频道列表…")) {
            library.refreshOnlineChannels()
        }
        .disabled(!library.updatingSourceIDs.isEmpty || !library.channelLists.contains { $0.remoteURL != nil })
    }
}

private struct PlaybackMenu: View {
    @ObservedObject var library: Library
    var body: some View {
        Button(L10n.text("上一个频道")) { library.nextChannel(-1) }.keyboardShortcut(.upArrow, modifiers: []).disabled(library.channels.isEmpty)
        Button(L10n.text("下一个频道")) { library.nextChannel(1) }.keyboardShortcut(.downArrow, modifiers: []).disabled(library.channels.isEmpty)
        Button(L10n.text("重新播放")) { library.reloadCurrentChannel() }.disabled(library.selected == nil)
        Button(L10n.text("停止播放")) { library.stopPlayback() }.disabled(library.selected == nil)
        Button(library.previousChannel.map { L10n.text("返回上一观看频道 · \($0.displayName)") } ?? L10n.text("返回上一观看频道")) {
            library.playPreviousChannel()
        }
        .disabled(library.previousChannel == nil)
        Divider()
        Button(L10n.text("降低音量")) { library.adjustVolume(-0.05) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(library.selected == nil)
        Button(L10n.text("增大音量")) { library.adjustVolume(0.05) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(library.selected == nil)
        Text(L10n.text("当前频道音量 \(Int((library.volume * 100).rounded()))%"))
        Divider()
        Picker(L10n.text("清晰度"), selection: $library.quality) {
            Text(L10n.text("最高")).tag(0); Text(L10n.text("适中")).tag(1); Text(L10n.text("最低")).tag(2)
        }
        Picker(L10n.text("直播模式"), selection: $library.mode) {
            Text(L10n.text("稳定")).tag(0); Text(L10n.text("适中")).tag(1); Text(L10n.text("低延迟")).tag(2)
        }
        Toggle(L10n.text("拉伸画面"), isOn: $library.stretch)
        if let channel = library.selected {
            Picker(L10n.text("播放线路"), selection: Binding(get: { library.sourceIndex }, set: { library.changeSource($0) })) {
                ForEach(Array(channel.sources.enumerated()), id: \.offset) { index, source in
                    Text(L10n.text("线路 \(index + 1) · \(source.scheme == "webview" ? L10n.text("后台解析") : (source.host ?? L10n.text("直播")))")).tag(index)
                }
            }
        }
        Divider()
        Text(library.playbackMetrics)
        Button(L10n.text("复制播放诊断")) { library.copyDiagnostics() }
    }
}
