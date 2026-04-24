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
            warningCount: 0,
            notes: ""
        )
    }
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
