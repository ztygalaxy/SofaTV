import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private var licensesController: NSWindowController?
    private weak var licenseText: NSTextView?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 438),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "关于沙发电视"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        buildContents(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContents(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 464)
        ])

        let icon = NSImageView()
        icon.identifier = NSUserInterfaceItemIdentifier("About.icon")
        icon.image = Bundle.main.url(forResource: "Television", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 104),
            icon.heightAnchor.constraint(equalToConstant: 104)
        ])
        stack.addArrangedSubview(icon)

        let name = label("SofaTV / 沙发电视", identifier: "About.name", size: 24, weight: .bold)
        stack.addArrangedSubview(name)
        stack.setCustomSpacing(10, after: name)

        let details = NSStackView()
        details.orientation = .vertical
        details.alignment = .centerX
        details.spacing = 3
        let description = label("坐回沙发，好好看电视。", identifier: "About.description", size: 13)
        details.addArrangedSubview(description)
        let version = label(versionText, identifier: "About.version", size: 13)
        version.textColor = .secondaryLabelColor
        details.addArrangedSubview(version)
        stack.addArrangedSubview(details)
        NSLayoutConstraint.activate([
            details.widthAnchor.constraint(equalTo: stack.widthAnchor),
            description.widthAnchor.constraint(equalTo: details.widthAnchor),
            description.heightAnchor.constraint(equalToConstant: 22)
        ])

        let links = NSStackView()
        links.orientation = .horizontal
        links.spacing = 16
        links.addArrangedSubview(linkButton("项目主页", identifier: "About.project", action: #selector(openProject)))
        links.addArrangedSubview(linkButton("问题反馈", identifier: "About.feedback", action: #selector(openFeedback)))
        links.addArrangedSubview(linkButton("开源许可", identifier: "About.licenses", action: #selector(showLicenses)))
        stack.addArrangedSubview(links)

        let attribution = label("Build by ztygalaxy with his friends.", identifier: "About.attribution", size: 11)
        attribution.textColor = .secondaryLabelColor
        attribution.allowsEditingTextAttributes = true
        let credit = NSMutableAttributedString(string: attribution.stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
        ])
        credit.addAttributes([.link: URL(string: "https://github.com/ztygalaxy")!, .underlineStyle: 0],
                             range: (credit.string as NSString).range(of: "ztygalaxy"))
        credit.addAttributes([.link: URL(string: "https://github.com/ztygalaxy/SofaTV/graphs/contributors")!, .underlineStyle: 0],
                             range: (credit.string as NSString).range(of: "his friends"))
        attribution.attributedStringValue = credit
        stack.addArrangedSubview(attribution)
        stack.setCustomSpacing(18, after: links)

        contentView.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 520, height: max(300, ceil(stack.fittingSize.height) + 56)))
        window.center()
    }

    private func label(
        _ value: String,
        identifier: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.alignment = .center
        label.isSelectable = true
        return label
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func linkButton(_ title: String, identifier: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 13)
        button.contentTintColor = .linkColor
        return button
    }

    @objc private func openProject() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ztygalaxy/SofaTV")!)
    }

    @objc private func openFeedback() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ztygalaxy/SofaTV/issues")!)
    }

    @objc private func showLicenses() {
        if licensesController == nil { makeLicensesWindow() }
        refreshLicenses()
        licensesController?.showWindow(nil)
        licensesController?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeLicensesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "开源许可"
        window.minSize = NSSize(width: 420, height: 300)

        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isRichText = false
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 14, height: 12)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        window.contentView?.addSubview(scroll)
        licenseText = text
        licensesController = NSWindowController(window: window)
        window.center()
    }

    private func refreshLicenses() {
        guard let licenseText else { return }
        var content = "沙发电视采用 GPL-3.0-only 许可，第三方组件和素材保留各自许可。\n\n"
        let titles = [
            "SofaTV-GPL-3.0.txt": "沙发电视开源许可",
            "Channel-Logos-Source.md": "频道台标来源",
            "Channel-Logos-GPL-3.0.txt": "频道台标开源许可"
        ]
        let orderedFiles = ["SofaTV-GPL-3.0.txt", "Channel-Logos-Source.md", "Channel-Logos-GPL-3.0.txt"]
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("Licenses", isDirectory: true) {
            for name in orderedFiles {
                let file = directory.appendingPathComponent(name)
                guard let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty else { continue }
                content += "\(titles[file.lastPathComponent] ?? file.deletingPathExtension().lastPathComponent)\n\n\(text)\n\n"
            }
        }
        if !content.contains("GNU GENERAL PUBLIC LICENSE") {
            content += "此构建中缺少许可文件。"
        }
        let position = licenseText.enclosingScrollView?.contentView.bounds.origin ?? .zero
        licenseText.string = content
        licenseText.enclosingScrollView?.contentView.scroll(to: position)
        licenseText.enclosingScrollView?.reflectScrolledClipView(licenseText.enclosingScrollView!.contentView)
    }
}
