import Foundation

struct ManagedTranscriptionInstallResult {
    let executableSourceDescription: String
    let modelSourceDescription: String
}

struct ManagedTranscriptionInstallService {
    func install(
        settings: AppSettings,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ManagedTranscriptionInstallResult {
        let fileManager = FileManager.default

        let executableDestination = URL(fileURLWithPath: settings.managedTranscriptionExecutablePath)
        let modelDestination = URL(fileURLWithPath: settings.managedTranscriptionModelPath)

        try fileManager.createDirectory(
            at: executableDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: modelDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        await progress("Preparing managed transcription files…")
        let executableSource = try resolveExecutableSource(settings: settings)

        await progress("Installing whisper-cli…")
        try replaceFile(at: executableDestination, withContentsOf: executableSource.url)
        makeExecutableIfPossible(at: executableDestination)

        let modelSource = try await resolveModelSource(
            settings: settings,
            destinationURL: modelDestination,
            progress: progress
        )

        return ManagedTranscriptionInstallResult(
            executableSourceDescription: executableSource.description,
            modelSourceDescription: modelSource
        )
    }

    private func resolveExecutableSource(settings: AppSettings) throws -> (url: URL, description: String) {
        let fileManager = FileManager.default

        let externalExecutable = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !externalExecutable.isEmpty,
           fileManager.isExecutableFile(atPath: externalExecutable) {
            return (URL(fileURLWithPath: externalExecutable), "Copied from your external whisper-cli path.")
        }

        if let bundledExecutable = bundledExecutableURL(),
           fileManager.isExecutableFile(atPath: bundledExecutable.path) {
            return (bundledExecutable, "Installed from the LoqBar app bundle.")
        }

        let workspaceExecutable = developerWorkspaceExecutableURL()
        if fileManager.isExecutableFile(atPath: workspaceExecutable.path) {
            return (workspaceExecutable, "Copied from the local developer workspace.")
        }

        throw AppError.transcriptionConfigurationMissing(
            """
            LoqBar could not find a bundled or external whisper-cli yet.

            Reinstall the latest LoqBar release, or choose an existing external whisper-cli path first.
            """
        )
    }

    private func resolveModelSource(
        settings: AppSettings,
        destinationURL: URL,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let fileManager = FileManager.default

        let externalModel = settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !externalModel.isEmpty,
           fileManager.fileExists(atPath: externalModel) {
            await progress("Installing the selected model from your external path…")
            try replaceFile(at: destinationURL, withContentsOf: URL(fileURLWithPath: externalModel))
            return "Copied model from your external path."
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            return "Kept the existing managed model already stored in .loqbar."
        }

        guard let suggestion = settings.selectedModelSuggestion else {
            throw AppError.transcriptionConfigurationMissing(
                """
                LoqBar does not know how to install the selected model automatically yet.

                Choose Base, Small, Medium, or Large in Preferences > Transcription, or provide an external model path.
                """
            )
        }

        await progress("Downloading the \(suggestion.title) model… This can take a while.")
        let temporaryModel = try await downloadFile(from: suggestion.managedDownloadURL)
        defer { try? FileManager.default.removeItem(at: temporaryModel) }

        try replaceFile(at: destinationURL, withContentsOf: temporaryModel)
        return "Downloaded the \(suggestion.title) model into the managed .loqbar folder."
    }

    private func downloadFile(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw AppError.transcriptionConfigurationMissing(
                "LoqBar could not download the model file (\(httpResponse.statusCode)). Check your internet connection and try again."
            )
        }

        return temporaryURL
    }

    private func replaceFile(at destinationURL: URL, withContentsOf sourceURL: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func bundledExecutableURL() -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("ManagedTranscription", isDirectory: true)
            .appendingPathComponent("whisper-cli")
    }

    private func developerWorkspaceExecutableURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("whisper.cpp", isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli")
    }

    private func makeExecutableIfPossible(at url: URL) {
        var permissions = stat()
        if stat(url.path, &permissions) == 0 {
            chmod(url.path, permissions.st_mode | S_IXUSR | S_IXGRP | S_IXOTH)
        }
    }
}
