import Foundation

struct OptimizedAudioFiles {
    let microphoneFileURL: URL?
    let systemAudioFileURL: URL?
    let notes: [String]
}

struct AudioStorageOptimizer {
    func optimize(_ capture: ActiveCaptureSession) throws -> OptimizedAudioFiles {
        let optimizedMicrophone = try optimizeIfPresent(
            inputURL: capture.microphoneFileURL,
            outputFileName: "microphone.flac"
        )
        let optimizedSystemAudio = try optimizeIfPresent(
            inputURL: capture.systemAudioFileURL,
            outputFileName: "system-audio.flac"
        )

        var notes: [String] = []
        if optimizedMicrophone != nil || optimizedSystemAudio != nil {
            notes.append("Audio optimized for storage as 16 kHz mono FLAC.")
        }

        return OptimizedAudioFiles(
            microphoneFileURL: optimizedMicrophone,
            systemAudioFileURL: optimizedSystemAudio,
            notes: notes
        )
    }

    private func optimizeIfPresent(inputURL: URL?, outputFileName: String) throws -> URL? {
        guard let inputURL else { return nil }

        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFileName)
        let normalizedWAVURL = inputURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try runAFConvert(
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                inputURL.path,
                normalizedWAVURL.path
            ],
            context: "normalize \(inputURL.lastPathComponent) for storage"
        )

        do {
            try runAFConvert(
                arguments: [
                    "-f", "flac",
                    normalizedWAVURL.path,
                    outputURL.path
                ],
                context: "encode \(inputURL.lastPathComponent) as FLAC"
            )
        } catch {
            try? FileManager.default.removeItem(at: normalizedWAVURL)
            throw error
        }

        try? FileManager.default.removeItem(at: normalizedWAVURL)

        try? FileManager.default.removeItem(at: inputURL)
        return outputURL
    }

    private func runAFConvert(arguments: [String], context: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty
                ? "Audio optimization could not \(context)."
                : "Audio optimization could not \(context): \(errorText)"
            throw AppError.storageSetupFailed(message)
        }
    }
}
