import Foundation
import UpdateSupport

private final class UpdateDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @MainActor @Sendable (Double?) -> Void

    init(report: @escaping @MainActor @Sendable (Double?) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil
        Task { @MainActor in report(fraction) }
    }
}

enum UpdateDownload {
    static func prepare(_ update: VerifiedUpdate, workspace: URL,
                        progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: update.downloadURL)
        request.setValue("SofaTV-Updater", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await session.download(for: request, delegate: UpdateDownloadProgress(report: progress))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let archive = workspace.appendingPathComponent(update.asset.name)
        try FileManager.default.moveItem(at: file, to: archive)
        let extraction = Task.detached {
            try UpdateInstallation.verifyChecksum(of: archive, expected: update.asset.sha256)
            return try UpdateInstallation.extract(archive: archive, into: workspace.appendingPathComponent("extracted"), version: update.version.description)
        }
        return try await withTaskCancellationHandler { try await extraction.value } onCancel: { extraction.cancel() }
    }
}
