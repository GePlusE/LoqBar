import Foundation

struct TranscriptExporter {
    func exportTranscript(for session: SessionRecord, settings: AppSettings, content: TranscriptContent) throws -> TranscriptExport {
        let folderURL = URL(fileURLWithPath: settings.transcriptOutputFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: session.startedAt)
        let fileURL = folderURL.appendingPathComponent("loqbar-\(timestamp).md")

        let markdown = buildMarkdown(for: session, content: content)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        return TranscriptExport(
            path: fileURL.path,
            warningCount: content.warningCount,
            speakersDetected: content.speakersDetected,
            summary: content.summary,
            planNotes: content.analysis.notes
        )
    }

    private func buildMarkdown(for session: SessionRecord, content: TranscriptContent) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let start = session.startedAt
        let end = session.endedAt ?? start

        let sourceSummary = content.analysis.primarySources.joined(separator: ", ")
        let analysisNotes = content.analysis.notes.map { "- \($0)" }.joined(separator: "\n")
        let transcriptBody = content.segments.map { segment in
            let marker = segment.lowConfidence ? "[low confidence] " : ""
            return "[\(isoTimestamp(segment.absoluteTimestamp)) | +\(relativeTimestamp(segment.relativeOffset))] \(segment.speakerLabel): \(marker)\(segment.text)"
        }.joined(separator: "\n\n")

        return """
        ---
        title: \(content.title)
        date: \(dateFormatter.string(from: start))
        start_time: "\(timeFormatter.string(from: start))"
        end_time: "\(timeFormatter.string(from: end))"
        duration_seconds: \(session.durationSeconds)
        language: \(session.language)
        capture_mode: \(session.captureMode.rawValue)
        audio_source: \(session.audioSourceType.rawValue)
        speakers_detected: \(content.speakersDetected)
        speaker_aliases:
          Speaker1: ""
          Speaker2: ""
        confidence_warnings: \(content.warningCount)
        audio_file: "\(session.audioPath ?? "")"
        system_audio_file: "\(session.systemAudioPath ?? "")"
        preferred_transcript_sources: "\(sourceSummary)"
        ---

        # Transcript

        \(transcriptBody)

        # Analysis Notes

        \(analysisNotes)
        """
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func relativeTimestamp(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
