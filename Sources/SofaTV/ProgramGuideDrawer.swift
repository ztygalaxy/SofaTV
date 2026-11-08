import SwiftUI
import AppKit
import Combine

struct ProgramGuideOverlay: NSViewRepresentable {
    let preview: ProgramGuidePreview
    let store: ProgramGuideStore
    let presentation: ProgramGuidePreview.Presentation
    let playingChannel: Channel?

    func makeNSView(context: Context) -> ProgramGuideOverlayHost {
        ProgramGuideOverlayHost(preview: preview, store: store, presentation: presentation, playingChannel: playingChannel)
    }
    func updateNSView(_ view: ProgramGuideOverlayHost, context: Context) { view.playingChannel = playingChannel }
}

private struct ProgramGuideDrawer: View {
    let channel: Channel
    @ObservedObject var store: ProgramGuideStore
    let fullscreen: Bool
    let isPlayingChannel: Bool
    let canReturnToCurrent: Bool
    let returnToCurrent: () -> Void
    private var scale: CGFloat { fullscreen ? 1.3 : 1 }

    var body: some View {
        let now = store.currentDate
        let schedule = store.schedule(for: channel)
        let today = Calendar.current.startOfDay(for: now)
        let programs = schedule.programs(on: today)
        VStack(spacing: 0) {
            VStack(spacing: 4 * scale) {
                ChannelLogoView(channelName: channel.name, isSelected: false, contentScale: scale * 0.72)
                Text(channel.displayName).font(.system(size: 14 * scale, weight: .semibold)).lineLimit(1)
                Text("节目单").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14 * scale)
            Divider().opacity(0.4)
            if programs.isEmpty {
                VStack(spacing: 10 * scale) {
                    Image(systemName: "calendar").font(.system(size: 26 * scale)).foregroundStyle(.secondary)
                    Text("暂无节目单").font(.system(size: 14 * scale, weight: .medium))
                    Text("暂未找到这一天的节目信息").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgramGuideScrollView(programs: programs, now: now, fullscreen: fullscreen,
                                       isPlayingChannel: isPlayingChannel, revision: store.scheduleRevision,
                                       channel: channel, reminders: store.reminders)
            }
            HStack {
                if let reminders = store.reminders {
                    Button("节目预约…") { ProgramReminderWindow.show(reminders) }.buttonStyle(.plain)
                }
                Spacer()
                Button("回到当前", action: returnToCurrent)
                    .buttonStyle(.plain)
                    .disabled(!canReturnToCurrent)
                    .help("定位正在播放的频道及当前节目")
            }
            .font(.system(size: 11 * scale))
            .padding(.horizontal, 14 * scale)
            .frame(height: (fullscreen ? 36 : 32) * scale)
        }
        .background(ProgramGuideGlass(fullscreen: fullscreen))
        .overlay(alignment: .trailing) { Color.white.opacity(0.09).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(channel.displayName)节目单")
    }

}

private struct ProgramGuideRow: View {
    let program: ProgramGuide.CurrentProgram
    let now: Date
    let fullscreen: Bool
    let isPlayingChannel: Bool
    let highlight: ProgramGuide.Schedule.Highlight?
    let channel: Channel
    let reminders: ProgramReminderStore?
    private var scale: CGFloat { fullscreen ? 1.3 : 1 }
    private var currentHighlight: Color { isPlayingChannel ? .sofaAccent : .white }

    var body: some View {
        let highlighted = highlight?.program == program
        let past = program.end <= now
        return VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 6 * scale) {
                Text(program.timeRange()).monospacedDigit().foregroundStyle(highlighted ? .primary : .secondary)
                Spacer(minLength: 0)
                if highlighted, let highlight {
                    Text(highlight.badge(isPlayingChannel: isPlayingChannel)).foregroundStyle(currentHighlight)
                        .font(.system(size: 10 * scale, weight: .medium))
                }
                if let reminders {
                    ProgramReminderButton(channel: channel, program: program, now: now, scale: scale, store: reminders)
                }
            }
            .font(.system(size: 11 * scale))
            .frame(minHeight: reminders == nil ? nil : 24 * scale)
            Text(program.title).font(.system(size: 14 * scale, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(past ? .secondary : .primary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16 * scale).padding(.vertical, 13 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(highlighted ? (fullscreen ? 0.07 : 0.10) : 0))
        .overlay(alignment: .leading) { if highlighted { currentHighlight.frame(width: 3) } }
        .accessibilityElement(children: .contain)
    }
}

private struct ProgramGuideScrollView: NSViewRepresentable {
    let programs: [ProgramGuide.CurrentProgram]
    let now: Date
    let fullscreen: Bool
    let isPlayingChannel: Bool
    let revision: Int
    let channel: Channel
    let reminders: ProgramReminderStore?

    func makeNSView(context: Context) -> ScheduleScrollView { ScheduleScrollView() }
    func updateNSView(_ scroll: ScheduleScrollView, context: Context) { scroll.update(self) }

    final class ScheduleScrollView: AppScrollView {
        private final class Document: NSView { override var isFlipped: Bool { true } }
        private let rows = Document()
        private var hosts: [NSHostingView<AnyView>] = []
        private var configuration: ProgramGuideScrollView?
        private var viewportSize: NSSize = .zero
        private var rowsNeedLayout = false
        private var centreRequested = true

        init() {
            super.init(frame: .zero)
            drawsBackground = false; borderType = .noBorder
            horizontalScrollElasticity = .none
            documentView = rows
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(_ value: ProgramGuideScrollView) {
            if let previous = configuration {
                centreRequested = centreRequested || previous.programs != value.programs || previous.revision != value.revision
            }
            configuration = value
            while hosts.count > value.programs.count { hosts.removeLast().removeFromSuperview() }
            while hosts.count < value.programs.count {
                let host = NSHostingView(rootView: AnyView(EmptyView()))
                host.sizingOptions = [.intrinsicContentSize]
                rows.addSubview(host); hosts.append(host)
            }
            rowsNeedLayout = true
            needsLayout = true
        }
        override func layout() {
            super.layout()
            let size = contentView.bounds.size
            guard let configuration, size.width > 0, size.height > 0,
                  rowsNeedLayout || viewportSize != size else { return }
            centreRequested = centreRequested || viewportSize != size
            rowsNeedLayout = false; viewportSize = size
            var y: CGFloat = 0
            let highlight = ProgramGuide.Schedule.highlight(in: configuration.programs, at: configuration.now)
            for (host, program) in zip(hosts, configuration.programs) {
                host.rootView = AnyView(
                    ProgramGuideRow(program: program, now: configuration.now, fullscreen: configuration.fullscreen,
                                    isPlayingChannel: configuration.isPlayingChannel, highlight: highlight,
                                    channel: configuration.channel, reminders: configuration.reminders)
                        .frame(width: size.width)
                        .fixedSize(horizontal: false, vertical: true)
                        .preferredColorScheme(.dark)
                )
                host.layoutSubtreeIfNeeded()
                let height = ceil(host.fittingSize.height)
                host.frame = NSRect(x: 0, y: y, width: size.width, height: height)
                y += height
            }
            rows.frame = NSRect(x: 0, y: 0, width: size.width, height: y)
            if centreRequested,
               let target = ProgramGuide.Schedule.scrollTarget(in: configuration.programs, at: configuration.now),
               let index = configuration.programs.firstIndex(of: target) {
                let offset = min(max(0, hosts[index].frame.midY - size.height / 2), max(0, y - size.height))
                contentView.scroll(to: NSPoint(x: 0, y: offset))
                reflectScrolledClipView(contentView)
                centreRequested = false
            }
        }
    }
}

private struct ProgramGuideGlass: NSViewRepresentable {
    final class GlassView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    let fullscreen: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .underWindowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // Only fade the material: the programme text remains fully legible.
        view.alphaValue = fullscreen ? 0.62 : 0.92
    }
}

/// Move a fixed-size pane as a unit, using the same native animation as the channel sidebar.
final class ProgramGuideOverlayHost: NSView {
    var isInteractive = true
    var playingChannel: Channel? {
        didSet {
            guard playingChannel?.identity != oldValue?.identity, visible, let channel = preview.channel else { return }
            setContent(for: channel)
        }
    }
    private let preview: ProgramGuidePreview
    private let store: ProgramGuideStore
    private let presentation: ProgramGuidePreview.Presentation
    private let pane = NSHostingView(rootView: AnyView(EmptyView()))
    private var observation: AnyCancellable?
    private var visible = false
    private var animationID = 0

    init(preview: ProgramGuidePreview, store: ProgramGuideStore, presentation: ProgramGuidePreview.Presentation,
         playingChannel: Channel? = nil) {
        self.preview = preview; self.store = store; self.presentation = presentation
        self.playingChannel = playingChannel
        super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        pane.sizingOptions = []; pane.isHidden = true
        pane.safeAreaRegions = []
        addSubview(pane)
        observation = preview.$channel.sink { [weak self] channel in self?.show(channel) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if pane.frame.size != bounds.size || pane.isHidden {
            pane.frame = paneFrame(visible: visible)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, visible, bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    private func paneFrame(visible: Bool) -> NSRect {
        NSRect(x: visible ? 0 : -bounds.width, y: 0, width: bounds.width, height: bounds.height)
    }
    func returnToCurrent() {
        guard visible, let playingChannel else { return }
        preview.showPlayingChannel(playingChannel, in: presentation)
    }
    private func setContent(for channel: Channel) {
        pane.rootView = AnyView(
            ProgramGuideDrawer(channel: channel, store: store, fullscreen: presentation == .fullscreen,
                               isPlayingChannel: playingChannel?.identity == channel.identity,
                               canReturnToCurrent: playingChannel != nil,
                               returnToCurrent: { [weak self] in self?.returnToCurrent() })
                .id(preview.revealID)
                .onHover { [weak preview, presentation] in preview?.hoverPanel($0, in: presentation) }
                .preferredColorScheme(.dark)
        )
    }
    private func show(_ channel: Channel?) {
        let active = preview.presentation == presentation
        if active, let channel { setContent(for: channel) }
        let nextVisible = active && channel != nil
        guard visible != nextVisible else { return }
        if nextVisible {
            pane.frame = paneFrame(visible: false)
            pane.isHidden = false
        }
        visible = nextVisible
        animationID += 1
        let currentAnimation = animationID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = active && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pane.animator().frame = paneFrame(visible: nextVisible)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.animationID == currentAnimation, !self.visible else { return }
                self.pane.isHidden = true
                self.pane.rootView = AnyView(EmptyView())
                self.preview.didFinishDismissal(in: self.presentation)
            }
        }
    }
}
