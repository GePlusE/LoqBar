import AppKit
import Foundation

struct SessionStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadSettings() -> AppSettings {
        load(AppSettings.self, from: StoragePaths.settingsFile) ?? .defaultValue
    }

    func save(settings: AppSettings) {
        save(settings, to: StoragePaths.settingsFile)
    }

    func loadSessions() -> [SessionRecord] {
        load([SessionRecord].self, from: StoragePaths.sessionsFile) ?? []
    }

    func save(sessions: [SessionRecord]) {
        save(sessions, to: StoragePaths.sessionsFile)
    }

    func openTranscriptFolder(settings: AppSettings) {
        NSWorkspace.shared.open(URL(fileURLWithPath: settings.transcriptOutputFolder, isDirectory: true))
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("LoqBar store write failed: \(error.localizedDescription)")
        }
    }
}

enum StoragePaths {
    static let appSupportFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LoqBar", isDirectory: true)

    static let defaultTranscriptFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LoqBar Transcripts", isDirectory: true)

    static let settingsFile = appSupportFolder.appendingPathComponent("settings.json")
    static let sessionsFile = appSupportFolder.appendingPathComponent("sessions.json")
}
