import Foundation

struct TranscriptExporter {
    func exportTranscript(for session: SessionRecord, settings: AppSettings) throws -> TranscriptExport {
        let folderURL = URL(fileURLWithPath: settings.transcriptOutputFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: session.startedAt)
        let fileURL = folderURL.appendingPathComponent("loqbar-\(timestamp).md")

        let markdown = buildMarkdown(for: session)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        return TranscriptExport(
            path: fileURL.path,
            warningCount: 1,
            speakersDetected: 2,
            summary: "Sample local export complete. Recording and transcription engines still need implementation."
        )
    }

    private func buildMarkdown(for session: SessionRecord) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let start = session.startedAt
        let end = session.endedAt ?? start

        return """
        ---
        title: \(session.title)
        date: \(dateFormatter.string(from: start))
        start_time: "\(timeFormatter.string(from: start))"
        end_time: "\(timeFormatter.string(from: end))"
        duration_seconds: \(session.durationSeconds)
        language: \(session.language)
        capture_mode: \(session.captureMode.rawValue)
        audio_source: \(session.audioSourceType.rawValue)
        speakers_detected: 2
        speaker_aliases:
          Speaker1: ""
          Speaker2: ""
        confidence_warnings: 1
        audio_file: ""
        ---

        # Transcript

        [\(isoTimestamp(start)) | +00:00:04] Speaker1: Sample transcript export created by the LoqBar scaffold.

        [\(isoTimestamp(start.addingTimeInterval(8))) | +00:00:12] Speaker2: The real audio capture and local transcription pipeline still need to be implemented.

        [\(isoTimestamp(start.addingTimeInterval(28))) | +00:00:32] Speaker1: [low confidence] Teams headphone call capture should be validated as the first engineering spike.
        """
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
