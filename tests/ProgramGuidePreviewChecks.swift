import Foundation

@main struct ProgramGuidePreviewChecks {
    @MainActor private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
    @MainActor private static func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        preconditionFailure("Hover state did not settle")
    }
    @MainActor static func main() async {
        let a = Channel(name: "北京卫视", group: "卫视", url: URL(string: "https://example.com/a")!)
        let b = Channel(name: "江苏卫视", group: "卫视", url: URL(string: "https://example.com/b")!)
        let preview = ProgramGuidePreview(revealDelay: .zero, dismissDelay: .zero)
        preview.hover(a, in: .embedded, inside: true)
        preview.hover(b, in: .embedded, inside: true)
        preview.hover(a, in: .embedded, inside: false)
        await waitFor { preview.channel == b }
        let firstReveal = preview.revealID
        preview.hover(b, in: .embedded, inside: true)
        await settle()
        precondition(preview.revealID == firstReveal, "Staying on a visible channel must not restart the guide")

        preview.hoverPanel(true, in: .embedded)
        preview.hover(b, in: .embedded, inside: false)
        await settle()
        precondition(preview.channel == b && preview.panelHovered)
        preview.hoverPanel(false, in: .embedded)
        await waitFor { preview.channel == nil }

        preview.hover(a, in: .embedded, inside: true)
        await waitFor { preview.channel == a }
        precondition(preview.revealID > firstReveal, "Every new presentation needs its own centering request")
        preview.hover(a, in: .embedded, inside: false)
        preview.hoverPanel(true, in: .embedded)
        await settle()
        precondition(preview.channel == a, "Moving from the row into the schedule must cancel dismissal")

        preview.setPresentation(.fullscreen)
        precondition(preview.channel == nil && !preview.panelHovered)
        preview.hover(a, in: .embedded, inside: true)
        await settle()
        precondition(preview.channel == nil, "The hidden main sidebar must not open a full-screen schedule")
        preview.hover(b, in: .fullscreen, inside: true)
        await waitFor { preview.channel == b }
        preview.hover(b, in: .embedded, inside: false)
        precondition(preview.channel == b)

        preview.setPresentation(nil)
        preview.hover(a, in: .fullscreen, inside: true)
        await settle()
        precondition(preview.channel == nil, "Mini mode must disable both guide entry points")
        preview.setPresentation(.embedded)
        preview.hover(a, in: .embedded, inside: true)
        preview.dismiss()
        await settle()
        precondition(preview.channel == nil, "A pending hover must not reopen a dismissed panel")
        preview.acceptsHover = false
        preview.hover(a, in: .embedded, inside: true)
        preview.hoverPanel(true, in: .embedded)
        await settle()
        precondition(preview.channel == nil && !preview.panelHovered, "Closing sidebars must ignore hover events from moving rows")
        preview.acceptsHover = true
        preview.hover(a, in: .embedded, inside: true)
        await waitFor { preview.channel == a }
        print("Guide hover passed: rapid row changes, row-to-panel handoff, stale exits, full-screen/main isolation, mini mode, and cancellation")
    }
}
