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
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于沙发电视") { showAbout() }
            Divider()
            Button("检查更新…") { checkForUpdates() }
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu("频道") {
            Button("导入频道文件…") { library?.importChannels() }.keyboardShortcut("o").disabled(library == nil)
            Button("导入在线列表…") { library?.showAddressWindow(direct: false) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(library == nil)
            Button("打开直播地址…") { library?.showAddressWindow(direct: true) }.keyboardShortcut("l").disabled(library == nil)
            Divider()
            if let library { ChannelSourceMenu(library: library) }
            Button("整理频道分组…") { library?.showChannelOrganizer() }.disabled(library == nil)
            Button("编辑频道来源…") { library?.showListManager() }.disabled(library == nil)
        }
        CommandMenu("播放") {
            if let library { PlaybackMenu(library: library) }
            Divider()
            Button("节目预约…") { ProgramReminderWindow.show() }
        }
    }
    @MainActor private func showAbout() { AboutWindowController.shared.show() }
    @MainActor private func checkForUpdates() { UpdateChecker.shared.check() }
}

private struct ChannelSourceMenu: View {
    @ObservedObject var library: Library
    var body: some View {
        Button(library.updatingSourceIDs.isEmpty ? "更新频道列表" : "正在更新频道列表…") {
            library.refreshOnlineChannels()
        }
        .disabled(!library.updatingSourceIDs.isEmpty || !library.channelLists.contains { $0.remoteURL != nil })
    }
}

private struct PlaybackMenu: View {
    @ObservedObject var library: Library
    var body: some View {
        Button("上一个频道") { library.nextChannel(-1) }.keyboardShortcut(.upArrow, modifiers: []).disabled(library.channels.isEmpty)
        Button("下一个频道") { library.nextChannel(1) }.keyboardShortcut(.downArrow, modifiers: []).disabled(library.channels.isEmpty)
        Button("重新播放") { library.reloadCurrentChannel() }.disabled(library.selected == nil)
        Button("停止播放") { library.stopPlayback() }.disabled(library.selected == nil)
        Button(library.previousChannel.map { "返回上一观看频道 · \($0.displayName)" } ?? "返回上一观看频道") {
            library.playPreviousChannel()
        }
        .disabled(library.previousChannel == nil)
        Divider()
        Button("降低音量") { library.adjustVolume(-0.05) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(library.selected == nil)
        Button("增大音量") { library.adjustVolume(0.05) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(library.selected == nil)
        Text("当前频道音量 \(Int((library.volume * 100).rounded()))%")
        Divider()
        Picker("清晰度", selection: $library.quality) {
            Text("最高").tag(0); Text("适中").tag(1); Text("最低").tag(2)
        }
        Picker("直播模式", selection: $library.mode) {
            Text("稳定").tag(0); Text("适中").tag(1); Text("低延迟").tag(2)
        }
        Toggle("拉伸画面", isOn: $library.stretch)
        if let channel = library.selected {
            Picker("播放线路", selection: Binding(get: { library.sourceIndex }, set: { library.changeSource($0) })) {
                ForEach(Array(channel.sources.enumerated()), id: \.offset) { index, source in
                    Text("线路 \(index + 1) · \(source.scheme == "webview" ? "后台解析" : (source.host ?? "直播"))").tag(index)
                }
            }
        }
        Divider()
        Text(library.nativeDiagnostic)
        Text(library.playbackMetrics)
        Button("复制播放诊断") { library.copyDiagnostics() }
    }
}
