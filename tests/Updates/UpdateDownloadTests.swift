import CryptoKit
import Foundation

@MainActor
struct UpdateDownloadTests {
    func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SofaTV.DownloadTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try UpdateInstallationTests().fixture(in: root.appendingPathComponent("new"), version: "0.0.4")
        let app = original.deletingLastPathComponent().appendingPathComponent("SofaTV-0.0.4-arm64.app")
        try FileManager.default.moveItem(at: original, to: app)
        let archive = root.appendingPathComponent("update.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", app.path, archive.path]
        try zip.run()
        zip.waitUntilExit()
        check(zip.terminationStatus == 0)
        let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", """
        import http.server, sys, time
        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *a, **kw): super().__init__(*a, directory=sys.argv[1], **kw)
            def log_message(self, *args): pass
            def do_GET(self):
                if self.path == '/slow':
                    self.send_response(200); self.send_header('Content-Length', str(1024*1024*16)); self.end_headers()
                    try:
                        for i in range(256): self.wfile.write(b'x'*65536); self.wfile.flush(); time.sleep(.01)
                    except (BrokenPipeError, ConnectionResetError): pass
                else: super().do_GET()
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        print(server.server_port, flush=True)
        server.serve_forever()
        """, root.path]
        let pipe = Pipe()
        server.standardOutput = pipe
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        let port = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        func update(path: String = "update.zip", checksum: String? = nil) -> VerifiedUpdate {
            VerifiedUpdate(version: SemanticVersion("0.0.4")!, notes: "", asset: UpdateAsset(name: "SofaTV-0.0.4-arm64.zip", sha256: checksum ?? hash),
                           downloadURL: URL(string: "http://127.0.0.1:\(port)/\(path)")!, releaseURL: URL(string: "https://example.com")!)
        }
        func workspace() throws -> URL {
            let directory = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            return directory
        }
        var progress: [Double] = []
        let source = try await UpdateDownload.prepare(update(), workspace: workspace()) { fraction in
            if let fraction { progress.append(fraction) }
        }
        check(FileManager.default.fileExists(atPath: source.appendingPathComponent("Contents/MacOS/SofaTV").path))
        check(progress.allSatisfy { (0...1).contains($0) })
        do {
            _ = try await UpdateDownload.prepare(update(checksum: String(repeating: "0", count: 64)), workspace: workspace()) { _ in }
            preconditionFailure("A corrupted download must be rejected")
        } catch {}
        do {
            _ = try await UpdateDownload.prepare(update(path: "missing.zip"), workspace: workspace()) { _ in }
            preconditionFailure("An HTTP error must be rejected")
        } catch {}
        let slowWorkspace = try workspace()
        let slow = update(path: "slow")
        let task = Task { try await UpdateDownload.prepare(slow, workspace: slowWorkspace) { _ in } }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("Cancelled download continued to installation")
        } catch {
            check(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }
}
