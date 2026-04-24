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

struct TranscriptionSetupStatus {
    enum State {
        case readyExternal
        case readyManaged
        case notConfigured
        case incompleteExternal
        case brokenExternal
    }

    let state: State
    let title: String
    let message: String
    let detailLines: [String]

    var isReady: Bool {
        state == .readyExternal || state == .readyManaged
    }

    var badgeColorName: String {
        switch state {
        case .readyExternal, .readyManaged:
            return "green"
        case .notConfigured, .incompleteExternal:
            return "orange"
        case .brokenExternal:
            return "red"
        }
    }

    static func from(settings: AppSettings) -> TranscriptionSetupStatus {
        let fileManager = FileManager.default
        let externalExecutable = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalModel = settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnyExternal = !externalExecutable.isEmpty || !externalModel.isEmpty
        let hasBothExternal = !externalExecutable.isEmpty && !externalModel.isEmpty

        if hasBothExternal {
            let executableValid = fileManager.isExecutableFile(atPath: externalExecutable)
            let modelValid = fileManager.fileExists(atPath: externalModel)

            if executableValid && modelValid {
                return TranscriptionSetupStatus(
                    state: .readyExternal,
                    title: "External Transcription Ready",
                    message: "LoqBar will use your configured external whisper-cli and model files.",
                    detailLines: [
                        "Executable: \(externalExecutable)",
                        "Model: \(externalModel)"
                    ]
                )
            }

            return TranscriptionSetupStatus(
                state: .brokenExternal,
                title: "External Transcription Needs Attention",
                message: "LoqBar found configured external paths, but one or both files are not usable.",
                detailLines: [
                    "Executable: \(externalExecutable)",
                    "Model: \(externalModel)"
                ]
            )
        }

        let managedExecutable = settings.managedTranscriptionExecutablePath
        let managedModel = settings.managedTranscriptionModelPath
        let managedReady = fileManager.isExecutableFile(atPath: managedExecutable) &&
            fileManager.fileExists(atPath: managedModel)

        if managedReady {
            return TranscriptionSetupStatus(
                state: .readyManaged,
                title: "Managed Transcription Ready",
                message: "LoqBar will use the managed whisper-cli and model inside the hidden .loqbar folder.",
                detailLines: [
                    "Executable: \(managedExecutable)",
                    "Model: \(managedModel)"
                ]
            )
        }

        if hasAnyExternal {
            return TranscriptionSetupStatus(
                state: .incompleteExternal,
                title: "Transcription Setup Incomplete",
                message: "Add both an external whisper-cli path and a model path, or install a managed copy into .loqbar.",
                detailLines: [
                    "Managed folder: \(settings.managedTranscriptionRootFolder)"
                ]
            )
        }

        return TranscriptionSetupStatus(
            state: .notConfigured,
            title: "Transcription Not Set Up",
            message: "Choose existing external transcription files or install a managed copy into the hidden .loqbar folder.",
            detailLines: [
                "Managed folder: \(settings.managedTranscriptionRootFolder)"
            ]
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
