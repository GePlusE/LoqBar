import Foundation

struct ManagedTranscriptionInstallResult {
    let executableSourceDescription: String
    let modelSourceDescription: String
}

struct ManagedTranscriptionInstallService {
    private let requiredLibraryNames = [
        "libwhisper.1.dylib",
        "libggml.0.dylib",
        "libggml-cpu.0.dylib",
        "libggml-blas.0.dylib",
        "libggml-metal.0.dylib",
        "libggml-base.0.dylib"
    ]

    func install(
        settings: AppSettings,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ManagedTranscriptionInstallResult {
        let fileManager = FileManager.default

        let executableDestination = URL(fileURLWithPath: settings.managedTranscriptionExecutablePath)
        let modelDestination = URL(fileURLWithPath: settings.managedTranscriptionModelPath)
        let libraryDestinationDirectory = URL(fileURLWithPath: settings.managedTranscriptionRootFolder, isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)

        try fileManager.createDirectory(
            at: executableDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: modelDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: libraryDestinationDirectory,
            withIntermediateDirectories: true
        )

        await progress("Preparing managed transcription files…")
        let executableSource = try resolveExecutableSource(settings: settings)

        await progress("Installing whisper-cli…")
        try replaceFile(at: executableDestination, withContentsOf: executableSource.url, sourceBasenameOverride: executableDestination.lastPathComponent)
        makeExecutableIfPossible(at: executableDestination)

        await progress("Installing whisper libraries…")
        let librarySourceDescription = try installLibraries(
            source: executableSource,
            destinationDirectory: libraryDestinationDirectory
        )

        try retargetExecutable(
            executableURL: executableDestination,
            libraryDirectory: libraryDestinationDirectory
        )

        let modelSource = try await resolveModelSource(
            settings: settings,
            destinationURL: modelDestination,
            progress: progress
        )

        return ManagedTranscriptionInstallResult(
            executableSourceDescription: "\(executableSource.description) \(librarySourceDescription)",
            modelSourceDescription: modelSource
        )
    }

    private func resolveExecutableSource(settings: AppSettings) throws -> (url: URL, description: String, libraryURLs: [URL]) {
        let fileManager = FileManager.default

        let externalExecutable = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !externalExecutable.isEmpty,
           fileManager.isExecutableFile(atPath: externalExecutable) {
            let executableURL = URL(fileURLWithPath: externalExecutable)
            return (
                executableURL,
                "Copied from your external whisper-cli path.",
                try resolveLibraryURLs(for: executableURL)
            )
        }

        if let bundledExecutable = bundledExecutableURL(),
           fileManager.isExecutableFile(atPath: bundledExecutable.path) {
            return (
                bundledExecutable,
                "Installed from the LoqBar app bundle.",
                try bundledLibraryURLs()
            )
        }

        let workspaceExecutable = developerWorkspaceExecutableURL()
        if fileManager.isExecutableFile(atPath: workspaceExecutable.path) {
            return (
                workspaceExecutable,
                "Copied from the local developer workspace.",
                try developerWorkspaceLibraryURLs()
            )
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
            try replaceFile(
                at: destinationURL,
                withContentsOf: URL(fileURLWithPath: externalModel),
                sourceBasenameOverride: destinationURL.lastPathComponent
            )
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

        try replaceFile(
            at: destinationURL,
            withContentsOf: temporaryModel,
            sourceBasenameOverride: destinationURL.lastPathComponent
        )
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

    private func replaceFile(
        at destinationURL: URL,
        withContentsOf sourceURL: URL,
        sourceBasenameOverride: String? = nil
    ) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let resolvedSourceURL = sourceURL.resolvingSymlinksInPath()
        let stagingURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            sourceBasenameOverride ?? destinationURL.lastPathComponent
        )

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }

        try fileManager.copyItem(at: resolvedSourceURL, to: stagingURL)

        if stagingURL != destinationURL {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }
    }

    private func bundledExecutableURL() -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("ManagedTranscription", isDirectory: true)
            .appendingPathComponent("whisper-cli")
    }

    private func bundledLibraryURLs() throws -> [URL] {
        guard let resourcesURL = Bundle.main.resourceURL else {
            throw AppError.transcriptionConfigurationMissing("LoqBar could not locate its bundled resources for managed transcription.")
        }

        let libraryRoot = resourcesURL
            .appendingPathComponent("ManagedTranscription", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)

        return try requiredLibraryNames.map { libraryName in
            let url = libraryRoot.appendingPathComponent(libraryName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AppError.transcriptionConfigurationMissing("LoqBar is missing the bundled managed library \(libraryName). Reinstall the latest release and try again.")
            }
            return url
        }
    }

    private func developerWorkspaceExecutableURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("whisper.cpp", isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli")
    }

    private func developerWorkspaceLibraryURLs() throws -> [URL] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("whisper.cpp", isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)

        let candidates: [String: URL] = [
            "libwhisper.1.dylib": root.appendingPathComponent("src", isDirectory: true).appendingPathComponent("libwhisper.1.dylib"),
            "libggml.0.dylib": root.appendingPathComponent("ggml", isDirectory: true).appendingPathComponent("src", isDirectory: true).appendingPathComponent("libggml.0.dylib"),
            "libggml-cpu.0.dylib": root.appendingPathComponent("ggml", isDirectory: true).appendingPathComponent("src", isDirectory: true).appendingPathComponent("libggml-cpu.0.dylib"),
            "libggml-blas.0.dylib": root.appendingPathComponent("ggml", isDirectory: true).appendingPathComponent("src", isDirectory: true).appendingPathComponent("ggml-blas", isDirectory: true).appendingPathComponent("libggml-blas.0.dylib"),
            "libggml-metal.0.dylib": root.appendingPathComponent("ggml", isDirectory: true).appendingPathComponent("src", isDirectory: true).appendingPathComponent("ggml-metal", isDirectory: true).appendingPathComponent("libggml-metal.0.dylib"),
            "libggml-base.0.dylib": root.appendingPathComponent("ggml", isDirectory: true).appendingPathComponent("src", isDirectory: true).appendingPathComponent("libggml-base.0.dylib")
        ]

        return try requiredLibraryNames.map { name in
            guard let url = candidates[name], FileManager.default.fileExists(atPath: url.path) else {
                throw AppError.transcriptionConfigurationMissing("LoqBar could not find the required whisper library \(name) in the developer workspace.")
            }
            return url
        }
    }

    private func resolveLibraryURLs(for executableURL: URL) throws -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        process.arguments = ["-l", executableURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        let rpaths = outputText
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("path ") else { return nil }
                return trimmed
                    .replacingOccurrences(of: "path ", with: "")
                    .components(separatedBy: " (offset").first
            }

        let fileManager = FileManager.default

        return try requiredLibraryNames.map { libraryName in
            if let matchingURL = rpaths
                .map({ URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(libraryName) })
                .first(where: { fileManager.fileExists(atPath: $0.path) }) {
                return matchingURL
            }

            throw AppError.transcriptionConfigurationMissing(
                "LoqBar could not locate the required whisper library \(libraryName) next to the selected external whisper-cli."
            )
        }
    }

    private func installLibraries(
        source: (url: URL, description: String, libraryURLs: [URL]),
        destinationDirectory: URL
    ) throws -> String {
        for sourceURL in source.libraryURLs {
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try replaceFile(at: destinationURL, withContentsOf: sourceURL, sourceBasenameOverride: destinationURL.lastPathComponent)
        }

        return "Installed \(source.libraryURLs.count) required whisper libraries."
    }

    private func retargetExecutable(
        executableURL: URL,
        libraryDirectory: URL
    ) throws {
        let tool = URL(fileURLWithPath: "/usr/bin/install_name_tool")
        let fileManager = FileManager.default
        let executableDirectory = executableURL.deletingLastPathComponent()

        let candidateRPaths = [
            FileManager.default.currentDirectoryPath + "/tools/whisper.cpp/build/src",
            FileManager.default.currentDirectoryPath + "/tools/whisper.cpp/build/ggml/src",
            FileManager.default.currentDirectoryPath + "/tools/whisper.cpp/build/ggml/src/ggml-blas",
            FileManager.default.currentDirectoryPath + "/tools/whisper.cpp/build/ggml/src/ggml-metal"
        ]

        for oldPath in candidateRPaths {
            try runInstallNameTool(tool: tool, arguments: ["-delete_rpath", oldPath, executableURL.path], allowFailure: true)
        }

        try runInstallNameTool(
            tool: tool,
            arguments: ["-add_rpath", "@executable_path/../lib", executableURL.path],
            allowFailure: true
        )

        for libraryName in requiredLibraryNames {
            let libraryURL = libraryDirectory.appendingPathComponent(libraryName)
            guard fileManager.fileExists(atPath: libraryURL.path) else { continue }

            try runInstallNameTool(
                tool: tool,
                arguments: ["-id", "@rpath/\(libraryName)", libraryURL.path],
                allowFailure: false
            )
            try runInstallNameTool(
                tool: tool,
                arguments: ["-add_rpath", "@loader_path", libraryURL.path],
                allowFailure: true
            )
        }

        _ = executableDirectory
    }

    private func runInstallNameTool(tool: URL, arguments: [String], allowFailure: Bool) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = Pipe()
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || allowFailure else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppError.storageSetupFailed(
                message.isEmpty
                ? "LoqBar could not prepare the managed whisper runtime."
                : "LoqBar could not prepare the managed whisper runtime: \(message)"
            )
        }
    }

    private func makeExecutableIfPossible(at url: URL) {
        var permissions = stat()
        if stat(url.path, &permissions) == 0 {
            chmod(url.path, permissions.st_mode | S_IXUSR | S_IXGRP | S_IXOTH)
        }
    }
}
