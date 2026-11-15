import Foundation
import os
import UpdateSupport

private final class UpdateDownloadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @MainActor @Sendable (Double?) -> Void
    private let observation = OSAllocatedUnfairLock<NSKeyValueObservation?>(initialState: nil)
    @MainActor private var lastFraction: Double? = 0

    init(report: @escaping @MainActor @Sendable (Double?) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        // The async download API uses a completion handler, so observe its byte count directly.
        let observer = task.observe(\.countOfBytesReceived) { [weak self] task, _ in
            let expected = task.countOfBytesExpectedToReceive
            let received = task.countOfBytesReceived
            guard received > 0, expected <= 0 || received < expected else { return }
            let fraction = expected > 0 ? Double(received) / Double(expected) : nil
            DispatchQueue.main.async { self?.update(fraction) }
        }
        observation.withLock { $0 = observer }
    }

    @MainActor func update(_ fraction: Double?) {
        guard fraction != lastFraction, (fraction ?? 0) >= (lastFraction ?? 0) else { return }
        lastFraction = fraction
        report(fraction)
    }
}

enum UpdateDownload {
    static func prepare(_ update: VerifiedUpdate, workspace: URL,
                        progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        let downloadProgress = UpdateDownloadProgress(report: progress)
        let session = URLSession(configuration: configuration, delegate: downloadProgress, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: update.downloadURL)
        request.setValue("SofaTV-Updater", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await session.download(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let archive = workspace.appendingPathComponent(update.asset.name)
        try FileManager.default.moveItem(at: file, to: archive)
        await downloadProgress.update(1)
        let extraction = Task.detached {
            try UpdateInstallation.verifyChecksum(of: archive, expected: update.asset.sha256)
            return try UpdateInstallation.extract(archive: archive, into: workspace.appendingPathComponent("extracted"), version: update.version.description)
        }
        return try await withTaskCancellationHandler { try await extraction.value } onCancel: { extraction.cancel() }
    }
}
