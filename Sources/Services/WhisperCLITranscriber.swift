import Foundation

struct WhisperCLITranscriber {
    func transcribe(audioFileURL: URL, configuration: WhisperConfiguration) throws -> WhisperTranscription {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw AppError.transcriptionConfigurationMissing("The configured whisper executable is not usable. Check the `whisper-cli path` in Settings: \(configuration.executableURL.path)")
        }
        guard fileManager.fileExists(atPath: configuration.modelURL.path) else {
            throw AppError.transcriptionConfigurationMissing("The configured whisper model file does not exist. Check the `Model file path` in Settings: \(configuration.modelURL.path)")
        }
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw AppError.transcriptionExecutionFailed("The audio file to transcribe could not be found: \(audioFileURL.path)")
        }

        let outputDirectory = StoragePaths.transcriptionScratchFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let preparedAudioURL = try prepareAudioInputIfNeeded(audioFileURL, outputDirectory: outputDirectory)

        let outputBaseURL = outputDirectory.appendingPathComponent("transcript")
        let jsonURL = outputBaseURL.appendingPathExtension("json")
        let txtURL = outputBaseURL.appendingPathExtension("txt")

        let process = Process()
        process.executableURL = configuration.executableURL

        var arguments = [
            "-m", configuration.modelURL.path,
            "-f", preparedAudioURL.path,
            "-ng",
            "--output-json",
            "--output-txt",
            "--output-file", outputBaseURL.path
        ]

        if let language = configuration.language {
            arguments += ["-l", language]
        }

        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrText.isEmpty
                ? "whisper-cli exited with status \(process.terminationStatus)."
                : "whisper-cli exited with status \(process.terminationStatus): \(stderrText)"
            throw AppError.transcriptionExecutionFailed(message)
        }

        let jsonData = try? Data(contentsOf: jsonURL)
        let textData = try? Data(contentsOf: txtURL)

        let parsed = jsonData.flatMap(parseJSONTranscription(data:))
        let text = parsed?.text
            ?? textData.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        let segments = parsed?.segments ?? fallbackSegments(from: text)
        let language = parsed?.language ?? configuration.language

        return WhisperTranscription(
            text: text,
            language: language,
            segments: segments,
            engineDescription: "whisper-cli"
        )
    }

    private func parseJSONTranscription(data: Data) -> WhisperTranscription? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let language = (json["result"] as? [String: Any])?["language"] as? String
        let rawSegments = json["transcription"] as? [[String: Any]] ?? []

        let segments = rawSegments.compactMap { segmentJSON -> WhisperSegment? in
            let text = (segmentJSON["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }

            let offsets = segmentJSON["offsets"] as? [String: Any]
            let fromMilliseconds = numberValue(offsets?["from"]) ?? 0
            let toMilliseconds = numberValue(offsets?["to"]) ?? fromMilliseconds

            return WhisperSegment(
                startTime: fromMilliseconds / 1000,
                endTime: toMilliseconds / 1000,
                text: text
            )
        }

        let fullText = segments.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return WhisperTranscription(
            text: fullText,
            language: language,
            segments: segments,
            engineDescription: "whisper-cli"
        )
    }

    private func fallbackSegments(from text: String) -> [WhisperSegment] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return [WhisperSegment(startTime: 0, endTime: 0, text: normalized)]
    }

    private func prepareAudioInputIfNeeded(_ audioFileURL: URL, outputDirectory: URL) throws -> URL {
        let supportedExtensions = ["wav", "flac", "mp3", "ogg"]
        if supportedExtensions.contains(audioFileURL.pathExtension.lowercased()) {
            return audioFileURL
        }

        let convertedURL = outputDirectory.appendingPathComponent(audioFileURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            audioFileURL.path,
            convertedURL.path
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty
                ? "LoqBar could not convert \(audioFileURL.lastPathComponent) into a transcription-friendly WAV file."
                : "LoqBar could not convert \(audioFileURL.lastPathComponent) into WAV: \(errorText)"
            throw AppError.transcriptionExecutionFailed(message)
        }

        return convertedURL
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }
}
