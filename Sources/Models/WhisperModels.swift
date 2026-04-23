import Foundation

struct WhisperConfiguration {
    let executableURL: URL
    let modelURL: URL
    let language: String?
    let source: WhisperConfigurationSource

    static func from(settings: AppSettings) -> WhisperConfiguration? {
        let fileManager = FileManager.default

        let managedExecutablePath = settings.managedTranscriptionExecutablePath
        let managedModelPath = settings.managedTranscriptionModelPath

        let legacyExecutablePath = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyModelPath = settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines)

        let executablePath: String
        let modelPath: String
        let source: WhisperConfigurationSource

        if !legacyExecutablePath.isEmpty, !legacyModelPath.isEmpty {
            executablePath = legacyExecutablePath
            modelPath = legacyModelPath
            source = .external
        } else if fileManager.fileExists(atPath: managedExecutablePath), fileManager.fileExists(atPath: managedModelPath) {
            executablePath = managedExecutablePath
            modelPath = managedModelPath
            source = .managed
        } else {
            return nil
        }

        let languageValue = settings.transcriptionLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return WhisperConfiguration(
            executableURL: URL(fileURLWithPath: executablePath),
            modelURL: URL(fileURLWithPath: modelPath),
            language: languageValue == "auto" || languageValue.isEmpty ? nil : languageValue,
            source: source
        )
    }
}

enum WhisperConfigurationSource {
    case external
    case managed
}

struct WhisperSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

struct WhisperTranscription {
    let text: String
    let language: String?
    let segments: [WhisperSegment]
    let engineDescription: String
}
