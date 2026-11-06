import Foundation

/// A channel generation owns both attempts; only a rendered frame can win.
struct PlaybackRace {
    enum Output: Equatable { case loading, web, native, failed }
    private(set) var token = UUID()
    private(set) var output: Output = .loading
    private(set) var webFailed = false
    private(set) var nativeFailed = false
    mutating func begin() { self = PlaybackRace() }
    @discardableResult mutating func webReady(_ token: UUID) -> Bool {
        guard self.token == token, output != .native, output != .web else { return false }
        output = .web; webFailed = false; return true
    }
    @discardableResult mutating func nativeReady(_ token: UUID) -> Bool {
        guard self.token == token, output != .native else { return false }
        output = .native; nativeFailed = false; return true
    }
    mutating func failWeb(_ token: UUID) {
        guard self.token == token else { return }
        webFailed = true
        if nativeFailed && output == .loading { output = .failed }
    }
    mutating func failNative(_ token: UUID) {
        guard self.token == token else { return }
        nativeFailed = true
        if webFailed && output == .loading { output = .failed }
    }
}
