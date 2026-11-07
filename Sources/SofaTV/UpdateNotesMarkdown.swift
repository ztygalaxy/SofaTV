import AppKit

@MainActor
enum UpdateNotesMarkdown {
    static func render(_ source: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: source, options: .init(failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(source)
        let result = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        var previousListItem: Int?
        var blockFont = NSFont.systemFont(ofSize: 13)
        var blockStyle = NSMutableParagraphStyle()
        var blockIsCode = false

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            if result.length == 0 || block != previousBlock {
                let hasPrecedingContent = result.length > 0
                if hasPrecedingContent, !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n", attributes: [.font: blockFont, .paragraphStyle: blockStyle]))
                }
                blockFont = .systemFont(ofSize: 13)
                blockStyle = NSMutableParagraphStyle()
                blockStyle.paragraphSpacing = 6
                blockIsCode = false
                var listItem: PresentationIntent.IntentType?
                var listDepth = 0
                var ordered = false

                for component in components {
                    switch component.kind {
                    case .header(let level):
                        blockFont = .boldSystemFont(ofSize: level == 1 ? 19 : level == 2 ? 17 : 15)
                        blockStyle.paragraphSpacingBefore = hasPrecedingContent ? 8 : 0
                        blockStyle.paragraphSpacing = 8
                    case .codeBlock:
                        blockIsCode = true
                    case .listItem:
                        if listItem == nil { listItem = component }
                        listDepth += 1
                    case .orderedList:
                        if listDepth == 1 { ordered = true }
                    case .blockQuote:
                        blockStyle.headIndent += 14
                        blockStyle.firstLineHeadIndent += 14
                    default: break
                    }
                }

                if let listItem, case .listItem(let ordinal) = listItem.kind {
                    blockStyle.firstLineHeadIndent = CGFloat(listDepth - 1) * 18
                    blockStyle.headIndent = CGFloat(listDepth) * 18
                    blockStyle.tabStops = [NSTextTab(textAlignment: .left, location: blockStyle.headIndent)]
                    blockStyle.paragraphSpacing = 4
                    if listItem.identity != previousListItem {
                        result.append(NSAttributedString(string: ordered ? "\(ordinal).\t" : "•\t", attributes: [
                            .font: blockFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: blockStyle
                        ]))
                    } else {
                        blockStyle.firstLineHeadIndent = blockStyle.headIndent
                    }
                }
                previousBlock = block
                previousListItem = listItem?.identity
            }

            let inline = run.inlinePresentationIntent ?? []
            var font = blockIsCode || inline.contains(.code) ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : blockFont
            if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: blockStyle]
            if blockIsCode || inline.contains(.code) { attributes[.backgroundColor] = NSColor.quaternaryLabelColor }
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            // Keep source line breaks without creating extra Markdown paragraphs.
            let content = inline.contains(.softBreak) || inline.contains(.lineBreak) ? "\u{2028}" : String(parsed[run.range].characters)
            result.append(NSAttributedString(string: content, attributes: attributes))
        }
        return result
    }
}
