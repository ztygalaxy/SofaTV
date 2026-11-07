import Foundation

@MainActor
final class AutomaticUpdateCheck {
    static let skippedVersionKey = "skippedUpdateVersion"

    private let defaults: UserDefaults
    private let delay: Duration
    private var started = false
    private var deadlineReached = false
    private var suppressed = false
    private var update: VerifiedUpdate?
    private var fetchTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private var isWatching: (() -> Bool)?
    private var show: ((VerifiedUpdate) -> Void)?

    init(defaults: UserDefaults = .standard, delay: Duration = .seconds(10)) {
        self.defaults = defaults
        self.delay = delay
    }

    func start(isWatching: @escaping () -> Bool,
               fetch: @escaping () async throws -> VerifiedUpdate?,
               show: @escaping (VerifiedUpdate) -> Void) {
        guard !started else { return }
        started = true
        self.isWatching = isWatching
        self.show = show
        fetchTask = Task { [weak self] in
            do {
                let update = try await fetch()
                try Task.checkCancellation()
                self?.update = update
                self?.presentIfReady()
            } catch {
                // Startup checks are silent; manual checks report errors.
            }
        }
        delayTask = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
                guard let self else { return }
                deadlineReached = true
                // Watching at the deadline suppresses this launch's prompt.
                suppressed = isWatching()
                presentIfReady()
            } catch {}
        }
    }

    func cancel() {
        started = true
        suppressed = true
        fetchTask?.cancel()
        delayTask?.cancel()
        fetchTask = nil
        delayTask = nil
        update = nil
        isWatching = nil
        show = nil
    }

    private func presentIfReady() {
        guard deadlineReached, !suppressed, let update,
              defaults.string(forKey: Self.skippedVersionKey) != update.version.description,
              isWatching?() == false else { return }
        let show = show
        cancel()
        show?(update)
    }
}
