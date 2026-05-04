import Foundation

enum TranscriptionLanguageOption: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum TranscriptionModelSuggestion: String, CaseIterable, Identifiable, Sendable {
    case base
    case small
    case medium
    case large

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
        case .large:
            return "Large"
        }
    }

    var managedModelFileName: String {
        switch self {
        case .base:
            return "ggml-base.bin"
        case .small:
            return "ggml-small.bin"
        case .medium:
            return "ggml-medium.bin"
        case .large:
            return "ggml-large-v3.bin"
        }
    }

    var managedDownloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(managedModelFileName)")!
    }

    var approximateDownloadSize: String {
        switch self {
        case .base:
            return "about 150 MB"
        case .small:
            return "about 500 MB"
        case .medium:
            return "about 1.5 GB"
        case .large:
            return "about 3.1 GB"
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
        case .large:
            return "Highest quality option in this picker, but also the slowest and heaviest on memory and processing."
        }
    }

    var isRecommendedForCalls: Bool {
        self == .small || self == .medium || self == .large
    }
}

enum TranscriptionComputeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case gpuPreferred
    case cpuOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .gpuPreferred:
            return "GPU Preferred"
        case .cpuOnly:
            return "CPU Only"
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return "Use the best local acceleration path when available, then fall back safely."
        case .gpuPreferred:
            return "Try Metal/GPU first and retry on CPU if acceleration fails."
        case .cpuOnly:
            return "Most conservative mode. Slowest, but avoids GPU/Metal entirely."
        }
    }
}

struct AppSettings: Codable, Sendable {
    var storageRootFolder: String
    var audioRetentionPolicy: AudioRetentionPolicy
    var defaultCaptureMode: CaptureMode
    var customVocabularyEntries: [String]
    var transcriptionModelIdentifier: String
    var transcriptionComputeMode: TranscriptionComputeMode
    var transcriptionExecutablePath: String
    var transcriptionModelPath: String
    var transcriptionLanguage: String
    var autoCleanupEnabled: Bool
    var lastCleanupAt: Date?
    var lastCleanupSummary: String?
    var launchAtLoginEnabled: Bool
    var firstRunCompleted: Bool
    var lastLaunchedAppVersion: String?

    private enum CodingKeys: String, CodingKey {
        case storageRootFolder
        case audioRetentionPolicy
        case defaultCaptureMode
        case customVocabularyEntries
        case transcriptionModelIdentifier
        case transcriptionComputeMode
        case transcriptionExecutablePath
        case transcriptionModelPath
        case transcriptionLanguage
        case autoCleanupEnabled
        case lastCleanupAt
        case lastCleanupSummary
        case launchAtLoginEnabled
        case firstRunCompleted
        case lastLaunchedAppVersion
    }

    static let defaultValue = AppSettings(
        storageRootFolder: StoragePaths.defaultStorageRootFolder.path,
        audioRetentionPolicy: .days90,
        defaultCaptureMode: .auto,
        customVocabularyEntries: [],
        transcriptionModelIdentifier: "base",
        transcriptionComputeMode: .auto,
        transcriptionExecutablePath: "",
        transcriptionModelPath: "",
        transcriptionLanguage: "auto",
        autoCleanupEnabled: true,
        lastCleanupAt: nil,
        lastCleanupSummary: nil,
        launchAtLoginEnabled: false,
        firstRunCompleted: false,
        lastLaunchedAppVersion: nil
    )

    init(
        storageRootFolder: String,
        audioRetentionPolicy: AudioRetentionPolicy,
        defaultCaptureMode: CaptureMode,
        customVocabularyEntries: [String],
        transcriptionModelIdentifier: String,
        transcriptionComputeMode: TranscriptionComputeMode,
        transcriptionExecutablePath: String,
        transcriptionModelPath: String,
        transcriptionLanguage: String,
        autoCleanupEnabled: Bool,
        lastCleanupAt: Date?,
        lastCleanupSummary: String?,
        launchAtLoginEnabled: Bool,
        firstRunCompleted: Bool,
        lastLaunchedAppVersion: String?
    ) {
        self.storageRootFolder = storageRootFolder
        self.audioRetentionPolicy = audioRetentionPolicy
        self.defaultCaptureMode = defaultCaptureMode
        self.customVocabularyEntries = customVocabularyEntries
        self.transcriptionModelIdentifier = transcriptionModelIdentifier
        self.transcriptionComputeMode = transcriptionComputeMode
        self.transcriptionExecutablePath = transcriptionExecutablePath
        self.transcriptionModelPath = transcriptionModelPath
        self.transcriptionLanguage = transcriptionLanguage
        self.autoCleanupEnabled = autoCleanupEnabled
        self.lastCleanupAt = lastCleanupAt
        self.lastCleanupSummary = lastCleanupSummary
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.firstRunCompleted = firstRunCompleted
        self.lastLaunchedAppVersion = lastLaunchedAppVersion
    }

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

        if normalized == TranscriptionModelSuggestion.large.identifier {
            return TranscriptionModelSuggestion.large.managedModelFileName
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

    var selectedModelSuggestion: TranscriptionModelSuggestion? {
        TranscriptionModelSuggestion.allCases.first { $0.identifier == normalizedTranscriptionModelIdentifier }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storageRootFolder = try container.decodeIfPresent(String.self, forKey: .storageRootFolder) ?? AppSettings.defaultValue.storageRootFolder
        audioRetentionPolicy = try container.decodeIfPresent(AudioRetentionPolicy.self, forKey: .audioRetentionPolicy) ?? AppSettings.defaultValue.audioRetentionPolicy
        defaultCaptureMode = try container.decodeIfPresent(CaptureMode.self, forKey: .defaultCaptureMode) ?? AppSettings.defaultValue.defaultCaptureMode
        customVocabularyEntries = try container.decodeIfPresent([String].self, forKey: .customVocabularyEntries) ?? AppSettings.defaultValue.customVocabularyEntries
        transcriptionModelIdentifier = try container.decodeIfPresent(String.self, forKey: .transcriptionModelIdentifier) ?? AppSettings.defaultValue.transcriptionModelIdentifier
        transcriptionComputeMode = try container.decodeIfPresent(TranscriptionComputeMode.self, forKey: .transcriptionComputeMode) ?? AppSettings.defaultValue.transcriptionComputeMode
        transcriptionExecutablePath = try container.decodeIfPresent(String.self, forKey: .transcriptionExecutablePath) ?? AppSettings.defaultValue.transcriptionExecutablePath
        transcriptionModelPath = try container.decodeIfPresent(String.self, forKey: .transcriptionModelPath) ?? AppSettings.defaultValue.transcriptionModelPath
        transcriptionLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage) ?? AppSettings.defaultValue.transcriptionLanguage
        autoCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoCleanupEnabled) ?? AppSettings.defaultValue.autoCleanupEnabled
        lastCleanupAt = try container.decodeIfPresent(Date.self, forKey: .lastCleanupAt)
        lastCleanupSummary = try container.decodeIfPresent(String.self, forKey: .lastCleanupSummary)
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? AppSettings.defaultValue.launchAtLoginEnabled
        firstRunCompleted = try container.decodeIfPresent(Bool.self, forKey: .firstRunCompleted) ?? AppSettings.defaultValue.firstRunCompleted
        lastLaunchedAppVersion = try container.decodeIfPresent(String.self, forKey: .lastLaunchedAppVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storageRootFolder, forKey: .storageRootFolder)
        try container.encode(audioRetentionPolicy, forKey: .audioRetentionPolicy)
        try container.encode(defaultCaptureMode, forKey: .defaultCaptureMode)
        try container.encode(customVocabularyEntries, forKey: .customVocabularyEntries)
        try container.encode(transcriptionModelIdentifier, forKey: .transcriptionModelIdentifier)
        try container.encode(transcriptionComputeMode, forKey: .transcriptionComputeMode)
        try container.encode(transcriptionExecutablePath, forKey: .transcriptionExecutablePath)
        try container.encode(transcriptionModelPath, forKey: .transcriptionModelPath)
        try container.encode(transcriptionLanguage, forKey: .transcriptionLanguage)
        try container.encode(autoCleanupEnabled, forKey: .autoCleanupEnabled)
        try container.encodeIfPresent(lastCleanupAt, forKey: .lastCleanupAt)
        try container.encodeIfPresent(lastCleanupSummary, forKey: .lastCleanupSummary)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(firstRunCompleted, forKey: .firstRunCompleted)
        try container.encodeIfPresent(lastLaunchedAppVersion, forKey: .lastLaunchedAppVersion)
    }
}

enum AudioRetentionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
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
