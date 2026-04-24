import Foundation

enum TranscriptionLanguageOption: String, Codable, CaseIterable, Identifiable {
    case auto
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case dutch = "nl"
    case portuguese = "pt"
    case polish = "pl"

    var id: Self { self }

    var title: String {
        switch self {
        case .auto:
            return "Auto Detect"
        case .english:
            return "English"
        case .german:
            return "German"
        case .french:
            return "French"
        case .spanish:
            return "Spanish"
        case .italian:
            return "Italian"
        case .dutch:
            return "Dutch"
        case .portuguese:
            return "Portuguese"
        case .polish:
            return "Polish"
        }
    }
}

struct AppSettings: Codable {
    var storageRootFolder: String
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
        storageRootFolder: StoragePaths.defaultStorageRootFolder.path,
        audioRetentionPolicy: .days90,
        defaultCaptureMode: .auto,
        customVocabularyEntries: [],
        transcriptionModelIdentifier: "base",
        transcriptionExecutablePath: "",
        transcriptionModelPath: "",
        transcriptionLanguage: "auto",
        autoCleanupEnabled: true,
        launchAtLoginEnabled: false,
        firstRunCompleted: false
    )

    var transcriptOutputFolder: String {
        URL(fileURLWithPath: storageRootFolder, isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
            .path
    }

    var recordingOutputFolder: String {
        URL(fileURLWithPath: storageRootFolder, isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
            .path
    }

    var managedTranscriptionRootFolder: String {
        URL(fileURLWithPath: storageRootFolder, isDirectory: true)
            .appendingPathComponent(".loqbar", isDirectory: true)
            .path
    }

    var managedTranscriptionExecutablePath: String {
        URL(fileURLWithPath: managedTranscriptionRootFolder, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli")
            .path
    }

    var managedTranscriptionModelPath: String {
        URL(fileURLWithPath: managedTranscriptionRootFolder, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(managedTranscriptionModelFileName)
            .path
    }

    private var managedTranscriptionModelFileName: String {
        let normalized = transcriptionModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty || normalized == "whisper-large-v3-turbo-q5" {
            return "ggml-base.bin"
        }

        if normalized.hasSuffix(".bin") || normalized.hasSuffix(".gguf") {
            return normalized
        }

        return "ggml-\(normalized).bin"
    }

    var hasExternalTranscriptionPaths: Bool {
        !transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AudioRetentionPolicy: String, Codable, CaseIterable, Identifiable {
    case deleteImmediately
    case days7
    case days14
    case days30
    case days60
    case days90
    case keepForever

    var id: Self { self }

    var title: String {
        switch self {
        case .deleteImmediately:
            return "Delete Immediately"
        case .days7:
            return "Keep 7 Days"
        case .days14:
            return "Keep 14 Days"
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
