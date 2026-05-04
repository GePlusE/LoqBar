import XCTest
@testable import LoqBar

final class AppEventLoggerTests: XCTestCase {
    func testLoggerWritesJSONLWithStableFields() throws {
        let root = try makeTemporaryDirectory()
        let logURL = root.appendingPathComponent("events.jsonl")
        let logger = AppEventLogger(logFileURL: logURL)
        let sessionID = UUID()

        logger.log(
            category: "transcription",
            name: "transcribe_finished",
            sessionID: sessionID,
            metadata: [
                "duration_ms": "1234",
                "compute_mode": "auto"
            ]
        )

        let logText = try String(contentsOf: logURL, encoding: .utf8)
        let line = try XCTUnwrap(logText.split(separator: "\n").first)
        let data = Data(line.utf8)
        let event = try JSONDecoder().decode(AppLogEvent.self, from: data)

        XCTAssertEqual(event.category, "transcription")
        XCTAssertEqual(event.name, "transcribe_finished")
        XCTAssertEqual(event.sessionID, sessionID.uuidString)
        XCTAssertEqual(event.metadata["duration_ms"], "1234")
        XCTAssertEqual(event.metadata["compute_mode"], "auto")
        XCTAssertFalse(event.timestamp.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoqBarLoggerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}
