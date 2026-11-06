import AppKit
import SwiftUI

private struct ChannelLibraryKey: FocusedValueKey { typealias Value = Library }
private struct ChannelUIKey: FocusedValueKey { typealias Value = UIState }
extension FocusedValues {
    var channelLibrary: Library? {
        get { self[ChannelLibraryKey.self] }
        set { self[ChannelLibraryKey.self] = newValue }
    }
    var channelUI: UIState? {
        get { self[ChannelUIKey.self] }
        set { self[ChannelUIKey.self] = newValue }
    }
}

struct SofaTVCommands: Commands {
    @FocusedValue(\.channelLibrary) private var library
    @FocusedValue(\.channelUI) private var ui
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于沙发电视") { showAbout() }
            Divider()
            Button("检查更新…") { checkForUpdates() }
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu("频道") {
            Button("导入频道文件…") { ui?.showImporter = true }.keyboardShortcut("o").disabled(ui == nil)
            Button("导入在线列表…") { openAddress(direct: false) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(ui == nil)
            Button("打开直播地址…") { openAddress(direct: true) }.keyboardShortcut("l").disabled(ui == nil)
            Divider()
            Button("恢复内置频道") { library?.restoreBuiltins() }.disabled(library == nil)
            Button("管理频道列表…") { ui?.showListManager = true }.disabled(ui == nil || library == nil)
        }
        CommandMenu("播放") {
            if let library { PlaybackMenu(library: library) }
        }
    }
    private func openAddress(direct: Bool) {
        ui?.direct = direct; ui?.address = ""; ui?.showAddress = true
    }

    @MainActor private func showAbout() { AboutWindowController.shared.show() }
    @MainActor private func checkForUpdates() { UpdateChecker.shared.check() }
}

private struct PlaybackMenu: View {
    @ObservedObject var library: Library
    var body: some View {
        Button("上一个频道") { library.nextChannel(-1) }.keyboardShortcut(.upArrow, modifiers: []).disabled(library.channels.isEmpty)
        Button("下一个频道") { library.nextChannel(1) }.keyboardShortcut(.downArrow, modifiers: []).disabled(library.channels.isEmpty)
        Button("重新播放") { if let channel = library.selected { library.play(channel) } }.disabled(library.selected == nil)
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
