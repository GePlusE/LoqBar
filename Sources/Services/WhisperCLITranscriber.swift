import Foundation

protocol AudioTranscribing {
    func transcribe(audioFileURL: URL, configuration: WhisperConfiguration) throws -> WhisperTranscription
}

struct WhisperCLITranscriber: AudioTranscribing {
    private let logger = AppEventLogger.shared

    func transcribe(audioFileURL: URL, configuration: WhisperConfiguration) throws -> WhisperTranscription {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw AppError.transcriptionConfigurationMissing("LoqBar found a transcription executable path, but it is not usable: \(configuration.executableURL.path)")
        }
        guard fileManager.fileExists(atPath: configuration.modelURL.path) else {
            throw AppError.transcriptionConfigurationMissing("LoqBar could not find the managed transcription model file: \(configuration.modelURL.path)")
        }
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw AppError.transcriptionExecutionFailed("The audio file to transcribe could not be found: \(audioFileURL.path)")
        }

        let outputDirectory = StoragePaths.transcriptionScratchFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let transcriptionStartedAt = Date()
        logger.log(
            category: "transcription",
            name: "transcribe_started",
            metadata: [
                "audio_file": audioFileURL.lastPathComponent,
                "model": configuration.modelURL.lastPathComponent,
                "language": configuration.language ?? "auto",
                "compute_mode": configuration.computeMode.rawValue
            ]
        )

        let preparedAudioURL = try prepareAudioInputIfNeeded(audioFileURL, outputDirectory: outputDirectory)

        let outputBaseURL = outputDirectory.appendingPathComponent("transcript")
        let jsonURL = outputBaseURL.appendingPathExtension("json")
        let txtURL = outputBaseURL.appendingPathExtension("txt")
        let execution = try executeWhisperCLI(
            preparedAudioURL: preparedAudioURL,
            outputBaseURL: outputBaseURL,
            configuration: configuration
        )

        let jsonData = try? Data(contentsOf: jsonURL)
        let textData = try? Data(contentsOf: txtURL)

        let parsed = jsonData.flatMap(parseJSONTranscription(data:))
        let text = parsed?.text
            ?? textData.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        let segments = parsed?.segments ?? fallbackSegments(from: text)
        let language = parsed?.language ?? configuration.language

        logger.log(
            category: "transcription",
            name: "transcribe_finished",
            metadata: [
                "audio_file": audioFileURL.lastPathComponent,
                "engine": execution.engineDescription,
                "language": language ?? "unknown",
                "segment_count": String(segments.count),
                "duration_ms": String(Int(Date().timeIntervalSince(transcriptionStartedAt) * 1000)),
                "note_count": String(execution.notes.count)
            ]
        )

        return WhisperTranscription(
            text: text,
            language: language,
            segments: segments,
            engineDescription: execution.engineDescription,
            notes: execution.notes
        )
    }

    private func executeWhisperCLI(
        preparedAudioURL: URL,
        outputBaseURL: URL,
        configuration: WhisperConfiguration
    ) throws -> WhisperCLIExecutionResult {
        let attempts = executionAttempts(for: configuration)
        var failures: [WhisperCLIAttemptFailure] = []

        for (index, attempt) in attempts.enumerated() {
            let attemptStartedAt = Date()
            logger.log(
                category: "transcription",
                name: "whisper_attempt_started",
                metadata: [
                    "audio_file": preparedAudioURL.lastPathComponent,
                    "attempt_index": String(index),
                    "attempt_mode": attempt.computeMode.description,
                    "model": configuration.modelURL.lastPathComponent,
                    "language": configuration.language ?? "auto"
                ]
            )
            let result = try runWhisperCLI(
                preparedAudioURL: preparedAudioURL,
                outputBaseURL: outputBaseURL,
                configuration: configuration,
                attempt: attempt
            )

            logger.log(
                category: "transcription",
                name: result.terminationStatus == 0 ? "whisper_attempt_succeeded" : "whisper_attempt_failed",
                metadata: [
                    "audio_file": preparedAudioURL.lastPathComponent,
                    "attempt_index": String(index),
                    "attempt_mode": attempt.computeMode.description,
                    "termination_status": String(result.terminationStatus),
                    "duration_ms": String(Int(Date().timeIntervalSince(attemptStartedAt) * 1000)),
                    "stderr": result.stderrText.nilIfEmpty ?? "none"
                ]
            )

            if result.terminationStatus == 0 {
                var notes: [String] = []
                if index > 0, let previousFailure = failures.last {
                    notes.append("LoqBar retried transcription in CPU-only mode after the accelerated path failed: \(previousFailure.summary)")
                } else if attempt.computeMode == .gpu {
                    notes.append("LoqBar used GPU/Metal acceleration for this transcription run.")
                }

                return WhisperCLIExecutionResult(
                    engineDescription: attempt.computeMode == .cpuOnly ? "whisper-cli (CPU)" : "whisper-cli (GPU/Metal)",
                    notes: notes
                )
            }

            let failure = WhisperCLIAttemptFailure(
                mode: attempt.computeMode,
                terminationStatus: result.terminationStatus,
                stderrText: result.stderrText
            )
            failures.append(failure)
        }

        let failureSummary = failures.map(\.summary).joined(separator: " Then ")
        throw AppError.transcriptionExecutionFailed(failureSummary)
    }

    private func executionAttempts(for configuration: WhisperConfiguration) -> [WhisperCLIExecutionAttempt] {
        switch configuration.computeMode {
        case .cpuOnly:
            return [.cpuOnly]
        case .auto, .gpuPreferred:
            return [.gpu, .cpuOnly]
        }
    }

    private func runWhisperCLI(
        preparedAudioURL: URL,
        outputBaseURL: URL,
        configuration: WhisperConfiguration,
        attempt: WhisperCLIExecutionAttempt
    ) throws -> WhisperCLIExecutionOutcome {
        let process = Process()
        process.executableURL = configuration.executableURL

        var arguments = [
            "-m", configuration.modelURL.path,
            "-f", preparedAudioURL.path,
            "--output-json",
            "--output-txt",
            "--output-file", outputBaseURL.path
        ]

        if attempt.computeMode == .cpuOnly {
            arguments.append("-ng")
        }

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

        return WhisperCLIExecutionOutcome(
            terminationStatus: process.terminationStatus,
            stderrText: stderrText
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
            engineDescription: "whisper-cli",
            notes: []
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

        let conversionStartedAt = Date()
        logger.log(
            category: "transcription",
            name: "audio_conversion_started",
            metadata: [
                "source_file": audioFileURL.lastPathComponent,
                "target_file": convertedURL.lastPathComponent
            ]
        )

        try process.run()
        process.waitUntilExit()

        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        logger.log(
            category: "transcription",
            name: process.terminationStatus == 0 ? "audio_conversion_finished" : "audio_conversion_failed",
            metadata: [
                "source_file": audioFileURL.lastPathComponent,
                "target_file": convertedURL.lastPathComponent,
                "duration_ms": String(Int(Date().timeIntervalSince(conversionStartedAt) * 1000)),
                "termination_status": String(process.terminationStatus),
                "stderr": errorText.nilIfEmpty ?? "none"
            ]
        )

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

private enum WhisperCLIAttemptComputeMode {
    case gpu
    case cpuOnly

    var description: String {
        switch self {
        case .gpu:
            return "gpu"
        case .cpuOnly:
            return "cpu_only"
        }
    }
}

private struct WhisperCLIExecutionAttempt {
    let computeMode: WhisperCLIAttemptComputeMode

    static let gpu = WhisperCLIExecutionAttempt(computeMode: .gpu)
    static let cpuOnly = WhisperCLIExecutionAttempt(computeMode: .cpuOnly)
}

private struct WhisperCLIExecutionOutcome {
    let terminationStatus: Int32
    let stderrText: String
}

private struct WhisperCLIExecutionResult {
    let engineDescription: String
    let notes: [String]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct WhisperCLIAttemptFailure {
    let mode: WhisperCLIAttemptComputeMode
    let terminationStatus: Int32
    let stderrText: String

    var summary: String {
        let modeLabel = mode == .gpu ? "GPU/Metal attempt" : "CPU-only attempt"
        if stderrText.isEmpty {
            return "\(modeLabel) exited with status \(terminationStatus)."
        }
        return "\(modeLabel) exited with status \(terminationStatus): \(stderrText)"
    }
}
