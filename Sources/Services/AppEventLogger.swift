import Foundation

struct AppLogEvent: Codable, Sendable {
    let timestamp: String
    let category: String
    let name: String
    let sessionID: String?
    let metadata: [String: String]
}

final class AppEventLogger: @unchecked Sendable {
    static let shared = AppEventLogger(logFileURL: StoragePaths.eventsLogFile)

    private let logFileURL: URL
    private let encoder = JSONEncoder()
    private let lock = NSLock()

    init(logFileURL: URL) {
        self.logFileURL = logFileURL
    }

    func log(
        category: String,
        name: String,
        sessionID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        let event = AppLogEvent(
            timestamp: Self.makeTimestamp(),
            category: category,
            name: name,
            sessionID: sessionID?.uuidString,
            metadata: metadata
        )

        guard let data = try? encoder.encode(event) else { return }
        appendLine(data)
    }

    private func appendLine(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(data)
            handle.write(Data([0x0A]))
        } catch {
            NSLog("LoqBar event log write failed: \(error.localizedDescription)")
        }
    }

    private static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
