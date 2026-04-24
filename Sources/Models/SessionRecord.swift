import Foundation

struct SessionRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var status: SessionStatus
    var captureMode: CaptureMode
    var audioSourceType: AudioSourceType
    var transcriptPath: String?
    var audioPath: String?
    var systemAudioPath: String?
    var language: String
    var speakerCount: Int
    var aliasMapping: [String: String]
    var transcriptEdits: [String: TranscriptEdit]
    var warningCount: Int
    var notes: String

    var isActive: Bool {
        status == .recording || status == .processing
    }

    var hasTranscribableAudio: Bool {
        audioPath != nil || systemAudioPath != nil
    }

    var isTranscriptionPending: Bool {
        status == .completed && hasTranscribableAudio && transcriptPath == nil
    }

    var displayStatusTitle: String {
        isTranscriptionPending ? "Transcription Pending" : status.title
    }

    var transcriptionStatusSummary: String {
        if isTranscriptionPending {
            return "Recording saved, transcript not exported yet."
        }

        if transcriptPath != nil {
            return "Transcript exported."
        }

        return "No transcript available yet."
    }

    var speakerLabels: [String] {
        let aliasIndexes = aliasMapping.keys.compactMap { key -> Int? in
            guard key.hasPrefix("Speaker") else { return nil }
            return Int(key.replacingOccurrences(of: "Speaker", with: ""))
        }

        let totalSpeakers = max(speakerCount, aliasIndexes.max() ?? 0)
        guard totalSpeakers > 0 else { return [] }

        return (1...totalSpeakers).map { "Speaker\($0)" }
    }

    static func newDraft(captureMode: CaptureMode, audioSourceType: AudioSourceType) -> SessionRecord {
        let now = Date()
        return SessionRecord(
            id: UUID(),
            title: "Untitled Session",
            createdAt: now,
            startedAt: now,
            endedAt: nil,
            durationSeconds: 0,
            status: .idle,
            captureMode: captureMode,
            audioSourceType: audioSourceType,
            transcriptPath: nil,
            audioPath: nil,
            systemAudioPath: nil,
            language: Locale.current.language.languageCode?.identifier ?? "en",
            speakerCount: 0,
            aliasMapping: [:],
            transcriptEdits: [:],
            warningCount: 0,
            notes: ""
        )
    }
}

struct TranscriptEdit: Codable, Hashable {
    var originalText: String
    var editedText: String
    var editedAt: Date
}

enum SessionStatus: String, Codable, CaseIterable {
    case idle
    case recording
    case processing
    case completed
    case failed

    var title: String {
        rawValue.capitalized
    }
}
