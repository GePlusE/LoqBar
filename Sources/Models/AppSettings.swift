import Foundation

struct AppSettings: Codable {
    var transcriptOutputFolder: String
    var recordingOutputFolder: String
    var audioRetentionPolicy: AudioRetentionPolicy
    var defaultCaptureMode: CaptureMode
    var customVocabularyEntries: [String]
    var transcriptionModelIdentifier: String
    var transcriptionExecutablePath: String
    var transcriptionModelPath: String
    var transcriptionLanguage: String
    var autoCleanupEnabled: Bool
    var launchAtLoginEnabled: Bool
    var firstRunCompleted: Bool

    static let defaultValue = AppSettings(
        transcriptOutputFolder: StoragePaths.defaultTranscriptFolder.path,
        recordingOutputFolder: StoragePaths.defaultRecordingFolder.path,
        audioRetentionPolicy: .days90,
        defaultCaptureMode: .auto,
        customVocabularyEntries: [],
        transcriptionModelIdentifier: "whisper-large-v3-turbo-q5",
        transcriptionExecutablePath: "",
        transcriptionModelPath: "",
        transcriptionLanguage: "auto",
        autoCleanupEnabled: true,
        launchAtLoginEnabled: false,
        firstRunCompleted: false
    )
}

enum AudioRetentionPolicy: String, Codable, CaseIterable, Identifiable {
    case deleteImmediately
    case days30
    case days60
    case days90
    case keepForever

    var id: Self { self }

    var title: String {
        switch self {
        case .deleteImmediately:
            return "Delete Immediately"
        case .days30:
            return "Keep 30 Days"
        case .days60:
            return "Keep 60 Days"
        case .days90:
            return "Keep 90 Days"
        case .keepForever:
            return "Keep Indefinitely"
        }
    }
}
