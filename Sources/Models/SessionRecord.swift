import Foundation

struct SessionRecord: Identifiable, Codable, Hashable, Sendable {
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
    var transcriptionLanguageOverride: String?
    var speakerCount: Int
    var aliasMapping: [String: String]
    var speakerAssignments: [String: String]
    var transcriptEdits: [String: TranscriptEdit]
    var warningCount: Int
    var notes: String
    var sharedLinks: String
    var contextNotes: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case startedAt
        case endedAt
        case durationSeconds
        case status
        case captureMode
        case audioSourceType
        case transcriptPath
        case audioPath
        case systemAudioPath
        case language
        case transcriptionLanguageOverride
        case speakerCount
        case aliasMapping
        case speakerAssignments
        case transcriptEdits
        case warningCount
        case notes
        case sharedLinks
        case contextNotes
    }

    var isRecording: Bool {
        status == .recording
    }

    var isProcessing: Bool {
        status == .processing
    }

    var isActive: Bool {
        isRecording
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

        let reassignedIndexes = speakerAssignments.values.compactMap { key -> Int? in
            guard key.hasPrefix("Speaker") else { return nil }
            return Int(key.replacingOccurrences(of: "Speaker", with: ""))
        }

        let totalSpeakers = max(speakerCount, aliasIndexes.max() ?? 0, reassignedIndexes.max() ?? 0)
        guard totalSpeakers > 0 else { return [] }

        return (1...totalSpeakers).map { "Speaker\($0)" }
    }

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        startedAt: Date,
        endedAt: Date?,
        durationSeconds: Int,
        status: SessionStatus,
        captureMode: CaptureMode,
        audioSourceType: AudioSourceType,
        transcriptPath: String?,
        audioPath: String?,
        systemAudioPath: String?,
        language: String,
        transcriptionLanguageOverride: String?,
        speakerCount: Int,
        aliasMapping: [String: String],
        speakerAssignments: [String: String],
        transcriptEdits: [String: TranscriptEdit],
        warningCount: Int,
        notes: String,
        sharedLinks: String,
        contextNotes: String
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.captureMode = captureMode
        self.audioSourceType = audioSourceType
        self.transcriptPath = transcriptPath
        self.audioPath = audioPath
        self.systemAudioPath = systemAudioPath
        self.language = language
        self.transcriptionLanguageOverride = transcriptionLanguageOverride
        self.speakerCount = speakerCount
        self.aliasMapping = aliasMapping
        self.speakerAssignments = speakerAssignments
        self.transcriptEdits = transcriptEdits
        self.warningCount = warningCount
        self.notes = notes
        self.sharedLinks = sharedLinks
        self.contextNotes = contextNotes
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
            transcriptionLanguageOverride: nil,
            speakerCount: 0,
            aliasMapping: [:],
            speakerAssignments: [:],
            transcriptEdits: [:],
            warningCount: 0,
            notes: "",
            sharedLinks: "",
            contextNotes: ""
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        status = try container.decode(SessionStatus.self, forKey: .status)
        captureMode = try container.decode(CaptureMode.self, forKey: .captureMode)
        audioSourceType = try container.decode(AudioSourceType.self, forKey: .audioSourceType)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
        systemAudioPath = try container.decodeIfPresent(String.self, forKey: .systemAudioPath)
        language = try container.decode(String.self, forKey: .language)
        transcriptionLanguageOverride = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguageOverride)
        speakerCount = try container.decode(Int.self, forKey: .speakerCount)
        aliasMapping = try container.decodeIfPresent([String: String].self, forKey: .aliasMapping) ?? [:]
        speakerAssignments = try container.decodeIfPresent([String: String].self, forKey: .speakerAssignments) ?? [:]
        transcriptEdits = try container.decodeIfPresent([String: TranscriptEdit].self, forKey: .transcriptEdits) ?? [:]
        warningCount = try container.decode(Int.self, forKey: .warningCount)
        notes = try container.decode(String.self, forKey: .notes)
        sharedLinks = try container.decodeIfPresent(String.self, forKey: .sharedLinks) ?? ""
        contextNotes = try container.decodeIfPresent(String.self, forKey: .contextNotes) ?? ""
    }
}

struct TranscriptEdit: Codable, Hashable, Sendable {
    var originalText: String
    var editedText: String
    var editedAt: Date
}

enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case recording
    case processing
    case completed
    case failed

    var title: String {
        rawValue.capitalized
    }
}
