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

    func openRecordingRootFolder(settings: AppSettings) {
        NSWorkspace.shared.open(URL(fileURLWithPath: settings.recordingOutputFolder, isDirectory: true))
    }

    func revealFile(at path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openRecordingFolder(for session: SessionRecord) {
        if let audioPath = session.audioPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: audioPath).deletingLastPathComponent())
            return
        }

        if let systemAudioPath = session.systemAudioPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: systemAudioPath).deletingLastPathComponent())
            return
        }
    }

    func deleteArtifacts(for session: SessionRecord) throws {
        let fileManager = FileManager.default
        var candidateFolderURLs: Set<URL> = []

        for path in [session.transcriptPath, session.audioPath, session.systemAudioPath].compactMap({ $0 }) {
            let fileURL = URL(fileURLWithPath: path)
            candidateFolderURLs.insert(fileURL.deletingLastPathComponent())

            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    throw AppError.sessionDeletionFailed("LoqBar could not remove \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        for folderURL in candidateFolderURLs {
            guard fileManager.fileExists(atPath: folderURL.path) else { continue }

            do {
                let remainingItems = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                if remainingItems.isEmpty {
                    try fileManager.removeItem(at: folderURL)
                }
            } catch {
                throw AppError.sessionDeletionFailed("LoqBar could not clean up the session folder: \(error.localizedDescription)")
            }
        }
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

    static let defaultStorageRootFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LoqBar", isDirectory: true)
    static let transcriptionScratchFolder = appSupportFolder.appendingPathComponent("TranscriptionScratch", isDirectory: true)

    static let settingsFile = appSupportFolder.appendingPathComponent("settings.json")
    static let sessionsFile = appSupportFolder.appendingPathComponent("sessions.json")

    static func sessionRecordingFolder(rootFolderPath: String, for sessionID: UUID) -> URL {
        URL(fileURLWithPath: rootFolderPath, isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }
}
