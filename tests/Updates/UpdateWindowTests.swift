import AppKit

@MainActor
struct UpdateWindowTests {
    func testReleaseNotesAdaptToWrappedLinesAndCapAtFifteen() async {
        _ = NSApplication.shared
        let short = UpdateNotesView(notes: "第一行\n第二行", width: 512)
        let fifteen = UpdateNotesView(notes: Array(repeating: "更新内容", count: 15).joined(separator: "\n"), width: 512)
        let long = UpdateNotesView(notes: Array(repeating: "更新内容", count: 30).joined(separator: "\n"), width: 512)
        let wrapped = UpdateNotesView(notes: String(repeating: "很长的更新说明需要按实际换行计算高度。", count: 100), width: 512)
        check(short.visibleLineCount == 2)
        check(fifteen.visibleLineCount == 15)
        check(long.visibleLineCount == 15)
        check(wrapped.visibleLineCount == 15)
        check(short.frame.height < fifteen.frame.height)
        check(long.frame.height == fifteen.frame.height)
        check(wrapped.frame.height == fifteen.frame.height)
        check(long.documentView!.frame.height > long.frame.height)
        check(short.documentView!.frame.height <= short.frame.height)
    }

    func testButtonsAlignAndSkipPersistsWithoutModalSession() async throws {
        _ = NSApplication.shared
        let name = "SofaTV.UpdateWindowTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let update = VerifiedUpdate(version: SemanticVersion("0.0.4")!, notes: "功能上新\n• 完整节目单，悬停频道即可查看\n• 下载并安装更新\n\n优化与修复\n• 启动时静默检查更新，观看直播时不打扰",
                                    asset: UpdateAsset(name: "test.zip", sha256: String(repeating: "a", count: 64)),
                                    downloadURL: URL(string: "https://example.com/test.zip")!, releaseURL: URL(string: "https://example.com")!)
        let controller = UpdateWindowController(update: update, current: SemanticVersion("0.0.3")!, defaults: defaults)
        let window = try unwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        let content = try unwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let buttons = descendants(content).compactMap { $0 as? NSButton }
        let skip = try unwrap(buttons.first { $0.title == "跳过此版本" })
        let later = try unwrap(buttons.first { $0.title == "稍后" })
        let install = try unwrap(buttons.first { $0.title == "下载并安装" })
        let skipRect = skip.convert(skip.bounds, to: content)
        let laterRect = later.convert(later.bounds, to: content)
        // NSStackView aligns alignment rectangles. Native bezel outsets differ
        // between macOS releases and between bordered/borderless buttons.
        func alignmentRect(_ button: NSButton) -> NSRect {
            button.superview!.convert(button.alignmentRect(forFrame: button.frame), to: content)
        }
        let skipAlignment = alignmentRect(skip)
        let laterAlignment = alignmentRect(later)
        let installAlignment = alignmentRect(install)
        check(skipRect.maxX + 80 < laterRect.minX)
        check(abs(skipAlignment.midY - laterAlignment.midY) < 1)
        check(abs(laterAlignment.midY - installAlignment.midY) < 1)
        check(abs(content.bounds.maxX - installAlignment.maxX - 24) < 1)
        check(NSApp.modalWindow == nil && window.sheetParent == nil)
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/sofatv-update-preview.png"))
        }
        skip.performClick(nil)
        check(defaults.string(forKey: AutomaticUpdateCheck.skippedVersionKey) == "0.0.4")
        check(NSApp.modalWindow == nil)
    }
}
