import Foundation

struct WhisperConfiguration {
    let executableURL: URL
    let modelURL: URL
    let language: String?

    static func from(settings: AppSettings) -> WhisperConfiguration? {
        let executablePath = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelPath = settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !executablePath.isEmpty, !modelPath.isEmpty else {
            return nil
        }

        let languageValue = settings.transcriptionLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return WhisperConfiguration(
            executableURL: URL(fileURLWithPath: executablePath),
            modelURL: URL(fileURLWithPath: modelPath),
            language: languageValue == "auto" || languageValue.isEmpty ? nil : languageValue
        )
    }
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
