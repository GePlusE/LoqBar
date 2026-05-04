import XCTest
@testable import LoqBar

final class CoreModelTests: XCTestCase {
    func testManagedLargeModelMapsToLargeV3File() {
        let settings = makeSettings(modelIdentifier: "large")
        XCTAssertEqual(settings.managedTranscriptionModelPath, tempRoot().appendingPathComponent(".loqbar/models/ggml-large-v3.bin").path)
    }

    func testManagedSetupStatusReportsMissingModelWhenRuntimeExists() throws {
        let root = try makeTemporaryDirectory()
        let settings = makeSettings(storageRoot: root.path, modelIdentifier: "medium")

        let executableURL = URL(fileURLWithPath: settings.managedTranscriptionExecutablePath)
        try createExecutable(at: executableURL)

        let status = TranscriptionSetupStatus.from(settings: settings)

        XCTAssertEqual(status.state, .managedModelNeedsInstall)
        XCTAssertEqual(status.activeSourceLabel, "Managed setup needs a model")
        XCTAssertTrue(status.detailLines.contains(where: { $0.contains("Selected model: Medium") }))
    }

    func testManagedSetupStatusReportsReadyWhenExecutableAndModelExist() throws {
        let root = try makeTemporaryDirectory()
        let settings = makeSettings(storageRoot: root.path, modelIdentifier: "small")

        try createExecutable(at: URL(fileURLWithPath: settings.managedTranscriptionExecutablePath))
        try createFile(at: URL(fileURLWithPath: settings.managedTranscriptionModelPath), contents: "model")

        let status = TranscriptionSetupStatus.from(settings: settings)

        XCTAssertEqual(status.state, .readyManaged)
        XCTAssertEqual(status.activeSourceLabel, "Managed")
        XCTAssertTrue(status.detailLines.contains(where: { $0.contains("Selected model: Small") }))
    }

    func testExternalSetupTakesPriorityOverManagedSetup() throws {
        let root = try makeTemporaryDirectory()
        let executableURL = root.appendingPathComponent("external-whisper-cli")
        let modelURL = root.appendingPathComponent("external-model.bin")
        try createExecutable(at: executableURL)
        try createFile(at: modelURL, contents: "model")

        var settings = makeSettings(storageRoot: root.path, modelIdentifier: "base")
        settings.transcriptionExecutablePath = executableURL.path
        settings.transcriptionModelPath = modelURL.path

        let status = TranscriptionSetupStatus.from(settings: settings)

        XCTAssertEqual(status.state, .readyExternal)
        XCTAssertEqual(status.activeSourceLabel, "External")
        XCTAssertTrue(status.detailLines.contains(where: { $0.contains(executableURL.path) }))
    }

    func testWhisperConfigurationCarriesSelectedComputeMode() throws {
        let root = try makeTemporaryDirectory()
        var settings = makeSettings(storageRoot: root.path, modelIdentifier: "small")
        settings.transcriptionComputeMode = .gpuPreferred

        try createExecutable(at: URL(fileURLWithPath: settings.managedTranscriptionExecutablePath))
        try createFile(at: URL(fileURLWithPath: settings.managedTranscriptionModelPath), contents: "model")

        let configuration = try XCTUnwrap(WhisperConfiguration.from(settings: settings))

        XCTAssertEqual(configuration.computeMode, .gpuPreferred)
    }

    func testLegacySettingsDecodeDefaultsToAutoComputeMode() throws {
        let json = """
        {
          "storageRootFolder": "\(tempRoot().path)",
          "audioRetentionPolicy": "days90",
          "defaultCaptureMode": "auto",
          "customVocabularyEntries": [],
          "transcriptionModelIdentifier": "base",
          "transcriptionExecutablePath": "",
          "transcriptionModelPath": "",
          "transcriptionLanguage": "auto",
          "autoCleanupEnabled": true,
          "launchAtLoginEnabled": false,
          "firstRunCompleted": false
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.transcriptionComputeMode, .auto)
    }

    func testSpeakerLabelsExpandToCoverAliasesAndReassignments() {
        let session = SessionRecord(
            id: UUID(),
            title: "Test",
            createdAt: .now,
            startedAt: .now,
            endedAt: nil,
            durationSeconds: 0,
            status: .completed,
            captureMode: .call,
            audioSourceType: .appAudioPlusMicrophone,
            transcriptPath: nil,
            audioPath: nil,
            systemAudioPath: nil,
            language: "en",
            transcriptionLanguageOverride: nil,
            speakerCount: 2,
            aliasMapping: ["Speaker6": "Alex"],
            speakerAssignments: ["seg-1": "Speaker4"],
            transcriptEdits: [:],
            warningCount: 0,
            notes: "",
            sharedLinks: "",
            contextNotes: ""
        )

        XCTAssertEqual(session.speakerLabels, [
            "Speaker1", "Speaker2", "Speaker3", "Speaker4", "Speaker5", "Speaker6"
        ])
    }

    func testLegacySessionDecodingBackfillsNewFields() throws {
        let json = """
        {
          "id": "\(UUID())",
          "title": "Legacy Session",
          "createdAt": "2026-04-28T10:00:00Z",
          "startedAt": "2026-04-28T10:00:00Z",
          "endedAt": "2026-04-28T10:05:00Z",
          "durationSeconds": 300,
          "status": "completed",
          "captureMode": "call",
          "audioSourceType": "appAudioPlusMicrophone",
          "transcriptPath": null,
          "audioPath": null,
          "systemAudioPath": null,
          "language": "de",
          "speakerCount": 2,
          "aliasMapping": { "Speaker1": "Host" },
          "warningCount": 0,
          "notes": "done"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(SessionRecord.self, from: Data(json.utf8))

        XCTAssertEqual(session.transcriptEdits, [:])
        XCTAssertEqual(session.speakerAssignments, [:])
        XCTAssertEqual(session.sharedLinks, "")
        XCTAssertEqual(session.contextNotes, "")
        XCTAssertNil(session.transcriptionLanguageOverride)
    }

    private func makeSettings(storageRoot: String? = nil, modelIdentifier: String) -> AppSettings {
        AppSettings(
            storageRootFolder: storageRoot ?? tempRoot().path,
            audioRetentionPolicy: .days90,
            defaultCaptureMode: .auto,
            customVocabularyEntries: [],
            transcriptionModelIdentifier: modelIdentifier,
            transcriptionComputeMode: .auto,
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
        let root = tempRoot().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LoqBarTests", isDirectory: true)
    }
}
