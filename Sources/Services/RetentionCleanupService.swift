import Foundation

struct RetentionCleanupResult {
    let sessions: [SessionRecord]
    let deletedFileCount: Int
    let deletedSessionFolderCount: Int
    let affectedSessionCount: Int

    var summary: String {
        if deletedFileCount == 0 && deletedSessionFolderCount == 0 {
            return "No audio files needed cleanup."
        }

        var parts: [String] = []
        if deletedFileCount > 0 {
            parts.append("\(deletedFileCount) audio file\(deletedFileCount == 1 ? "" : "s") removed")
        }
        if deletedSessionFolderCount > 0 {
            parts.append("\(deletedSessionFolderCount) empty recording folder\(deletedSessionFolderCount == 1 ? "" : "s") removed")
        }
        if affectedSessionCount > 0 {
            parts.append("across \(affectedSessionCount) session\(affectedSessionCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ").capitalized + "."
    }
}

struct RetentionCleanupService {
    private let fileManager = FileManager.default
    private let logger = AppEventLogger.shared

    func run(sessions: [SessionRecord], settings: AppSettings, now: Date = Date()) -> RetentionCleanupResult {
        let startedAt = Date()
        guard settings.autoCleanupEnabled else {
            logger.log(
                category: "cleanup",
                name: "cleanup_skipped",
                metadata: ["reason": "auto_cleanup_disabled"]
            )
            return RetentionCleanupResult(
                sessions: sessions,
                deletedFileCount: 0,
                deletedSessionFolderCount: 0,
                affectedSessionCount: 0
            )
        }

        guard let cutoffDate = settings.audioRetentionPolicy.cutoffDate(relativeTo: now) else {
            logger.log(
                category: "cleanup",
                name: "cleanup_skipped",
                metadata: ["reason": "retention_policy_keep_forever"]
            )
            return RetentionCleanupResult(
                sessions: sessions,
                deletedFileCount: 0,
                deletedSessionFolderCount: 0,
                affectedSessionCount: 0
            )
        }

        var updatedSessions = sessions
        var deletedFileCount = 0
        var deletedSessionFolderCount = 0
        var affectedSessionIDs = Set<UUID>()

        for index in updatedSessions.indices {
            guard shouldPruneAudio(for: updatedSessions[index], cutoffDate: cutoffDate) else {
                continue
            }

            let audioPath = updatedSessions[index].audioPath
            let systemAudioPath = updatedSessions[index].systemAudioPath

            if let audioPath, removeFileIfNeeded(at: audioPath) {
                updatedSessions[index].audioPath = nil
                deletedFileCount += 1
                affectedSessionIDs.insert(updatedSessions[index].id)
            }

            if let systemAudioPath, removeFileIfNeeded(at: systemAudioPath) {
                updatedSessions[index].systemAudioPath = nil
                deletedFileCount += 1
                affectedSessionIDs.insert(updatedSessions[index].id)
            }

            if removeEmptyRecordingFolderIfNeeded(using: [audioPath, systemAudioPath]) {
                deletedSessionFolderCount += 1
            }
        }

        let result = RetentionCleanupResult(
            sessions: updatedSessions,
            deletedFileCount: deletedFileCount,
            deletedSessionFolderCount: deletedSessionFolderCount,
            affectedSessionCount: affectedSessionIDs.count
        )

        logger.log(
            category: "cleanup",
            name: "cleanup_finished",
            metadata: [
                "duration_ms": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                "deleted_file_count": String(result.deletedFileCount),
                "deleted_session_folder_count": String(result.deletedSessionFolderCount),
                "affected_session_count": String(result.affectedSessionCount),
                "policy": settings.audioRetentionPolicy.title
            ]
        )

        return result
    }

    private func shouldPruneAudio(for session: SessionRecord, cutoffDate: Date) -> Bool {
        guard !session.isRecording else { return false }
        guard !session.isProcessing else { return false }
        guard session.transcriptPath != nil else { return false }
        guard session.audioPath != nil || session.systemAudioPath != nil else { return false }

        let referenceDate = session.endedAt ?? session.startedAt
        return referenceDate <= cutoffDate
    }

    private func removeFileIfNeeded(at path: String) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return false }

        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            logger.log(
                category: "cleanup",
                name: "file_remove_failed",
                metadata: [
                    "path": path,
                    "error": error.localizedDescription
                ]
            )
            NSLog("LoqBar cleanup could not remove \(path): \(error.localizedDescription)")
            return false
        }
    }

    private func removeEmptyRecordingFolderIfNeeded(using filePaths: [String?]) -> Bool {
        guard
            let firstPath = filePaths.compactMap({ $0 }).first
        else {
            return false
        }

        let folderURL = URL(fileURLWithPath: firstPath).deletingLastPathComponent()
        guard fileManager.fileExists(atPath: folderURL.path) else { return false }

        do {
            let remaining = try fileManager.contentsOfDirectory(atPath: folderURL.path)
            guard remaining.isEmpty else { return false }
            try fileManager.removeItem(at: folderURL)
            return true
        } catch {
            logger.log(
                category: "cleanup",
                name: "folder_remove_failed",
                metadata: [
                    "path": folderURL.path,
                    "error": error.localizedDescription
                ]
            )
            NSLog("LoqBar cleanup could not remove empty folder \(folderURL.path): \(error.localizedDescription)")
            return false
        }
    }
}
