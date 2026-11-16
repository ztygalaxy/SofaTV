import AppKit
import SwiftUI

@MainActor enum OnboardingWindow {
    private static let id = "onboarding"
    private static let shownKey = "hasShownOnboarding"
    fileprivate static let bottomInset: CGFloat = 8

    static func shouldShowOnLaunch(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: shownKey) &&
            defaults.object(forKey: "channel-lists") == nil &&
            defaults.object(forKey: "channels") == nil &&
            defaults.object(forKey: "mainWindowFrame") == nil
    }

    static func showOnce() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        show()
    }

    static func show() {
        UserDefaults.standard.set(true, forKey: shownKey)
        let size = NSSize(width: 546, height: 402 + bottomInset)
        AppWindows.shared.show(id: id, title: "新手引导", size: size, sizingOptions: [], configureWindow: { window in
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            // Full-size content also occupies the space AppKit reserves for a title bar.
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
        }, content: OnboardingView(onClose: {
            AppWindows.shared.close(id: id)
        }))
    }
}

private enum OnboardingPage: Int, CaseIterable {
    case welcome, search, reminders, miniPlayer, dock

    var title: String.LocalizationValue {
        switch self {
        case .welcome: "欢迎来到沙发电视"
        case .search: "看你想看的节目"
        case .reminders: "坐等好戏开场"
        case .miniPlayer: "边做事，边看电视"
        case .dock: "频道一目了然"
        }
    }

    var detail: String.LocalizationValue {
        switch self {
        case .welcome: "坐回沙发，好好看电视。添加频道列表后，选择喜爱的频道，好戏马上开始。"
        case .search: "在侧边栏搜索频道或者节目名称，点击结果跳转换台。"
        case .reminders: "点击节目单右侧的铃铛获取节目开播提醒。"
        case .miniPlayer: "点击播放器右上角的图钉，切换为置顶小窗，继续做事。"
        case .dock: "Dock 栏中即时展示当前频道，一眼便知。"
        }
    }
}

private struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var page: OnboardingPage = .welcome
    @ViewState private var choosingSource = false
    @ViewState private var slideOffset: CGFloat = 12
    let onClose: () -> Void

    var body: some View {
        Group {
            if choosingSource { sourcePicker }
            else { guide }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, OnboardingWindow.bottomInset)
        .background(Color.sofaBackground)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var guide: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    artwork
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .accessibilityHidden(page != .dock)
                    caption
                }
                .id(page)
                .transition(.asymmetric(insertion: .offset(x: slideOffset).combined(with: .opacity), removal: .opacity))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { value in
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height) * 1.4 else { return }
                move(by: width < 0 ? 1 : -1)
            })
            .background(OnboardingNavigationInput(onTurn: move(by:)))

            ZStack {
                HStack {
                    Button(L10n.text("跳过"), action: onClose)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    actionButton(page == .dock ? "添加频道" : "下一页", prominent: true) {
                        if page == .dock { choosingSource = true }
                        else { move(by: 1) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                HStack(spacing: 0) {
                    ForEach(OnboardingPage.allCases, id: \.self) { target in
                        Button { move(to: target) } label: {
                            Capsule()
                                .fill(target == page ? Color.sofaAccent : Color.secondary.opacity(0.68))
                                .frame(width: target == page ? 13 : 7, height: 7)
                                .frame(width: 30, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text(target.title))
                        .accessibilityAddTraits(target == page ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
        }
    }

    private var caption: some View {
        VStack(spacing: 0) {
            Text(L10n.text(page.title))
                .font(.system(size: 24, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(page.detail))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: page == .welcome ? 470 : 425)
                .padding(.top, 8)
            if page == .welcome {
                Button { choosingSource = true } label: {
                    HStack(spacing: 4) {
                        Text(L10n.text("直接添加频道"))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .frame(height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .tint(.sofaAccent)
                .padding(.top, 3)
            }
        }
        .padding(.top, 16)
        .frame(height: 104, alignment: .top)
    }

    @ViewBuilder private var artwork: some View {
        switch page {
        case .welcome:
            AppLogoView(size: 124)
                .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EllipticalGradient(stops: [
                    .init(color: .sofaAccent.opacity(0.29), location: 0),
                    .init(color: .sofaAccent.opacity(0.13), location: 0.55),
                    .init(color: .clear, location: 1)
                ], center: UnitPoint(x: 0.5, y: 0.53), endRadiusFraction: 0.47))
        case .search: screenshot("Search")
        case .reminders: screenshot("Reservations")
        case .miniPlayer: screenshot("MiniPlayer")
        case .dock:
            HStack(spacing: 48) {
                dockIcon(L10n.text("未播放"), badge: nil)
                dockIcon(L10n.text("播放中"), badge: ChannelLogoStore.image(for: "浙江卫视"))
            }
        }
    }

    private func screenshot(_ name: String) -> some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Onboarding"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .clipShape(.rect(cornerRadius: 8))
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .white, location: 0.86),
                            .init(color: .white.opacity(0.86), location: 0.93),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }
        }
    }

    private func dockIcon(_ label: String, badge: NSImage?) -> some View {
        VStack(spacing: 5) {
            Group {
                let icon = NSApp.applicationIconImage
                if let icon, let badge {
                    OnboardingDockBadge(icon: icon, badge: badge)
                } else if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                }
            }
            .frame(width: 128, height: 128)
            Text(label).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 28)).foregroundStyle(Color.sofaAccent)
                    .accessibilityHidden(true)
                Text(L10n.text("添加频道")).font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text("导入在线列表地址，或从 Mac 选择 M3U / TXT 文件。"))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    actionButton("导入在线列表…", prominent: true) {
                        onClose()
                        Library.shared.showAddressWindow(direct: false)
                    }
                    .keyboardShortcut(.defaultAction)
                    actionButton("导入频道文件…", prominent: false) {
                        onClose()
                        Library.shared.importChannels()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(L10n.text("重新查看引导")) {
                page = .welcome
                choosingSource = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .frame(height: 60)
        }
    }

    private func actionButton(_ title: String.LocalizationValue, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.text(title))
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .foregroundStyle(prominent ? Color.black.opacity(0.84) : Color.primary)
                .background(prominent ? Color(red: 0.43, green: 0.84, blue: 0.80) : Color.primary.opacity(0.08),
                            in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func move(by direction: Int) {
        if let target = OnboardingPage(rawValue: page.rawValue + direction) { move(to: target) }
    }

    private func move(to target: OnboardingPage) {
        guard target != page else { return }
        slideOffset = target.rawValue > page.rawValue ? 12 : -12
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { page = target }
    }
}

private struct OnboardingDockBadge: NSViewRepresentable {
    let icon: NSImage
    let badge: NSImage

    func makeNSView(context: Context) -> DockIconBadgeView {
        DockIconBadgeView(frame: .zero, baseImage: icon, badgeImage: badge)
    }

    func updateNSView(_ view: DockIconBadgeView, context: Context) {}
}

private struct OnboardingNavigationInput: NSViewRepresentable {
    let onTurn: (Int) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) { view.onTurn = onTurn }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.stopMonitoring() }

    final class InputView: NSView {
        var onTurn: ((Int) -> Void)?
        private var monitor: Any?
        private var distance: CGFloat = 0
        private var didTurn = false
        private var lastScroll: TimeInterval = -.infinity

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.isKeyWindow else { return event }
                return self.handle(event)
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .keyDown {
                guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                switch event.keyCode {
                case 123: onTurn?(-1)
                case 124: onTurn?(1)
                default: return event
                }
                return nil
            }

            guard event.momentumPhase.isEmpty else { return event }
            let finished = !event.phase.intersection([.ended, .cancelled]).isEmpty
            if finished || event.phase.contains(.began) || (event.phase.isEmpty && event.timestamp - lastScroll > 0.25) {
                didTurn = false
                distance = 0
            }
            guard !finished, bounds.contains(convert(event.locationInWindow, from: nil)),
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            lastScroll = event.timestamp
            if !didTurn {
                distance += event.scrollingDeltaX
                if abs(distance) >= (event.hasPreciseScrollingDeltas ? 36 : 1) {
                    didTurn = true
                    onTurn?(distance < 0 ? 1 : -1)
                }
            }
            return nil
        }
    }
}
