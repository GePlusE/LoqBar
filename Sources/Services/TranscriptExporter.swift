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
        let manualCorrectionCount = session.transcriptEdits.count
        let speakerReassignmentCount = session.speakerAssignments.count
        let transcriptBody = content.segments.enumerated().map { index, segment in
            let marker = segment.lowConfidence ? "[low confidence] " : ""
            let key = transcriptSegmentKey(for: segment)
            let activeEdit = session.transcriptEdits[key]
            let assignedSpeakerLabel = session.speakerAssignments[key] ?? segment.speakerLabel
            let originalText = "\(marker)\(activeEdit?.originalText ?? segment.text)"
            let displayText = "\(marker)\(activeEdit?.editedText ?? segment.text)"
            let timestampMarker = "\(isoTimestamp(segment.absoluteTimestamp)) | +\(relativeTimestamp(segment.relativeOffset))"
            let speakerDisplay = displaySpeakerName(for: assignedSpeakerLabel, aliases: session.aliasMapping)
            var lines = ["[\(timestampMarker)] \(speakerDisplay): \(displayText)"]

            if speakerDisplay != assignedSpeakerLabel {
                lines.append("_Speaker label: \(assignedSpeakerLabel)_")
            } else if assignedSpeakerLabel != segment.speakerLabel {
                lines.append("_Speaker label: \(assignedSpeakerLabel)_")
            }

            if assignedSpeakerLabel != segment.speakerLabel {
                lines.append("_Original speaker label: \(segment.speakerLabel)_")
            }

            if displayText != originalText {
                lines.append("_Manual correction from original transcript: \(originalText)_")
            }

            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let agentSegmentsBody = content.segments.enumerated().map { index, segment in
            let marker = segment.lowConfidence ? "[low confidence] " : ""
            let key = transcriptSegmentKey(for: segment)
            let activeEdit = session.transcriptEdits[key]
            let assignedSpeakerLabel = session.speakerAssignments[key] ?? segment.speakerLabel
            let originalText = "\(marker)\(activeEdit?.originalText ?? segment.text)"
            let displayText = "\(marker)\(activeEdit?.editedText ?? segment.text)"
            let timestampMarker = "\(isoTimestamp(segment.absoluteTimestamp)) | +\(relativeTimestamp(segment.relativeOffset))"
            let speakerDisplay = displaySpeakerName(for: assignedSpeakerLabel, aliases: session.aliasMapping)
            let agentSegmentID = String(format: "seg-%04d", index + 1)

            return """
            - id: "\(agentSegmentID)"
              marker: "\(escapeForYAML(timestampMarker))"
              speaker_label: "\(escapeForYAML(assignedSpeakerLabel))"
              speaker_name: "\(escapeForYAML(speakerDisplay))"
              original_speaker_label: "\(escapeForYAML(segment.speakerLabel))"
              source: "\(escapeForYAML(segment.source))"
              edited: \(displayText != originalText)
              text: "\(escapeForYAML(displayText))"
              original_text: "\(escapeForYAML(originalText))"
            """
        }.joined(separator: "\n")
        let speakerAliases = session.speakerLabels.map { label in
            "  \(label): \"\(escapeForYAML(session.aliasMapping[label] ?? ""))\""
        }.joined(separator: "\n")

        return """
        ---
        schema_version: 2
        title: \(content.title)
        date: \(dateFormatter.string(from: start))
        start_time: "\(timeFormatter.string(from: start))"
        end_time: "\(timeFormatter.string(from: end))"
        duration_seconds: \(session.durationSeconds)
        language: \(content.language)
        capture_mode: \(session.captureMode.rawValue)
        audio_source: \(session.audioSourceType.rawValue)
        speakers_detected: \(content.speakersDetected)
        speaker_aliases:
        \(speakerAliases.isEmpty ? "  {}" : speakerAliases)
        confidence_warnings: \(content.warningCount)
        manual_corrections: \(manualCorrectionCount)
        speaker_reassignments: \(speakerReassignmentCount)
        audio_file: "\(session.audioPath ?? "")"
        system_audio_file: "\(session.systemAudioPath ?? "")"
        preferred_transcript_sources: "\(sourceSummary)"
        transcription_engine: "\(content.analysis.engineDescription)"
        ---

        # Transcript

        \(transcriptBody)

        # Agent Segments

        \(agentSegmentsBody)

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

    private func transcriptSegmentKey(for segment: TranscriptSegment) -> String {
        "\(isoTimestamp(segment.absoluteTimestamp)) | +\(relativeTimestamp(segment.relativeOffset))|\(segment.speakerLabel)"
    }

    private func displaySpeakerName(for speakerLabel: String, aliases: [String: String]) -> String {
        let alias = aliases[speakerLabel]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? speakerLabel : alias
    }

    private func escapeForYAML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
