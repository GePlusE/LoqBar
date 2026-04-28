import Foundation

struct WhisperConfiguration {
    let executableURL: URL
    let modelURL: URL
    let language: String?
    let source: WhisperConfigurationSource

    static func from(settings: AppSettings, languageOverride: String? = nil) -> WhisperConfiguration? {
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

        let languageValue = (languageOverride ?? settings.transcriptionLanguage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        case managedModelNeedsInstall
        case managedRuntimeNeedsInstall
        case notConfigured
        case incompleteExternal
        case brokenExternal
    }

    let state: State
    let title: String
    let message: String
    let detailLines: [String]
    let activeSourceLabel: String

    var isReady: Bool {
        state == .readyExternal || state == .readyManaged
    }

    var badgeColorName: String {
        switch state {
        case .readyExternal, .readyManaged:
            return "green"
        case .managedModelNeedsInstall, .managedRuntimeNeedsInstall, .notConfigured, .incompleteExternal:
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
        let managedExecutable = settings.managedTranscriptionExecutablePath
        let managedModel = settings.managedTranscriptionModelPath
        let managedExecutableReady = fileManager.isExecutableFile(atPath: managedExecutable)
        let managedModelReady = fileManager.fileExists(atPath: managedModel)
        let managedRoot = settings.managedTranscriptionRootFolder
        let selectedModelDescription = settings.selectedModelSuggestion?.title ?? settings.transcriptionModelIdentifier
        let managedModelsDirectory = URL(fileURLWithPath: managedRoot, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        let hasAnyManagedModelFiles = (try? fileManager.contentsOfDirectory(
            at: managedModelsDirectory,
            includingPropertiesForKeys: nil
        ))?.contains(where: { ["bin", "gguf"].contains($0.pathExtension.lowercased()) }) ?? false

        if hasBothExternal {
            let executableValid = fileManager.isExecutableFile(atPath: externalExecutable)
            let modelValid = fileManager.fileExists(atPath: externalModel)

            if executableValid && modelValid {
                return TranscriptionSetupStatus(
                    state: .readyExternal,
                    title: "External Transcription Ready",
                    message: "LoqBar will use your configured external whisper-cli and model files.",
                    detailLines: [
                        "Active source: External files override the managed setup.",
                        "Executable: \(externalExecutable)",
                        "Model: \(externalModel)"
                    ],
                    activeSourceLabel: "External"
                )
            }

            return TranscriptionSetupStatus(
                state: .brokenExternal,
                title: "External Transcription Needs Attention",
                message: "LoqBar found configured external paths, but one or both files are not usable.",
                detailLines: [
                    "Active source: External paths are configured, but at least one file is unusable.",
                    "Executable: \(externalExecutable)",
                    "Model: \(externalModel)"
                ],
                activeSourceLabel: "External"
            )
        }

        let managedReady = managedExecutableReady && managedModelReady

        if managedReady {
            return TranscriptionSetupStatus(
                state: .readyManaged,
                title: "Managed Transcription Ready",
                message: "LoqBar will use the managed whisper-cli and model inside the hidden .loqbar folder.",
                detailLines: [
                    "Active source: Managed setup",
                    "Selected model: \(selectedModelDescription)",
                    "Executable: \(managedExecutable)",
                    "Model: \(managedModel)"
                ],
                activeSourceLabel: "Managed"
            )
        }

        if managedExecutableReady && !managedModelReady {
            return TranscriptionSetupStatus(
                state: .managedModelNeedsInstall,
                title: "Managed Model Needs Installing",
                message: "LoqBar has the managed runtime, but the selected model is not installed yet.",
                detailLines: [
                    "Selected model: \(selectedModelDescription)",
                    hasAnyManagedModelFiles
                        ? "A different managed model is already present. Install the selected model to switch cleanly."
                        : "No managed model is installed yet.",
                    "Managed folder: \(managedRoot)"
                ],
                activeSourceLabel: "Managed setup needs a model"
            )
        }

        if managedExecutableReady || hasAnyManagedModelFiles {
            return TranscriptionSetupStatus(
                state: .managedRuntimeNeedsInstall,
                title: "Managed Setup Needs Repair",
                message: "LoqBar found part of the managed transcription setup, but it is incomplete.",
                detailLines: [
                    "Selected model: \(selectedModelDescription)",
                    "Reinstall the managed setup to refresh whisper-cli, its libraries, and the selected model.",
                    "Managed folder: \(managedRoot)"
                ],
                activeSourceLabel: "Managed setup incomplete"
            )
        }

        if hasAnyExternal {
            return TranscriptionSetupStatus(
                state: .incompleteExternal,
                title: "Transcription Setup Incomplete",
                message: "Add both an external whisper-cli path and a model path, or install a managed copy into .loqbar.",
                detailLines: [
                    "Selected model: \(selectedModelDescription)",
                    "Managed folder: \(settings.managedTranscriptionRootFolder)"
                ],
                activeSourceLabel: "Not ready"
            )
        }

        return TranscriptionSetupStatus(
            state: .notConfigured,
            title: "Transcription Not Set Up",
            message: "Choose existing external transcription files or install a managed copy into the hidden .loqbar folder.",
            detailLines: [
                "Selected model: \(selectedModelDescription)",
                "Managed folder: \(settings.managedTranscriptionRootFolder)"
            ],
            activeSourceLabel: "Not configured"
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
