import Foundation
import Combine

/// Hover state is independent of the channel library, so browsing does not rebuild its rows.
@MainActor final class ProgramGuidePreview: ObservableObject {
    enum Presentation: Equatable, Sendable { case embedded, fullscreen }
    @Published private(set) var channel: Channel?
    @Published private(set) var revealID = 0
    @Published private(set) var panelHovered = false
    var acceptsHover = true
    private(set) var presentation: Presentation? = .embedded
    @Published private(set) var hoveredRow: Channel.Identity?
    private var revealTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private let revealDelay: Duration
    private let dismissDelay: Duration
    private var dismissalCompletion: (() -> Void)?

    init(revealDelay: Duration = .milliseconds(180), dismissDelay: Duration = .milliseconds(250)) {
        self.revealDelay = revealDelay; self.dismissDelay = dismissDelay
    }
    deinit { revealTask?.cancel(); dismissTask?.cancel() }

    func setPresentation(_ value: Presentation?) {
        guard presentation != value else { return }
        dismissalCompletion = nil
        presentation = value
        dismiss()
    }

    func hover(_ channel: Channel, in presentation: Presentation, inside: Bool) {
        guard acceptsHover, self.presentation == presentation else { return }
        if inside {
            guard dismissalCompletion == nil else { return }
            hoveredRow = channel.identity
            dismissTask?.cancel(); revealTask?.cancel()
            guard self.channel != channel else { return }
            revealTask = Task { [weak self, revealDelay] in
                do { try await Task.sleep(for: revealDelay) } catch { return }
                guard let self, self.hoveredRow == channel.identity else { return }
                self.revealID += 1
                self.channel = channel
            }
        } else if hoveredRow == channel.identity {
            hoveredRow = nil
            revealTask?.cancel()
            scheduleDismiss()
        }
    }

    func hoverPanel(_ inside: Bool, in presentation: Presentation) {
        guard acceptsHover, self.presentation == presentation else { return }
        panelHovered = inside
        if inside { dismissTask?.cancel() }
        else { scheduleDismiss() }
    }

    func dismiss(completion: (() -> Void)? = nil) {
        revealTask?.cancel(); dismissTask?.cancel()
        hoveredRow = nil; panelHovered = false
        guard channel != nil else { completion?(); return }
        dismissalCompletion = completion
        channel = nil
    }

    func didFinishDismissal(in presentation: Presentation) {
        guard self.presentation == presentation else { return }
        let completion = dismissalCompletion
        dismissalCompletion = nil
        completion?()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard hoveredRow == nil, !panelHovered, channel != nil else { return }
        dismissTask = Task { [weak self, dismissDelay] in
            do { try await Task.sleep(for: dismissDelay) } catch { return }
            guard let self, self.hoveredRow == nil, !self.panelHovered else { return }
            self.dismiss()
        }
    }
}
