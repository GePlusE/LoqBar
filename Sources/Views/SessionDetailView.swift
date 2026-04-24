import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let sessionID: UUID

    @State private var editedTitle = ""

    var body: some View {
        Group {
            if let session = appModel.sessions.first(where: { $0.id == sessionID }) {
                Form {
                    Section("Session") {
                        TextField("Title", text: Binding(
                            get: {
                                editedTitle.isEmpty ? session.title : editedTitle
                            },
                            set: { editedTitle = $0 }
                        ))

                        Button("Save Title") {
                            appModel.renameSession(session, title: editedTitle)
                        }

                        Button("Retry Transcription") {
                            appModel.retryTranscription(for: session.id)
                        }
                        .disabled(session.isActive || !session.hasTranscribableAudio)

                        HStack {
                            Text("Status")
                            Spacer()
                            Text(session.displayStatusTitle)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(statusColor(for: session).opacity(0.16))
                                .foregroundStyle(statusColor(for: session))
                                .clipShape(Capsule())
                        }

                        LabeledContent("Transcription", value: session.transcriptionStatusSummary)
                        LabeledContent("Capture mode", value: session.captureMode.title)
                        LabeledContent("Audio source", value: session.audioSourceType.title)
                        LabeledContent("Microphone audio", value: session.audioPath ?? "Not available")
                        LabeledContent("System audio", value: session.systemAudioPath ?? "Not available")
                        LabeledContent("Transcript", value: session.transcriptPath ?? "Not exported yet")
                    }

                    Section("Speaker Aliases") {
                        if session.speakerLabels.isEmpty {
                            Text("Speaker aliases will appear after LoqBar detects speakers in the transcript.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(session.speakerLabels, id: \.self) { key in
                            TextField(key, text: Binding(
                                get: { session.aliasMapping[key] ?? "" },
                                set: { appModel.updateAlias(for: session, speakerLabel: key, alias: $0) }
                            ))
                        }
                    }

                    if !transcriptPreview(for: session).isEmpty {
                        Section("Transcript Preview") {
                            ForEach(transcriptPreview(for: session)) { segment in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(displaySpeakerName(for: segment.speakerLabel, session: session))
                                            .font(.headline)
                                        Spacer()
                                        Text(segment.timestamp)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if displaySpeakerName(for: segment.speakerLabel, session: session) != segment.speakerLabel {
                                        Text(segment.speakerLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(segment.text)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "tray")
            }
        }
    }

    private func displaySpeakerName(for speakerLabel: String, session: SessionRecord) -> String {
        let alias = session.aliasMapping[speakerLabel]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? speakerLabel : alias
    }

    private func transcriptPreview(for session: SessionRecord) -> [TranscriptPreviewSegment] {
        guard let transcriptPath = session.transcriptPath,
              let markdown = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return []
        }

        let transcriptSection = markdown
            .components(separatedBy: "# Transcript")
            .dropFirst()
            .joined(separator: "# Transcript")
            .components(separatedBy: "# Analysis Notes")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !transcriptSection.isEmpty else { return [] }

        return transcriptSection
            .components(separatedBy: "\n\n")
            .compactMap(TranscriptPreviewSegment.init(markdownBlock:))
    }

    private func statusColor(for session: SessionRecord) -> Color {
        if session.isTranscriptionPending {
            return .orange
        }

        switch session.status {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct TranscriptPreviewSegment: Identifiable {
    let id = UUID()
    let timestamp: String
    let speakerLabel: String
    let text: String

    init?(markdownBlock: String) {
        let trimmed = markdownBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closingBracketIndex = trimmed.firstIndex(of: "]"),
              let speakerSeparatorRange = trimmed.range(of: ": ") else {
            return nil
        }

        let timestampPart = String(trimmed[..<closingBracketIndex]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let speakerStart = trimmed.index(after: closingBracketIndex)
        let speakerPart = trimmed[speakerStart..<speakerSeparatorRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textPart = trimmed[speakerSeparatorRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !speakerPart.isEmpty, !textPart.isEmpty else { return nil }

        timestamp = timestampPart
        speakerLabel = speakerPart
        text = textPart
    }
}
