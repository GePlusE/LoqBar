import XCTest
@testable import LoqBar

final class TranscriptionServiceTests: XCTestCase {
    func testSplitSourceMergeDropsBlankAudioAndPrefersSystemAudioDuplicate() throws {
        let root = try makeTemporaryDirectory()
        let settings = try makeSettings(root: root, computeMode: .cpuOnly)
        let session = makeSession(
            audioSourceType: .appAudioPlusMicrophone,
            microphonePath: root.appendingPathComponent("microphone.flac").path,
            systemAudioPath: root.appendingPathComponent("system.flac").path
        )

        let fakeTranscriber = FakeAudioTranscriber(
            responses: [
                root.appendingPathComponent("system.flac").path: WhisperTranscription(
                    text: "Hello there",
                    language: "en",
                    segments: [
                        WhisperSegment(startTime: 0, endTime: 2.0, text: "Hello there"),
                        WhisperSegment(startTime: 4.0, endTime: 5.0, text: "[BLANK_AUDIO]")
                    ],
                    engineDescription: "fake-whisper",
                    notes: []
                ),
                root.appendingPathComponent("microphone.flac").path: WhisperTranscription(
                    text: "Hello there",
                    language: "en",
                    segments: [
                        WhisperSegment(startTime: 0.2, endTime: 2.1, text: "Hello there")
                    ],
                    engineDescription: "fake-whisper",
                    notes: []
                )
            ]
        )

        let service = TranscriptionService(whisperTranscriber: fakeTranscriber)
        let plan = service.makePlan(for: session)
        let content = try service.transcribe(plan: plan, session: session, settings: settings)

        XCTAssertEqual(content.segments.count, 1)
        XCTAssertEqual(content.segments.first?.source, PreferredTranscriptSource.systemAudio.rawValue)
        XCTAssertTrue(content.analysis.notes.contains(where: { $0.contains("low-value segment") }))
        XCTAssertTrue(content.analysis.notes.contains(where: { $0.contains("overlapping duplicate") }))
    }

    func testSourceLanguageDisagreementMarksTranscriptAsMixed() throws {
        let root = try makeTemporaryDirectory()
        let settings = try makeSettings(root: root, computeMode: .auto)
        let session = makeSession(
            audioSourceType: .appAudioPlusMicrophone,
            microphonePath: root.appendingPathComponent("microphone.flac").path,
            systemAudioPath: root.appendingPathComponent("system.flac").path
        )

        let fakeTranscriber = FakeAudioTranscriber(
            responses: [
                root.appendingPathComponent("system.flac").path: WhisperTranscription(
                    text: "Guten Morgen zusammen",
                    language: "de",
                    segments: [WhisperSegment(startTime: 0, endTime: 2, text: "Guten Morgen zusammen")],
                    engineDescription: "fake-whisper",
                    notes: []
                ),
                root.appendingPathComponent("microphone.flac").path: WhisperTranscription(
                    text: "Let's switch to English",
                    language: "en",
                    segments: [WhisperSegment(startTime: 2.2, endTime: 4.8, text: "Let's switch to English")],
                    engineDescription: "fake-whisper",
                    notes: []
                )
            ]
        )

        let service = TranscriptionService(whisperTranscriber: fakeTranscriber)
        let plan = service.makePlan(for: session)
        let content = try service.transcribe(plan: plan, session: session, settings: settings)

        XCTAssertEqual(content.language, "mixed")
        XCTAssertTrue(content.analysis.notes.contains(where: { $0.contains("Mixed-language session detected") }))
    }

    func testManyRemoteTurnsExpandSuggestedSpeakerRosterBeyondDetectedSpeakers() throws {
        let root = try makeTemporaryDirectory()
        let settings = try makeSettings(root: root, computeMode: .auto)
        let session = makeSession(
            audioSourceType: .appAudioPlusMicrophone,
            microphonePath: root.appendingPathComponent("microphone.flac").path,
            systemAudioPath: root.appendingPathComponent("system.flac").path
        )

        let remoteSegments = (0..<12).map { index in
            WhisperSegment(
                startTime: Double(index) * 4.0,
                endTime: Double(index) * 4.0 + 2.6,
                text: "Remote participant statement number \(index)"
            )
        }

        let fakeTranscriber = FakeAudioTranscriber(
            responses: [
                root.appendingPathComponent("system.flac").path: WhisperTranscription(
                    text: remoteSegments.map(\.text).joined(separator: " "),
                    language: "en",
                    segments: remoteSegments,
                    engineDescription: "fake-whisper",
                    notes: []
                ),
                root.appendingPathComponent("microphone.flac").path: WhisperTranscription(
                    text: "I am here locally",
                    language: "en",
                    segments: [WhisperSegment(startTime: 1.0, endTime: 2.0, text: "I am here locally")],
                    engineDescription: "fake-whisper",
                    notes: []
                )
            ]
        )

        let service = TranscriptionService(whisperTranscriber: fakeTranscriber)
        let plan = service.makePlan(for: session)
        let content = try service.transcribe(plan: plan, session: session, settings: settings)

        XCTAssertEqual(content.speakersDetected, 2)
        XCTAssertGreaterThan(content.suggestedSpeakerRosterCount, content.speakersDetected)
        XCTAssertEqual(content.suggestedSpeakerRosterCount, 5)
        XCTAssertTrue(content.analysis.notes.contains(where: { $0.contains("generic speaker slots heuristically") }))
    }

    private func makeSettings(root: URL, computeMode: TranscriptionComputeMode) throws -> AppSettings {
        let settings = AppSettings(
            storageRootFolder: root.path,
            audioRetentionPolicy: .days90,
            defaultCaptureMode: .auto,
            customVocabularyEntries: [],
            transcriptionModelIdentifier: "small",
            transcriptionComputeMode: computeMode,
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

        let executableURL = URL(fileURLWithPath: settings.managedTranscriptionExecutablePath)
        try createExecutable(at: executableURL)
        try createFile(at: URL(fileURLWithPath: settings.managedTranscriptionModelPath), contents: "model")
        return settings
    }

    private func makeSession(audioSourceType: AudioSourceType, microphonePath: String?, systemAudioPath: String?) -> SessionRecord {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return SessionRecord(
            id: UUID(),
            title: "Session",
            createdAt: now,
            startedAt: now,
            endedAt: now.addingTimeInterval(60),
            durationSeconds: 60,
            status: .completed,
            captureMode: .call,
            audioSourceType: audioSourceType,
            transcriptPath: nil,
            audioPath: microphonePath,
            systemAudioPath: systemAudioPath,
            language: "auto",
            transcriptionLanguageOverride: nil,
            speakerCount: 0,
            aliasMapping: [:],
            speakerAssignments: [:],
            transcriptEdits: [:],
            warningCount: 0,
            notes: "",
            sharedLinks: "",
            contextNotes: ""
        )
    }

    private func createExecutable(at url: URL) throws {
        try createFile(at: url, contents: "#!/bin/zsh\nexit 0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoqBarTranscriptionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}

private struct FakeAudioTranscriber: AudioTranscribing {
    let responses: [String: WhisperTranscription]

    func transcribe(audioFileURL: URL, configuration: WhisperConfiguration) throws -> WhisperTranscription {
        guard let response = responses[audioFileURL.path] else {
            throw AppError.transcriptionExecutionFailed("Missing fake transcription for \(audioFileURL.path)")
        }
        return response
    }
}
