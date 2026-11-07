import AppKit

@MainActor
struct UpdateMarkdownTests {
    func run() throws {
        let markdown = """
        ### 新功能

        - **节目单预览**：悬停频道查看排期。
        - 使用 `Esc` 关闭，查看[发布页](https://github.com/ztygalaxy/SofaTV/releases)。

        ### 优化与修复

        1. *第一项*
        2. 第二项
        """
        let rendered = UpdateNotesMarkdown.render(markdown)
        let text = rendered.string as NSString
        check(!text.contains("###") && !text.contains("**") && !text.contains("`"))
        check(text.contains("新功能\n•\t节目单预览"))
        check(text.contains("\n•\t使用 Esc"))
        check(text.contains("1.\t第一项\n2.\t第二项"))
        func attributes(_ value: String) -> [NSAttributedString.Key: Any] {
            let range = text.range(of: value)
            check(range.location != NSNotFound)
            return rendered.attributes(at: range.location, effectiveRange: nil)
        }
        let headingFont = try unwrap(attributes("新功能")[.font] as? NSFont)
        let bodyFont = try unwrap(attributes("悬停频道")[.font] as? NSFont)
        let boldFont = try unwrap(attributes("节目单预览")[.font] as? NSFont)
        let italicFont = try unwrap(attributes("第一项")[.font] as? NSFont)
        check(headingFont.pointSize > bodyFont.pointSize)
        check(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))
        check(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        check(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))
        check(attributes("Esc")[.backgroundColor] != nil)
        check((attributes("发布页")[.link] as? URL)?.absoluteString == "https://github.com/ztygalaxy/SofaTV/releases")
        let listStyle = try unwrap(attributes("节目单预览")[.paragraphStyle] as? NSParagraphStyle)
        check(listStyle.headIndent > listStyle.firstLineHeadIndent)

        let view = UpdateNotesView(notes: markdown, width: 240)
        let document = try unwrap(view.documentView as? NSTextView)
        check(document.isRichText && document.isSelectable && !document.isEditable)
        check(document.string == rendered.string)
        let long = UpdateNotesView(notes: Array(repeating: markdown, count: 4).joined(separator: "\n\n"), width: 240)
        check(long.visibleLineCount == 15)
        check(long.documentView!.frame.height > long.frame.height)

        let nested = UpdateNotesMarkdown.render("- 第一层\n  - 第二层\n- 另一个项目")
        check(nested.string.components(separatedBy: "•\t").count == 4)
        let plain = UpdateNotesView(notes: "原来的纯文本说明\n第二行", width: 512)
        check(plain.visibleLineCount == 2)
        print("Markdown update notes passed: headings, list boundaries/indentation, bold, italic, code, links and 15-line scrolling")
    }
}
