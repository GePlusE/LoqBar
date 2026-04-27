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

enum TranscriptionModelSuggestion: String, CaseIterable, Identifiable {
    case base
    case small
    case medium

    var id: Self { self }

    var identifier: String { rawValue }

    var title: String {
        switch self {
        case .base:
            return "Base"
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        }
    }

    var summary: String {
        switch self {
        case .base:
            return "Fastest, but the weakest choice for noisy calls and speaker overlap."
        case .small:
            return "Good quality/speed balance. Recommended first upgrade for call recordings."
        case .medium:
            return "Stronger recognition for difficult calls and accents, but slower and heavier."
        }
    }

    var isRecommendedForCalls: Bool {
        self == .small || self == .medium
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
    var lastCleanupAt: Date?
    var lastCleanupSummary: String?
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
        lastCleanupAt: nil,
        lastCleanupSummary: nil,
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

    var normalizedTranscriptionModelIdentifier: String {
        transcriptionModelIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    func cutoffDate(relativeTo now: Date) -> Date? {
        switch self {
        case .deleteImmediately:
            return now
        case .days7:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .days14:
            return Calendar.current.date(byAdding: .day, value: -14, to: now)
        case .days30:
            return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .days60:
            return Calendar.current.date(byAdding: .day, value: -60, to: now)
        case .days90:
            return Calendar.current.date(byAdding: .day, value: -90, to: now)
        case .keepForever:
            return nil
        }
    }
}
