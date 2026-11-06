import SwiftUI
import AVKit
import WebKit
import UniformTypeIdentifiers

@MainActor final class Library: ObservableObject {
    @Published var channels: [Channel] = []
    @Published private(set) var channelLists: [ChannelList] = []
    @Published var favorites: Set<String> = []
    @Published var selected: Channel?
    @Published var error: String?
    @Published var loading = false
    @Published var sourceIndex = 0
    @Published var webChannel: URL?
    @Published var playbackStatus = "就绪"
    @Published private var playbackVolume = PlaybackVolume(
        isMuted: UserDefaults.standard.bool(forKey: "playback-muted"),
        volumeBeforeMute: (UserDefaults.standard.object(forKey: "playback-volume-before-mute") as? NSNumber)?.floatValue ?? 0.3
    )
    var volume: Float { playbackVolume.volume }
    var isMuted: Bool { playbackVolume.isMuted }
    @Published var quality = UserDefaults.standard.integer(forKey: "quality") {
        didSet {
            UserDefaults.standard.set(quality, forKey: "quality"); applySettings()
            if oldValue != quality, let selected { play(selected) }
        }
    }
    @Published var mode = UserDefaults.standard.integer(forKey: "mode") { didSet { UserDefaults.standard.set(mode, forKey: "mode"); applySettings() } }
    @Published var stretch = UserDefaults.standard.bool(forKey: "stretch") { didSet { UserDefaults.standard.set(stretch, forKey: "stretch") } }
    @Published var videoVisible = false
    @Published var webVideo = false
    let resolver = WebMediaResolver()
    private var session = UUID()
    private var race = PlaybackRace()
    @Published var playbackMetrics = "尚无播放统计"
    @Published var nativeDiagnostic = "原生通道尚未启动"
    private var diagnostics: [String] = []
    func recordNative(_ message: String) {
        nativeDiagnostic = message
        diagnostics.append(message)
        if diagnostics.count > 60 { diagnostics.removeFirst() }
    }
    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.joined(separator: "\n"), forType: .string)
    }
    private var resolving = false
    private var latestWebMedia: (url: URL, cookies: [HTTPCookie])?
    private var deferredH5eIndex: Int?
    private var allowReducedH5e = false
    private var cmgLoader: CmgAssetLoader?
    let player = AVPlayer()
    private var observation: NSKeyValueObservation?
    private var playbackObservers: [NSObjectProtocol] = []
    private var timeout: Task<Void, Never>?
    private var attempted = Set<Int>()
    func applySettings() {
        player.currentItem?.preferredPeakBitRate = quality == 1 ? 3_000_000 : quality == 2 ? 800_000 : 0
        player.currentItem?.preferredForwardBufferDuration = mode == 2 ? 1 : mode == 1 ? 5 : 15
        player.automaticallyWaitsToMinimizeStalling = mode != 2
    }
    func restoreBuiltins() {
        do { guard let url = Bundle.main.url(forResource: "builtin_channels", withExtension: "txt") else { throw NSError(domain: "SofaTV", code: 2, userInfo: [NSLocalizedDescriptionKey: "应用内置频道文件缺失，请重新安装完整应用。"]) }; try parse(String(contentsOf: url, encoding: .utf8), as: .builtIn()) } catch { self.error = error.localizedDescription }
    }
    func changeSource(_ index: Int) {
        guard let channel = selected, channel.sources.indices.contains(index) else { return }
        UserDefaults.standard.set(channel.sources[index].absoluteString, forKey: "line-" + channel.id)
        attempted = []; allowReducedH5e = false; deferredH5eIndex = nil; start(channel, index: index)
    }
    func nextChannel(_ offset: Int) {
        guard !channels.isEmpty else { return }
        guard let selected, let index = channels.firstIndex(of: selected) else {
            play(offset < 0 ? channels[channels.count - 1] : channels[0]); return
        }
        play(channels[(index + offset + channels.count) % channels.count])
    }
    func adjustVolume(_ offset: Float) {
        setVolume(volume + offset)
    }
    func setVolume(_ value: Float) {
        guard selected != nil else { return }
        var next = playbackVolume
        next.setVolume(value)
        guard next != playbackVolume else { return }
        applyVolume(next, rememberChannel: true)
    }
    func toggleMute() {
        guard selected != nil else { return }
        var next = playbackVolume
        next.toggleMute()
        applyVolume(next, rememberChannel: true)
    }
    private func applyVolume(_ next: PlaybackVolume, rememberChannel: Bool) {
        if next != playbackVolume { playbackVolume = next }
        // Engine mute flags belong to playback handoff; amplitude zero keeps both engines silent.
        player.volume = next.volume
        resolver.setVolume(next.volume)
        UserDefaults.standard.set(next.isMuted, forKey: "playback-muted")
        UserDefaults.standard.set(next.volumeBeforeMute, forKey: "playback-volume-before-mute")
        if rememberChannel, next.volume > 0, let selected {
            UserDefaults.standard.set(next.volume, forKey: "volume-" + selected.id)
        }
    }
    private func restoreVolume(for channel: Channel) {
        let key = "volume-" + channel.id
        let level = UserDefaults.standard.object(forKey: key) == nil ? 0.3 : UserDefaults.standard.float(forKey: key)
        var next = playbackVolume
        next.restoreChannelVolume(level)
        applyVolume(next, rememberChannel: false)
    }
    private func failed(_ channel: Channel, index: Int, message: String) {
        guard selected?.id == channel.id, sourceIndex == index else { return }
        if let fallback = deferredH5eIndex {
            allowReducedH5e = true; start(channel, index: fallback); return
        }
        if let next = channel.sources.indices.first(where: { !attempted.contains($0) }) { start(channel, index: next) }
        else {
            videoVisible = false; webVideo = false
            DockIconController.shared.reset()
            playbackStatus = "播放失败"; error = message
        }
    }
    private func start(_ channel: Channel, index: Int) {
        timeout?.cancel(); observation = nil; resolver.cancel(); session = UUID(); cmgLoader?.cancel(); cmgLoader = nil; videoVisible = false; webVideo = false; resolving = false; sourceIndex = index; attempted.insert(index)
        DockIconController.shared.reset()
        latestWebMedia = nil; deferredH5eIndex = nil
        race.begin(); diagnostics = []; playbackMetrics = "尚无播放统计"; recordNative("等待媒体地址和解密会话")
        let url = channel.sources[index]
        player.isMuted = true
        player.pause(); player.replaceCurrentItem(with: nil)
        if url.scheme == "webview" {
            guard let page = URL(string: String(url.absoluteString.dropFirst("webview://".count))), ["http", "https"].contains(page.scheme ?? "") else {
                failed(channel, index: index, message: "无效的网页频道地址"); return
            }
            startWeb(page, channel: channel, index: index)
            return
        }
        if H5eRuntime.needsDecryption(url) {
            // Race the native CCTV decoder against the matching webpage immediately.
            // Previously this webpage was only attempted after a 20-second native timeout.
            if !allowReducedH5e, let web = channel.sources.enumerated().first(where: { $0.element.scheme == "webview" }),
               let page = webpageURL(web.element) {
                attempted.insert(web.offset)
                startWeb(page, channel: channel, index: index)
            }
            playbackStatus = "原生视频解密中..."
        } else { playbackStatus = "连接中…" }
        playMedia(url, cookies: [], channel: channel, index: index)
    }
    private func webpageURL(_ url: URL) -> URL? {
        guard url.scheme == "webview", let page = URL(string: String(url.absoluteString.dropFirst("webview://".count))),
              ["http", "https"].contains(page.scheme ?? "") else { return nil }
        return page
    }
    private func startWeb(_ page: URL, channel: Channel, index: Int) {
        resolving = true; playbackStatus = "正在解析视频…"
        let token = session
        resolver.resolve(page, completion: { [weak self] media, cookies in
            guard let self, self.session == token, self.race.output != .native else { return }
            self.latestWebMedia = (media, cookies)
            if !self.videoVisible && self.cmgLoader == nil { self.playbackStatus = "已发现视频，连接中…" }
            if self.cmgLoader == nil {
                self.recordNative(self.resolver.cmgState == nil ? "发现媒体地址，等待央视频会话状态" : "已采集央视频会话状态")
                self.playMedia(media, cookies: cookies, channel: channel, index: index)
            }
        }, failure: { [weak self] message in
            guard let self, self.session == token else { return }
            self.race.failWeb(self.race.token)
            if !self.videoVisible && self.cmgLoader == nil { self.playbackStatus = message }
        })
        enterCompatibility()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(40))
            guard !Task.isCancelled, let self, self.session == token, !self.videoVisible else { return }
            self.failed(channel, index: index, message: "网页和原生通道均未能显示视频，请重试或切换线路。")
        }
    }
    private func playMedia(_ url: URL, cookies: [HTTPCookie], channel: Channel, index: Int) {
        guard race.output != .native, cmgLoader == nil else { return }
        let loader: CmgAssetLoader?
        if H5eRuntime.needsDecryption(url) {
            loader = CmgAssetLoader(cookies: cookies, quality: quality)
            recordNative("已启动央视 H5E 原生解密通道")
        } else if resolving, let state = resolver.cmgState, url.host?.hasSuffix("ysp.cctv.cn") == true {
            loader = CmgAssetLoader(state: state, cookies: cookies, quality: quality)
            recordNative("已启动央视频原生解密通道")
        } else { loader = nil }
        if let loader {
            cmgLoader = loader
            if !videoVisible { playbackStatus = "原生视频解密中..." }
            let token = session
            if H5eRuntime.needsDecryption(url), resolving, quality == 0, !allowReducedH5e {
                loader.onBelowRequestedResolution = { [weak self, weak loader] actual, requested in
                    Task { @MainActor [weak self, weak loader] in
                        guard let self, let loader, self.session == token, self.cmgLoader === loader else { return }
                        self.observation = nil; self.player.pause(); self.player.replaceCurrentItem(with: nil)
                        self.cmgLoader = nil; loader.cancel(); self.deferredH5eIndex = index
                        self.recordNative("央视直链最高实际 \(actual.description)，继续准备央视频高清线路（目标 \(requested.description)）")
                        if let media = self.latestWebMedia { self.playMedia(media.url, cookies: media.cookies, channel: channel, index: index) }
                    }
                }
            }
            loader.onDiagnostic = { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.session == token else { return }
                    self.recordNative(message)
                }
            }
            loader.start(url) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.session == token else { return }
                    switch result {
                    case .success(let local): self.installItem(AVPlayerItem(url: local), channel: channel, index: index)
                    case .failure(let error):
                        self.recordNative("原生通道启动失败：" + error.localizedDescription)
                        self.race.failNative(self.race.token)
                        if !self.resolving { self.failed(channel, index: index, message: error.localizedDescription) }
                    }
                }
            }
            return
        }
        if cmgLoader != nil { return }
        // Encrypted Yangshipin media must wait for the matching CMG state.
        if resolving, url.host?.hasSuffix("ysp.cctv.cn") == true, resolver.cmgState == nil { return }
        installItem(AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])), channel: channel, index: index)
    }
    private func installItem(_ item: AVPlayerItem, channel: Channel, index: Int) {
        observation = nil
        for observer in playbackObservers { NotificationCenter.default.removeObserver(observer) }
        playbackObservers = []
        let token = session
        for name in [
            Notification.Name.AVPlayerItemNewErrorLogEntry,
            .AVPlayerItemPlaybackStalled,
            .AVPlayerItemNewAccessLogEntry,
            .AVPlayerItemDidPlayToEndTime,
            .AVPlayerItemFailedToPlayToEndTime
        ] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] notification in
                let eventName = notification.name
                let endFailureMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.session == token, self.player.currentItem === item else { return }
                    if eventName == .AVPlayerItemDidPlayToEndTime {
                        self.videoVisible = false; self.webVideo = false
                        DockIconController.shared.reset()
                        self.playbackStatus = "播放已结束"
                    } else if eventName == .AVPlayerItemFailedToPlayToEndTime {
                        self.failed(channel, index: index, message: endFailureMessage ?? "播放意外中断")
                    } else if eventName == .AVPlayerItemNewErrorLogEntry, let event = item.errorLog()?.events.last {
                        self.recordNative("播放器错误：\(event.errorDomain) / \(event.errorStatusCode)")
                    } else if eventName == .AVPlayerItemPlaybackStalled { self.recordNative("播放器发生缓冲停顿") }
                    else if let event = item.accessLog()?.events.last {
                        self.playbackMetrics = "丢帧 \(event.numberOfDroppedVideoFrames) / 停顿 \(event.numberOfStalls)"
                        self.recordNative("播放统计：" + self.playbackMetrics)
                    }
                }
            }
            playbackObservers.append(observer)
        }
        player.isMuted = true
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status; let message = item.error?.localizedDescription ?? "所有线路均无法播放"
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if status == .readyToPlay {
                    self.recordNative("媒体已加载，等待原生首帧")
                    if !self.videoVisible { self.playbackStatus = "正在准备画面…" }
                } else if status == .failed {
                    let error = item.error as NSError?
                    self.recordNative("原生播放失败：\(error?.domain ?? "未知") / \(error?.code ?? 0)；\(message)")
                    self.race.failNative(self.race.token)
                    if !self.resolving { self.failed(channel, index: index, message: message) }
                }
            }
        }
        player.replaceCurrentItem(with: item); applySettings(); player.play()
        if resolving { return }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self else { return }
            self.failed(channel, index: index, message: "连接超时，请检查网络或切换线路")
        }
    }
    private func enterCompatibility() {
        let token = session
        let raceToken = race.token
        resolver.showVideoOnly { [weak self] ready in
            guard let self, self.session == token else { return }
            if ready, self.race.webReady(raceToken) {
                self.webVideo = true; self.videoVisible = true
                if let selected = self.selected { DockIconController.shared.show(channelName: selected.name) }
                self.player.isMuted = true
                self.resolver.setAudible(true, volume: self.volume)
                self.playbackStatus = "网页视频播放中 · 原生准备中"
            } else if !ready {
                self.race.failWeb(raceToken)
                if !self.videoVisible { self.playbackStatus = "网页画面未就绪，继续等待原生通道…" }
            }
        }
    }
    func videoAppeared(_ item: AVPlayerItem?) {
        guard let item, player.currentItem === item, race.nativeReady(race.token) else { return }
        let token = session
        let size = item.presentationSize
        recordNative(size.width > 0 && size.height > 0 ? "原生首帧已显示 · \(Int(size.width))×\(Int(size.height))" : "原生首帧已显示")
        timeout?.cancel(); resolving = false
        if let selected { DockIconController.shared.show(channelName: selected.name) }
        // Mute the web channel before enabling native audio, including queued script calls.
        resolver.setAudible(false) { [weak self] in
            guard let self, self.session == token, self.race.output == .native else { return }
            self.webVideo = false; self.videoVisible = true; self.player.isMuted = false
            self.resolver.suspendVideoForNative()
            self.playbackStatus = "原生视频播放中"
        }
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "channel-lists"), let saved = try? JSONDecoder().decode([ChannelList].self, from: data) {
            channelLists = saved; channels = ChannelCatalog.merge(saved)
        } else if let data = UserDefaults.standard.data(forKey: "channels"), let saved = try? JSONDecoder().decode([Channel].self, from: data), !saved.isEmpty {
            channelLists = [.legacy(saved)]; channels = saved
        }
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        persistLibrary()
    }
    func play(_ channel: Channel) {
        timeout?.cancel(); observation = nil; resolver.cancel(); session = UUID(); webChannel = nil
        selected = channel; restoreVolume(for: channel); attempted = []; allowReducedH5e = false; deferredH5eIndex = nil
        guard !channel.sources.isEmpty else {
            DockIconController.shared.reset()
            player.pause(); player.replaceCurrentItem(with: nil)
            playbackStatus = "暂无视频直链"
            error = "这个频道没有可用线路。"
            return
        }
        let saved = UserDefaults.standard.string(forKey: "line-" + channel.id)
        let index = channel.sources.firstIndex(where: { $0.absoluteString == saved }) ?? channel.sources.firstIndex(where: { $0.scheme != "webview" }) ?? 0
        start(channel, index: index)
    }
    func favorite(_ channel: Channel) {
        if favorites.contains(channel.id) { favorites.remove(channel.id) } else { favorites.insert(channel.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }
    private func persistLibrary() {
        if let data = try? JSONEncoder().encode(channelLists) { UserDefaults.standard.set(data, forKey: "channel-lists") }
        if let data = try? JSONEncoder().encode(channels) { UserDefaults.standard.set(data, forKey: "channels") }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }
    private func migratePreferences(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        if let value = UserDefaults.standard.object(forKey: "volume-" + oldID) { UserDefaults.standard.set(value, forKey: "volume-" + newID) }
        if let value = UserDefaults.standard.string(forKey: "line-" + oldID) { UserDefaults.standard.set(value, forKey: "line-" + newID) }
        UserDefaults.standard.removeObject(forKey: "volume-" + oldID)
        UserDefaults.standard.removeObject(forKey: "line-" + oldID)
    }
    func stopPlayback() {
        timeout?.cancel(); observation = nil; resolver.cancel(); cmgLoader?.cancel(); cmgLoader = nil
        for observer in playbackObservers { NotificationCenter.default.removeObserver(observer) }
        playbackObservers = []
        player.pause(); player.replaceCurrentItem(with: nil); selected = nil; sourceIndex = 0
        DockIconController.shared.reset()
        videoVisible = false; webVideo = false; resolving = false; playbackStatus = "就绪"
    }
    private func rebuildChannels() {
        let previousChannels = channels
        let previousSelected = selected
        let previousSource = previousSelected.flatMap { channel in channel.sources.indices.contains(sourceIndex) ? channel.sources[sourceIndex] : nil }
        let selectedWasManaged = previousSelected.map { selected in previousChannels.contains { $0.id == selected.id && $0.name == selected.name && $0.group == selected.group } } ?? false
        channels = ChannelCatalog.merge(channelLists)
        for old in previousChannels {
            guard let refreshed = channels.first(where: { $0.name == old.name && $0.group == old.group }), old.id != refreshed.id else { continue }
            migratePreferences(from: old.id, to: refreshed.id)
            if favorites.remove(old.id) != nil { favorites.insert(refreshed.id) }
        }
        favorites.formIntersection(Set(channels.map(\.id)))
        guard selectedWasManaged, let previousSelected else { persistLibrary(); return }
        if let refreshed = channels.first(where: { $0.name == previousSelected.name && $0.group == previousSelected.group }) {
            self.selected = refreshed
            if let previousSource, let index = refreshed.sources.firstIndex(of: previousSource) { sourceIndex = index }
            else { play(refreshed) }
        } else { stopPlayback() }
        persistLibrary()
    }
    func parse(_ text: String, as list: ChannelList) throws {
        let imported = try ChannelCatalog.parse(text)
        if let index = channelLists.firstIndex(where: { $0.id == list.id }) {
            channelLists[index].name = list.name; channelLists[index].detail = list.detail
            channelLists[index].kind = list.kind; channelLists[index].importedAt = Date()
            channelLists[index].channels = ChannelCatalog.merge(imported, into: channelLists[index].channels)
        } else {
            var list = list; list.channels = imported; channelLists.append(list)
        }
        rebuildChannels()
    }
    func deleteChannel(_ channel: Channel) {
        channelLists = ChannelCatalog.deletingChannel(channel, from: channelLists); rebuildChannels()
    }
    func deleteSource(_ source: URL, from channel: Channel) {
        channelLists = ChannelCatalog.deletingSource(source, from: channel, in: channelLists); rebuildChannels()
    }
    func deleteGroup(_ group: String) {
        channelLists = ChannelCatalog.deletingGroup(group, from: channelLists); rebuildChannels()
    }
    func deleteList(_ list: ChannelList) {
        channelLists.removeAll { $0.id == list.id }; rebuildChannels()
    }
    func channelCount(for list: ChannelList) -> Int { list.channels.count }
    func load(_ address: String, direct: Bool) async {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { error = "请输入有效的 HTTP/HTTPS 地址"; return }
        if direct { play(Channel(name: url.lastPathComponent, group: "直播", url: url)); return }
        loading = true; defer { loading = false }
        do { let (data, response) = try await URLSession.shared.data(from: url); guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }; try parse(text, as: .online(url)) } catch { self.error = error.localizedDescription }
    }
}
enum LibraryDeletion: Identifiable {
    case channel(Channel)
    case source(Channel, URL)
    case group(String)
    case list(ChannelList)

    var id: String {
        switch self {
        case .channel(let channel): "channel:" + channel.group + ":" + channel.name
        case .source(let channel, let source): "source:" + channel.group + ":" + channel.name + ":" + source.absoluteString
        case .group(let group): "group:" + group
        case .list(let list): "list:" + list.id
        }
    }
    var title: String {
        switch self {
        case .channel: "删除频道？"
        case .source: "删除播放线路？"
        case .group: "删除整个分组？"
        case .list: "删除导入列表？"
        }
    }
    var message: String {
        switch self {
        case .channel(let channel): "“\(channel.name)”及其全部播放线路将从频道库中删除。"
        case .source(let channel, let source): "将从“\(channel.name)”删除线路 \(source.host ?? source.absoluteString)。"
        case .group(let group): "“\(group)”中的全部频道将从所有导入列表中删除。"
        case .list(let list): "将移除“\(list.name)”贡献的频道和线路；其他列表中重复存在的内容会保留。"
        }
    }
}
@MainActor final class UIState: ObservableObject {
    @Published var search = ""
    @Published var sidebarCollapsed = false
    @Published var favoritesOnly = UserDefaults.standard.bool(forKey: "favoritesOnly") {
        didSet { UserDefaults.standard.set(favoritesOnly, forKey: "favoritesOnly") }
    }
    @Published var collapsedGroups = Set(UserDefaults.standard.stringArray(forKey: "collapsedGroups") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedGroups).sorted(), forKey: "collapsedGroups") }
    }
    func toggleGroup(_ group: String) {
        if !collapsedGroups.insert(group).inserted { collapsedGroups.remove(group) }
    }
    @Published var address = ""
    @Published var showAddress = false
    @Published var direct = false
    @Published var showImporter = false
    @Published var showListManager = false
    @Published var deletion: LibraryDeletion?
}
struct ContentView: View {
    @StateObject private var library = Library()
    @StateObject private var ui = UIState()
    @StateObject private var programGuide = ProgramGuideStore()
    @ViewState private var sidebarWidth: CGFloat
    private let minimumSidebarWidth: CGFloat = 294
    private let minimumVideoWidth: CGFloat = 460
    private let topBarSpacing: CGFloat = 10
    private let searchWidth: CGFloat = 72 * 1.2 * 1.5
    private let filterWidth: CGFloat = 129.6
    var filtered: [Channel] { library.channels.filter { (!ui.favoritesOnly || library.favorites.contains($0.id)) && (ui.search.isEmpty || $0.name.localizedCaseInsensitiveContains(ui.search) || $0.group.localizedCaseInsensitiveContains(ui.search)) } }

    init() {
        let savedWidth = UserDefaults.standard.double(forKey: "sidebarWidth")
        _sidebarWidth = State(initialValue: savedWidth >= 294 ? CGFloat(savedWidth) : 294)
    }

    private func performDeletion(_ deletion: LibraryDeletion) {
        switch deletion {
        case .channel(let channel): library.deleteChannel(channel)
        case .source(let channel, let source): library.deleteSource(source, from: channel)
        case .group(let group): library.deleteGroup(group)
        case .list(let list): library.deleteList(list)
        }
    }

    private func groupHeader(_ group: String) -> some View {
        Button { ui.toggleGroup(group) } label: {
            HStack(spacing: 7) {
                Image(systemName: ui.collapsedGroups.contains(group) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).frame(width: 12)
                Text(group).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group)
        .accessibilityValue(ui.collapsedGroups.contains(group) ? "已折叠" : "已展开")
        .help(ui.collapsedGroups.contains(group) ? "展开\(group)" : "折叠\(group)")
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.sofaBackground)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("删除分组…", role: .destructive) { ui.deletion = .group(group) }
        }
    }

    private var sidebarGroups: [ChannelListGroup] {
        Dictionary(grouping: filtered, by: \.group).keys.sorted().map { group in
            ChannelListGroup(name: group, visibleChannelCount: ui.collapsedGroups.contains(group) ? 0 : filtered.filter { $0.group == group }.count)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let maximumSidebarWidth = max(minimumSidebarWidth, geometry.size.width - minimumVideoWidth - 1)
            let visibleSidebarWidth = min(max(sidebarWidth, minimumSidebarWidth), maximumSidebarWidth)
            let sidebarHidden = ui.sidebarCollapsed && library.selected != nil
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                    ChannelFilterTabs(favoritesOnly: $ui.favoritesOnly)
                        .frame(width: filterWidth, height: 26)
                    Spacer(minLength: topBarSpacing)
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索", text: $ui.search)
                            .textFieldStyle(.plain).accessibilityLabel("搜索频道或分组")
                        if !ui.search.isEmpty {
                            Button { ui.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("清除搜索")
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: searchWidth)
                    }
                    .padding(.horizontal, 12).padding(.top, 44).padding(.bottom, 10)
                    List {
                    ForEach(Array(Set(filtered.map(\.group))).sorted(), id: \.self) { group in
                        groupHeader(group)
                        if !ui.collapsedGroups.contains(group) {
                            ForEach(filtered.filter { $0.group == group }) { channel in
                                ChannelRow(
                                    channel: channel,
                                    isFavorite: library.favorites.contains(channel.id),
                                    isSelected: library.selected?.id == channel.id,
                                    currentProgram: programGuide.titles[channel.id],
                                    onPlay: { library.play(channel) },
                                    onFavorite: { library.favorite(channel) },
                                    onDeleteSource: { ui.deletion = .source(channel, $0) },
                                    onDelete: { ui.deletion = .channel(channel) }
                                )
                                .equatable()
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(Color.primary.opacity(library.selected?.id == channel.id ? 0.065 : 0))
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    }
                    .listStyle(.plain)
                    .contentMargins(.trailing, 0, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .background(Color.sofaBackground)
                    .background {
                        ChannelListScrollStyle(groups: sidebarGroups, makeHeader: { AnyView(groupHeader($0)) })
                    }
                    .overlay {
                    if library.channels.isEmpty {
                        SidebarEmptyView(
                            "添加你的频道",
                            systemImage: "tv",
                            description: "从菜单栏的“频道”菜单导入列表"
                        )
                    } else if filtered.isEmpty {
                        if ui.favoritesOnly {
                            SidebarEmptyView(
                                ui.search.isEmpty ? "暂无收藏频道" : "收藏中没有匹配的频道",
                                systemImage: "star",
                                description: ui.search.isEmpty ? "点击频道右侧的星标添加收藏" : "试试其他搜索词"
                            )
                        } else {
                            SidebarEmptyView("没有匹配的频道", systemImage: "magnifyingglass")
                        }
                    }
                    }
                    HStack {
                    Text(library.playbackStatus).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(filtered.count) 个频道").fixedSize()
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                }
                .frame(width: visibleSidebarWidth)
                .background(Color.sofaBackground)
                .frame(width: sidebarHidden ? 0 : visibleSidebarWidth, alignment: .leading)
                .clipped()
                .allowsHitTesting(!sidebarHidden)
                .accessibilityHidden(sidebarHidden)
                SidebarResizeHandle(
                    width: Binding(
                        get: { sidebarWidth },
                        set: {
                            sidebarWidth = $0
                            UserDefaults.standard.set(Double($0), forKey: "sidebarWidth")
                        }
                    ),
                    visibleWidth: visibleSidebarWidth,
                    minimumWidth: minimumSidebarWidth,
                    maximumWidth: maximumSidebarWidth
                )
                .frame(width: sidebarHidden ? 0 : 1)
                .opacity(sidebarHidden ? 0 : 1)
                .allowsHitTesting(!sidebarHidden)
                .accessibilityHidden(sidebarHidden)
                Group {
                    if library.selected != nil {
                        VideoStage(library: library, sidebarCollapsed: sidebarHidden) {
                            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                            withAnimation(.easeInOut(duration: duration)) { ui.sidebarCollapsed.toggle() }
                        }
                    }
                    else { EmptyPlaybackView() }
                }
                .frame(minWidth: minimumVideoWidth, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sofaBackground)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.sofaBackground)
        .ignoresSafeArea(.container, edges: .top)
        .background(MainWindowChrome(title: library.selected?.name ?? "沙发电视", onClose: library.stopPlayback).frame(width: 0, height: 0))
        .focusedSceneValue(\.channelLibrary, library)
        .focusedSceneValue(\.channelUI, ui)
        .onAppear { programGuide.setChannels(library.channels) }
        .onChange(of: library.channels) { _, channels in programGuide.setChannels(channels) }
        .onDisappear { programGuide.stop() }
        .onChange(of: library.selected?.id) { _, selected in
            if selected == nil { ui.sidebarCollapsed = false }
        }
        .overlay {
            if library.loading {
                ProgressView("正在加载频道…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $ui.showAddress) {
            VStack(alignment: .leading, spacing: 16) {
                Text(ui.direct ? "打开直播地址" : "导入在线频道列表").font(.title2)
                TextField("https://…", text: $ui.address).textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消") { ui.showAddress = false }
                    Spacer()
                    Button("打开") { ui.showAddress = false; Task { await library.load(ui.address, direct: ui.direct) } }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 460)
        }
        .sheet(isPresented: $ui.showListManager) {
            ChannelListManager(library: library)
        }
        .fileImporter(isPresented: $ui.showImporter, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try library.parse(String(contentsOf: url, encoding: .utf8), as: .file(url))
            } catch { library.error = error.localizedDescription }
        }
        .alert(ui.deletion?.title ?? "确认删除", isPresented: Binding(get: { ui.deletion != nil }, set: { if !$0 { ui.deletion = nil } }), presenting: ui.deletion) { deletion in
            Button("取消", role: .cancel) { ui.deletion = nil }
            Button("删除", role: .destructive) { performDeletion(deletion); ui.deletion = nil }
        } message: { deletion in
            Text(deletion.message)
        }
        .alert("无法打开", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("好") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}
struct ChannelListManager: View {
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @ViewState private var pendingList: ChannelList?

    private func icon(for kind: ChannelList.Kind) -> String {
        switch kind {
        case .builtIn: "shippingbox"
        case .file: "doc.text"
        case .online: "link"
        case .legacy: "tray.full"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("管理频道列表").font(.title2.bold())
            if library.channelLists.isEmpty {
                ContentUnavailableView("没有已导入的列表", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(library.channelLists) { list in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: list.kind)).font(.title3).foregroundStyle(.secondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(list.name).font(.headline)
                            Text(list.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        Text("\(library.channelCount(for: list)) 个频道").foregroundStyle(.secondary)
                        Button(role: .destructive) { pendingList = list } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("删除这份频道列表")
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color.sofaBackground)
            }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 560, height: 380)
        .background(Color.sofaBackground)
        .alert("删除导入列表？", isPresented: Binding(get: { pendingList != nil }, set: { if !$0 { pendingList = nil } }), presenting: pendingList) { list in
            Button("取消", role: .cancel) { pendingList = nil }
            Button("删除", role: .destructive) { library.deleteList(list); pendingList = nil }
        } message: { list in
            Text("将移除“\(list.name)”贡献的频道和线路；其他列表中重复存在的内容会保留。")
        }
    }
}
@main struct SofaTVApp: App {
    @NSApplicationDelegateAdaptor(SofaTVAppDelegate.self) private var appDelegate
    init() {
        // Scope the language preference to this app, including native menus and panels.
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
    }
    var body: some Scene {
        WindowGroup("沙发电视") {
            ContentView().frame(minWidth: 900, minHeight: 560)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .preferredColorScheme(.dark)
        }
            // New installs use this size; MainWindowChrome restores each user's saved frame.
            .defaultSize(width: 1050, height: 589)
            .windowStyle(.hiddenTitleBar)
            .commands { SofaTVCommands() }
    }
}
