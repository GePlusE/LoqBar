import Foundation

struct EditableTranscriptSegment: Identifiable, Hashable {
    let key: String
    let timestamp: String
    let speakerLabel: String
    let originalText: String
    let currentText: String

    var id: String { key }
    var isEdited: Bool { currentText != originalText }
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
            return EditableTranscriptSegment(
                key: parsed.key,
                timestamp: parsed.timestamp,
                speakerLabel: parsed.speakerLabel,
                originalText: edit?.originalText ?? parsed.originalText,
                currentText: edit?.editedText ?? parsed.currentText
            )
        }
    }

    func applyEdits(to transcriptPath: String, edits: [String: TranscriptEdit]) throws {
        let fileURL = URL(fileURLWithPath: transcriptPath)
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let rebuilt = try rewriteTranscriptSection(in: markdown, edits: edits, aliasMapping: [:])
        try rebuilt.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func refreshTranscriptPresentation(for session: SessionRecord) throws {
        guard let transcriptPath = session.transcriptPath else { return }
        let fileURL = URL(fileURLWithPath: transcriptPath)
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let rebuilt = try rewriteTranscriptSection(
            in: markdown,
            edits: session.transcriptEdits,
            aliasMapping: session.aliasMapping
        )
        try rebuilt.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func segmentKey(timestamp: String, speakerLabel: String) -> String {
        "\(timestamp)|\(speakerLabel)"
    }

    private func rewriteTranscriptSection(
        in markdown: String,
        edits: [String: TranscriptEdit],
        aliasMapping: [String: String]
    ) throws -> String {
        let transcriptMarker = "# Transcript"
        let agentMarker = "# Agent Segments"
        let analysisMarker = "# Analysis Notes"

        guard let transcriptRange = markdown.range(of: transcriptMarker) else {
            throw AppError.transcriptExportFailed("LoqBar could not find the transcript section while saving manual transcript edits.")
        }

        let afterTranscript = markdown[transcriptRange.upperBound...]
        let agentRangeInTail = afterTranscript.range(of: agentMarker)

        let header = String(markdown[..<transcriptRange.upperBound])
        let transcriptBodyRaw: String
        let agentBodyRaw: String
        let analysisSuffix: String

        if let agentRangeInTail {
            transcriptBodyRaw = String(afterTranscript[..<agentRangeInTail.lowerBound])
            let afterAgent = afterTranscript[agentRangeInTail.upperBound...]

            if let analysisRangeAfterAgent = afterAgent.range(of: analysisMarker) {
                agentBodyRaw = String(afterAgent[..<analysisRangeAfterAgent.lowerBound])
                analysisSuffix = String(afterAgent[analysisRangeAfterAgent.lowerBound...])
            } else {
                agentBodyRaw = String(afterAgent)
                analysisSuffix = ""
            }
        } else {
            transcriptBodyRaw = String(afterTranscript)
            agentBodyRaw = ""
            analysisSuffix = ""
        }

        let segments = parseTranscriptSection(from: transcriptMarker + transcriptBodyRaw)
        let agentMetadata = parseAgentSegmentMetadata(from: agentBodyRaw)
        let rebuiltBody = segments.map { segment in
            let activeEdit = edits[segment.key]
            let currentText = activeEdit?.editedText ?? baseTranscriptText(for: segment)
            let originalText = activeEdit?.originalText ?? segment.originalText
            let displaySpeaker = displaySpeakerName(for: segment.speakerLabel, aliasMapping: aliasMapping)
            var lines = ["[\(segment.timestamp)] \(displaySpeaker): \(currentText)"]

            if displaySpeaker != segment.speakerLabel {
                lines.append("_Speaker label: \(segment.speakerLabel)_")
            }

            if currentText != originalText {
                lines.append("_Manual correction from original transcript: \(originalText)_")
            }

            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let rebuiltAgentBody = segments.enumerated().map { index, segment in
            let activeEdit = edits[segment.key]
            let currentText = activeEdit?.editedText ?? baseTranscriptText(for: segment)
            let originalText = activeEdit?.originalText ?? segment.originalText
            let speakerDisplay = displaySpeakerName(for: segment.speakerLabel, aliasMapping: aliasMapping)
            let metadata = agentMetadata[segment.key]
            let segmentID = metadata?.id ?? String(format: "seg-%04d", index + 1)
            let source = metadata?.source ?? "unknown"

            return """
            - id: "\(segmentID)"
              marker: "\(escapeForYAML(segment.timestamp))"
              speaker_label: "\(escapeForYAML(segment.speakerLabel))"
              speaker_name: "\(escapeForYAML(speakerDisplay))"
              source: "\(escapeForYAML(source))"
              edited: \(currentText != originalText)
              text: "\(escapeForYAML(currentText))"
              original_text: "\(escapeForYAML(originalText))"
            """
        }.joined(separator: "\n")

        let normalizedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnalysis = analysisSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

        let updatedHeader = rewriteSpeakerAliases(in: normalizedHeader, aliasMapping: aliasMapping)

        if normalizedAnalysis.isEmpty {
            return "\(updatedHeader)\n\n\(rebuiltBody)\n\n# Agent Segments\n\n\(rebuiltAgentBody)\n"
        }

        return "\(updatedHeader)\n\n\(rebuiltBody)\n\n# Agent Segments\n\n\(rebuiltAgentBody)\n\n\(normalizedAnalysis)\n"
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
        var speakerLabel = firstLine[speakerStart..<speakerSeparatorRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = firstLine[speakerSeparatorRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var originalText = currentText

        if let speakerLabelLine = lines.dropFirst().first(where: { $0.hasPrefix("_Speaker label: ") }) {
            speakerLabel = speakerLabelLine
                .replacingOccurrences(of: "_Speaker label: ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let correctionLine = lines.dropFirst().first(where: { $0.hasPrefix("_Manual correction from original transcript: ") }) {
            originalText = correctionLine
                .replacingOccurrences(of: "_Manual correction from original transcript: ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let key = segmentKey(timestamp: timestamp, speakerLabel: speakerLabel)
        return EditableTranscriptSegment(
            key: key,
            timestamp: timestamp,
            speakerLabel: speakerLabel,
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

    private func rewriteSpeakerAliases(in header: String, aliasMapping: [String: String]) -> String {
        let lines = header.components(separatedBy: .newlines)
        var updatedLines: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            updatedLines.append(line)

            if line == "speaker_aliases:" {
                index += 1

                while index < lines.count {
                    let aliasLine = lines[index]
                    guard aliasLine.hasPrefix("  Speaker") else {
                        break
                    }

                    let key = aliasLine
                        .components(separatedBy: ":")
                        .first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let aliasValue = aliasMapping[key] ?? ""
                    updatedLines.append("  \(key): \"\(escapeForYAML(aliasValue))\"")
                    index += 1
                }

                continue
            }

            index += 1
        }

        return updatedLines.joined(separator: "\n")
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
