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
        let analysisMarker = "# Analysis Notes"

        guard let transcriptRange = markdown.range(of: transcriptMarker) else {
            throw AppError.transcriptExportFailed("LoqBar could not find the transcript section while saving manual transcript edits.")
        }

        let afterTranscript = markdown[transcriptRange.upperBound...]
        let analysisRangeInTail = afterTranscript.range(of: analysisMarker)

        let header = String(markdown[..<transcriptRange.upperBound])
        let analysisSuffix: String
        let transcriptBodyRaw: String

        if let analysisRangeInTail {
            transcriptBodyRaw = String(afterTranscript[..<analysisRangeInTail.lowerBound])
            analysisSuffix = String(afterTranscript[analysisRangeInTail.lowerBound...])
        } else {
            transcriptBodyRaw = String(afterTranscript)
            analysisSuffix = ""
        }

        let segments = parseTranscriptSection(from: transcriptMarker + transcriptBodyRaw)
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

        let normalizedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnalysis = analysisSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

        let updatedHeader = rewriteSpeakerAliases(in: normalizedHeader, aliasMapping: aliasMapping)

        if normalizedAnalysis.isEmpty {
            return "\(updatedHeader)\n\n\(rebuiltBody)\n"
        }

        return "\(updatedHeader)\n\n\(rebuiltBody)\n\n\(normalizedAnalysis)\n"
    }

    private func parseTranscriptSection(from markdown: String) -> [EditableTranscriptSegment] {
        let transcriptSection = markdown
            .components(separatedBy: "# Transcript")
            .dropFirst()
            .joined(separator: "# Transcript")
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
}
