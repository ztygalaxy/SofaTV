import AppKit

@MainActor
final class UpdateNotesView: NSScrollView {
    let visibleLineCount: Int

    init(notes: String, width: CGFloat) {
        let inset = NSSize(width: 12, height: 10)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        text.isEditable = false
        text.isRichText = true
        text.isSelectable = true
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.drawsBackground = false
        text.textContainerInset = inset
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.containerSize = NSSize(width: width - inset.width * 2, height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(UpdateNotesMarkdown.render(notes))
        let layout = text.layoutManager!
        let container = text.textContainer!
        layout.ensureLayout(for: container)
        var lines = 0
        var visibleHeight: CGFloat = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, _, _ in
            lines += 1
            if lines <= 15 { visibleHeight = rect.maxY }
        }
        visibleLineCount = min(lines, 15)
        let documentHeight = ceil(layout.usedRect(for: container).height + inset.height * 2)
        let height = ceil(visibleHeight + inset.height * 2)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScroller?.controlSize = .small
        text.setFrameSize(NSSize(width: width, height: documentHeight))
        documentView = text
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let update: VerifiedUpdate
    private let defaults: UserDefaults
    private let skipButton = NSButton(title: "跳过此版本", target: nil, action: nil)
    private let laterButton = NSButton(title: "稍后", target: nil, action: nil)
    private let installButton = NSButton(title: "下载并安装", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let status = NSTextField(labelWithString: "")
    private let progressStack = NSStackView()
    private var downloadTask: Task<Void, Never>?
    private var installing = false

    init(update: VerifiedUpdate, current: SemanticVersion, defaults: UserDefaults = .standard) {
        self.update = update
        self.defaults = defaults
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "软件更新"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        window.delegate = self
        buildContent(current: current)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent(current: SemanticVersion) {
        guard let window, let content = window.contentView else { return }
        let width: CGFloat = 512
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.widthAnchor.constraint(equalToConstant: width)
        ])
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(icon)

        let title = NSTextField(labelWithString: "发现沙发电视新版本")
        title.font = .boldSystemFont(ofSize: 17)
        let detail = NSTextField(wrappingLabelWithString: "沙发电视 \(update.version) 已发布，你正在使用 \(current)。")
        detail.font = .systemFont(ofSize: 13)
        let heading = NSStackView(views: [title, detail])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 8
        heading.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(heading)

        if !update.notes.isEmpty {
            let label = NSTextField(labelWithString: "更新说明")
            label.font = .boldSystemFont(ofSize: 13)
            let notes = NSStackView(views: [label, UpdateNotesView(notes: update.notes, width: width)])
            notes.orientation = .vertical
            notes.alignment = .leading
            notes.spacing = 8
            stack.addArrangedSubview(notes)
        }

        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        progress.widthAnchor.constraint(equalToConstant: width).isActive = true
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 8
        progressStack.addArrangedSubview(progress)
        progressStack.addArrangedSubview(status)
        progressStack.isHidden = true
        stack.addArrangedSubview(progressStack)

        skipButton.target = self
        skipButton.action = #selector(skipVersion)
        skipButton.isBordered = false
        skipButton.contentTintColor = .secondaryLabelColor
        laterButton.target = self
        laterButton.action = #selector(later)
        laterButton.bezelStyle = .rounded
        laterButton.keyEquivalent = "\u{1b}"
        installButton.target = self
        installButton.action = #selector(install)
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [skipButton, spacer, laterButton, installButton])
        buttons.spacing = 10
        buttons.alignment = .centerY
        buttons.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(buttons)
        content.layoutSubtreeIfNeeded()
        fitWindow()
        window.center()
    }

    private func fitWindow() {
        guard let content = window?.contentView, let stack = content.subviews.first as? NSStackView else { return }
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 560, height: stack.fittingSize.height + 40))
    }

    @objc private func skipVersion() {
        defaults.set(update.version.description, forKey: AutomaticUpdateCheck.skippedVersionKey)
        close()
    }

    @objc private func later() {
        downloadTask?.cancel()
        close()
    }

    @objc private func install() {
        guard downloadTask == nil else { return }
        skipButton.isEnabled = false
        installButton.isEnabled = false
        laterButton.title = "取消下载"
        progressStack.isHidden = false
        status.stringValue = "正在下载更新…"
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        fitWindow()
        downloadTask = Task { [weak self] in await self?.downloadAndInstall() }
    }

    private func downloadAndInstall() async {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("SofaTV-Update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let source = try await UpdateDownload.prepare(update, workspace: workspace) { [weak self] fraction in
                guard let self, !installing, downloadTask?.isCancelled == false else { return }
                progress.isIndeterminate = fraction == nil
                if let fraction {
                    progress.stopAnimation(nil)
                    progress.doubleValue = fraction
                    status.stringValue = fraction < 1 ? "正在下载更新… \(Int(fraction * 100))%" : "正在校验更新包…"
                }
            }
            try Task.checkCancellation()
            installing = true
            laterButton.isEnabled = false
            window?.standardWindowButton(.closeButton)?.isEnabled = false
            status.stringValue = "正在准备安装，随后将重新打开沙发电视…"
            try await UpdateInstaller.launch(source: source, version: update.version.description, workspace: workspace)
        } catch {
            try? FileManager.default.removeItem(at: workspace)
            if !Task.isCancelled {
                status.stringValue = error.localizedDescription
                progressStack.isHidden = true
                let alert = NSAlert()
                alert.messageText = "下载或安装更新失败"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "好")
                AppWindows.shared.present(alert)
            }
            downloadTask = nil
            installing = false
            skipButton.isEnabled = true
            laterButton.isEnabled = true
            laterButton.title = "稍后"
            installButton.isEnabled = true
            window?.standardWindowButton(.closeButton)?.isEnabled = true
            fitWindow()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !installing }

    func windowWillClose(_ notification: Notification) {
        downloadTask?.cancel()
        onClose?()
    }
}
