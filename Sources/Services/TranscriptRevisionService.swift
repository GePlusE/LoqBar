import Foundation

struct EditableTranscriptSegment: Identifiable, Hashable {
    let key: String
    let timestamp: String
    let originalSpeakerLabel: String
    let assignedSpeakerLabel: String
    let originalText: String
    let currentText: String

    var id: String { key }
    var isEdited: Bool { currentText != originalText }
    var isReassigned: Bool { assignedSpeakerLabel != originalSpeakerLabel }
}

private struct AgentSegmentMetadata {
    let id: String
    let source: String
}

struct TranscriptRevisionService {
    func loadEditableSegments(from transcriptPath: String, session: SessionRecord) -> [EditableTranscriptSegment] {
        guard let markdown = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return []
        }

        return parseTranscriptSection(from: markdown).map { parsed in
            let edit = session.transcriptEdits[parsed.key]
            let assignedSpeakerLabel = session.speakerAssignments[parsed.key] ?? parsed.assignedSpeakerLabel
            return EditableTranscriptSegment(
                key: parsed.key,
                timestamp: parsed.timestamp,
                originalSpeakerLabel: parsed.originalSpeakerLabel,
                assignedSpeakerLabel: assignedSpeakerLabel,
                originalText: edit?.originalText ?? parsed.originalText,
                currentText: edit?.editedText ?? parsed.currentText
            )
        }
    }

    func applyEdits(
        to session: SessionRecord
    ) throws {
        try refreshTranscriptPresentation(for: session)
    }

    func refreshTranscriptPresentation(for session: SessionRecord) throws {
        guard let transcriptPath = session.transcriptPath else { return }
        let fileURL = URL(fileURLWithPath: transcriptPath)
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let rebuilt = try rewriteTranscriptSection(in: markdown, session: session)
        try rebuilt.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func segmentKey(timestamp: String, speakerLabel: String) -> String {
        "\(timestamp)|\(speakerLabel)"
    }

    private func rewriteTranscriptSection(
        in markdown: String,
        session: SessionRecord
    ) throws -> String {
        let transcriptMarker = "# Transcript"
        let agentMarker = "# Agent Segments"
        let contextMarker = "# Session Context"
        let analysisMarker = "# Analysis Notes"

        guard let transcriptRange = markdown.range(of: transcriptMarker) else {
            throw AppError.transcriptExportFailed("LoqBar could not find the transcript section while saving manual transcript edits.")
        }

        let afterTranscript = markdown[transcriptRange.upperBound...]
        let agentRangeInTail = afterTranscript.range(of: agentMarker)

        let header = String(markdown[..<transcriptRange.lowerBound])
        let transcriptBodyRaw: String
        let agentBodyRaw: String
        let analysisBodyRaw: String

        if let agentRangeInTail {
            transcriptBodyRaw = String(afterTranscript[..<agentRangeInTail.lowerBound])
            let afterAgent = afterTranscript[agentRangeInTail.upperBound...]

            if let contextRangeAfterAgent = afterAgent.range(of: contextMarker) {
                agentBodyRaw = String(afterAgent[..<contextRangeAfterAgent.lowerBound])
                let afterContext = afterAgent[contextRangeAfterAgent.upperBound...]

                if let analysisRangeAfterContext = afterContext.range(of: analysisMarker) {
                    analysisBodyRaw = String(afterContext[analysisRangeAfterContext.upperBound...])
                } else {
                    analysisBodyRaw = ""
                }
            } else if let analysisRangeAfterAgent = afterAgent.range(of: analysisMarker) {
                agentBodyRaw = String(afterAgent[..<analysisRangeAfterAgent.lowerBound])
                analysisBodyRaw = String(afterAgent[analysisRangeAfterAgent.upperBound...])
            } else {
                agentBodyRaw = String(afterAgent)
                analysisBodyRaw = ""
            }
        } else {
            transcriptBodyRaw = String(afterTranscript)
            agentBodyRaw = ""
            analysisBodyRaw = ""
        }

        let segments = parseTranscriptSection(from: transcriptMarker + transcriptBodyRaw)
        let agentMetadata = parseAgentSegmentMetadata(from: agentBodyRaw)
        let rebuiltBody = segments.map { segment in
            let activeEdit = session.transcriptEdits[segment.key]
            let currentText = activeEdit?.editedText ?? baseTranscriptText(for: segment)
            let originalText = activeEdit?.originalText ?? segment.originalText
            let assignedSpeakerLabel = session.speakerAssignments[segment.key] ?? segment.assignedSpeakerLabel
            let displaySpeaker = displaySpeakerName(for: assignedSpeakerLabel, aliasMapping: session.aliasMapping)
            var lines = ["[\(segment.timestamp)] \(displaySpeaker): \(currentText)"]

            if displaySpeaker != assignedSpeakerLabel {
                lines.append("_Speaker label: \(assignedSpeakerLabel)_")
            } else if assignedSpeakerLabel != segment.originalSpeakerLabel {
                lines.append("_Speaker label: \(assignedSpeakerLabel)_")
            }

            if assignedSpeakerLabel != segment.originalSpeakerLabel {
                lines.append("_Original speaker label: \(segment.originalSpeakerLabel)_")
            }

            if currentText != originalText {
                lines.append("_Manual correction from original transcript: \(originalText)_")
            }

            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let rebuiltAgentBody = segments.enumerated().map { index, segment in
            let activeEdit = session.transcriptEdits[segment.key]
            let currentText = activeEdit?.editedText ?? baseTranscriptText(for: segment)
            let originalText = activeEdit?.originalText ?? segment.originalText
            let assignedSpeakerLabel = session.speakerAssignments[segment.key] ?? segment.assignedSpeakerLabel
            let speakerDisplay = displaySpeakerName(for: assignedSpeakerLabel, aliasMapping: session.aliasMapping)
            let metadata = agentMetadata[segment.key]
            let segmentID = metadata?.id ?? String(format: "seg-%04d", index + 1)
            let source = metadata?.source ?? "unknown"

            return """
            - id: "\(segmentID)"
              marker: "\(escapeForYAML(segment.timestamp))"
              speaker_label: "\(escapeForYAML(assignedSpeakerLabel))"
              speaker_name: "\(escapeForYAML(speakerDisplay))"
              original_speaker_label: "\(escapeForYAML(segment.originalSpeakerLabel))"
              source: "\(escapeForYAML(source))"
              edited: \(currentText != originalText)
              text: "\(escapeForYAML(currentText))"
              original_text: "\(escapeForYAML(originalText))"
            """
        }.joined(separator: "\n")

        let normalizedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnalysis = analysisBodyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let rebuiltContext = buildSessionContextSection(for: session)

        let updatedHeader = rebuildHeader(from: normalizedHeader, session: session)

        if normalizedAnalysis.isEmpty {
            return "\(updatedHeader)\n\n\(rebuiltBody)\n\n# Agent Segments\n\n\(rebuiltAgentBody)\n\n\(rebuiltContext)\n"
        }

        return "\(updatedHeader)\n\n\(rebuiltBody)\n\n# Agent Segments\n\n\(rebuiltAgentBody)\n\n\(rebuiltContext)\n\n# Analysis Notes\n\n\(normalizedAnalysis)\n"
    }

    private func parseTranscriptSection(from markdown: String) -> [EditableTranscriptSegment] {
        let transcriptSection = markdown
            .components(separatedBy: "# Transcript")
            .dropFirst()
            .joined(separator: "# Transcript")
            .components(separatedBy: "# Agent Segments")
            .first?
            .components(separatedBy: "# Analysis Notes")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !transcriptSection.isEmpty else { return [] }

        let rawBlocks = transcriptSection
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return rawBlocks.compactMap(parseSegmentBlock(_:))
    }

    private func parseSegmentBlock(_ block: String) -> EditableTranscriptSegment? {
        let lines = block
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first,
              firstLine.hasPrefix("["),
              let closingBracketIndex = firstLine.firstIndex(of: "]"),
              let speakerSeparatorRange = firstLine.range(of: ": ") else {
            return nil
        }

        let timestamp = String(firstLine[..<closingBracketIndex]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let speakerStart = firstLine.index(after: closingBracketIndex)
        var assignedSpeakerLabel = firstLine[speakerStart..<speakerSeparatorRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = firstLine[speakerSeparatorRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var originalText = currentText
        var originalSpeakerLabel = assignedSpeakerLabel

        if let speakerLabelLine = lines.dropFirst().first(where: { $0.hasPrefix("_Speaker label: ") }) {
            assignedSpeakerLabel = speakerLabelLine
                .replacingOccurrences(of: "_Speaker label: ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let originalSpeakerLabelLine = lines.dropFirst().first(where: { $0.hasPrefix("_Original speaker label: ") }) {
            originalSpeakerLabel = originalSpeakerLabelLine
                .replacingOccurrences(of: "_Original speaker label: ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            originalSpeakerLabel = assignedSpeakerLabel
        }

        if let correctionLine = lines.dropFirst().first(where: { $0.hasPrefix("_Manual correction from original transcript: ") }) {
            originalText = correctionLine
                .replacingOccurrences(of: "_Manual correction from original transcript: ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let key = segmentKey(timestamp: timestamp, speakerLabel: originalSpeakerLabel)
        return EditableTranscriptSegment(
            key: key,
            timestamp: timestamp,
            originalSpeakerLabel: originalSpeakerLabel,
            assignedSpeakerLabel: assignedSpeakerLabel,
            originalText: originalText,
            currentText: currentText
        )
    }

    private func parseAgentSegmentMetadata(from markdown: String) -> [String: AgentSegmentMetadata] {
        let lines = markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var metadata: [String: AgentSegmentMetadata] = [:]
        var currentID = ""
        var currentMarker = ""
        var currentSpeakerLabel = ""
        var currentSource = "unknown"

        func commitCurrent() {
            guard !currentMarker.isEmpty, !currentSpeakerLabel.isEmpty else { return }
            let key = segmentKey(timestamp: currentMarker, speakerLabel: currentSpeakerLabel)
            metadata[key] = AgentSegmentMetadata(
                id: currentID.isEmpty ? "seg-\(metadata.count + 1)" : currentID,
                source: currentSource
            )
        }

        for line in lines {
            if line.hasPrefix("- id: ") {
                commitCurrent()
                currentID = cleanedValue(from: line, prefix: "- id: ")
                currentMarker = ""
                currentSpeakerLabel = ""
                currentSource = "unknown"
            } else if line.hasPrefix("marker: ") {
                currentMarker = cleanedValue(from: line, prefix: "marker: ")
            } else if line.hasPrefix("speaker_label: ") {
                currentSpeakerLabel = cleanedValue(from: line, prefix: "speaker_label: ")
            } else if line.hasPrefix("original_speaker_label: ") {
                currentSpeakerLabel = cleanedValue(from: line, prefix: "original_speaker_label: ")
            } else if line.hasPrefix("source: ") {
                currentSource = cleanedValue(from: line, prefix: "source: ")
            }
        }

        commitCurrent()
        return metadata
    }

    private func displaySpeakerName(for speakerLabel: String, aliasMapping: [String: String]) -> String {
        let alias = aliasMapping[speakerLabel]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? speakerLabel : alias
    }

    private func rebuildHeader(from header: String, session: SessionRecord) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let start = session.startedAt
        let end = session.endedAt ?? start
        let speakerAliases = session.speakerLabels.map { label in
            "  \(label): \"\(escapeForYAML(session.aliasMapping[label] ?? ""))\""
        }.joined(separator: "\n")
        let preferredSources = headerValue(for: "preferred_transcript_sources", in: header) ?? ""
        let transcriptionEngine = headerValue(for: "transcription_engine", in: header) ?? ""
        let speakersDetected = Int(headerValue(for: "speakers_detected", in: header) ?? "") ?? 1
        let speakerSlotsAvailable = max(session.speakerLabels.count, session.speakerCount)

        return """
        ---
        schema_version: 2
        title: \(session.title)
        date: \(dateFormatter.string(from: start))
        start_time: "\(timeFormatter.string(from: start))"
        end_time: "\(timeFormatter.string(from: end))"
        duration_seconds: \(session.durationSeconds)
        language: \(session.language)
        capture_mode: \(session.captureMode.rawValue)
        audio_source: \(session.audioSourceType.rawValue)
        speakers_detected: \(speakersDetected)
        speaker_slots_available: \(speakerSlotsAvailable)
        speaker_aliases:
        \(speakerAliases.isEmpty ? "  {}" : speakerAliases)
        confidence_warnings: \(session.warningCount)
        manual_corrections: \(session.transcriptEdits.count)
        speaker_reassignments: \(session.speakerAssignments.count)
        shared_links_present: \(session.sharedLinks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        context_notes_present: \(session.contextNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        audio_file: "\(escapeForYAML(session.audioPath ?? ""))"
        system_audio_file: "\(escapeForYAML(session.systemAudioPath ?? ""))"
        preferred_transcript_sources: "\(escapeForYAML(preferredSources))"
        transcription_engine: "\(escapeForYAML(transcriptionEngine))"
        ---

        # Transcript
        """
    }

    private func buildSessionContextSection(for session: SessionRecord) -> String {
        let sharedLinks = session.sharedLinks.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextNotes = session.contextNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sharedLinks.isEmpty || !contextNotes.isEmpty else {
            return "# Session Context\n\n_No additional context was added._"
        }

        var sections = ["# Session Context"]

        if !sharedLinks.isEmpty {
            sections.append("## Shared Links / References\n\n\(sharedLinks)")
        }

        if !contextNotes.isEmpty {
            sections.append("## Additional Context / Notes\n\n\(contextNotes)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func headerValue(for key: String, in header: String) -> String? {
        let prefix = "\(key): "
        for rawLine in header.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(prefix) else { continue }
            return cleanedValue(from: line, prefix: prefix)
        }

        return nil
    }

    private func escapeForYAML(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func baseTranscriptText(for segment: EditableTranscriptSegment) -> String {
        segment.isEdited ? segment.originalText : segment.currentText
    }

    private func cleanedValue(from line: String, prefix: String) -> String {
        line
            .replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
