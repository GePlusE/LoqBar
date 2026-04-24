import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let sessionID: UUID

    @State private var editedTitle = ""
    @State private var editingSegmentKey: String?
    @State private var segmentDraftText = ""

    var body: some View {
        Group {
            if let session = appModel.sessions.first(where: { $0.id == sessionID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sessionCard(for: session)
                        speakerAliasesCard(for: session)

                        let preview = transcriptPreview(for: session)
                        if !preview.isEmpty {
                            transcriptPreviewCard(preview, session: session)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 980, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "tray")
            }
        }
    }

    private func sessionCard(for session: SessionRecord) -> some View {
        detailCard("Session") {
            VStack(alignment: .leading, spacing: 16) {
                detailField("Title") {
                    TextField("Title", text: Binding(
                        get: { editedTitle.isEmpty ? session.title : editedTitle },
                        set: { editedTitle = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    Button("Save Title") {
                        appModel.renameSession(session, title: editedTitle)
                    }

                    Button("Retry Transcription") {
                        appModel.retryTranscription(for: session.id)
                    }
                    .disabled(session.isActive || !session.hasTranscribableAudio)
                }

                detailRow("Status") {
                    Text(session.displayStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor(for: session).opacity(0.16))
                        .foregroundStyle(statusColor(for: session))
                        .clipShape(Capsule())
                }

                detailRow("Transcription", value: session.transcriptionStatusSummary)
                detailRow("Capture mode", value: session.captureMode.title)
                detailRow("Audio source", value: session.audioSourceType.title)
                detailRow("Microphone audio", value: session.audioPath ?? "Not available")
                detailRow("System audio", value: session.systemAudioPath ?? "Not available")
                detailRow("Transcript", value: session.transcriptPath ?? "Not exported yet")
            }
        }
    }

    private func speakerAliasesCard(for session: SessionRecord) -> some View {
        detailCard("Speaker Aliases") {
            VStack(alignment: .leading, spacing: 14) {
                if session.speakerLabels.isEmpty {
                    Text("Speaker aliases will appear after LoqBar detects speakers in the transcript.")
                        .foregroundStyle(.secondary)
                }

                ForEach(session.speakerLabels, id: \.self) { key in
                    detailField(key) {
                        TextField(key, text: Binding(
                            get: { session.aliasMapping[key] ?? "" },
                            set: { appModel.updateAlias(for: session, speakerLabel: key, alias: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private func transcriptPreviewCard(_ preview: [TranscriptPreviewSegment], session: SessionRecord) -> some View {
        detailCard("Transcript Preview") {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(preview) { segment in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
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

                        if editingSegmentKey == segment.key {
                            TextEditor(text: $segmentDraftText)
                                .frame(minHeight: 72)
                                .padding(8)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            HStack(spacing: 12) {
                                Button("Save Correction") {
                                    appModel.updateTranscriptSegment(
                                        for: session.id,
                                        segmentKey: segment.key,
                                        originalText: segment.originalText,
                                        editedText: segmentDraftText
                                    )
                                    editingSegmentKey = nil
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Cancel") {
                                    editingSegmentKey = nil
                                    segmentDraftText = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Button {
                                editingSegmentKey = segment.key
                                segmentDraftText = segment.currentText
                            } label: {
                                Text(segment.currentText)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)

                            if segment.isEdited {
                                Text(segment.originalText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if segment.id != preview.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func detailCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3.weight(.semibold))

            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func detailField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
            content()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        detailRow(label) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func detailRow<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.headline)
                .frame(width: 150, alignment: .leading)

            value()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func displaySpeakerName(for speakerLabel: String, session: SessionRecord) -> String {
        let alias = session.aliasMapping[speakerLabel]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? speakerLabel : alias
    }

    private func transcriptPreview(for session: SessionRecord) -> [TranscriptPreviewSegment] {
        appModel.editableTranscriptSegments(for: session)
            .map(TranscriptPreviewSegment.init(editableSegment:))
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
    let id: String
    let key: String
    let timestamp: String
    let speakerLabel: String
    let originalText: String
    let currentText: String
    let isEdited: Bool

    init(editableSegment: EditableTranscriptSegment) {
        id = editableSegment.id
        key = editableSegment.key
        timestamp = editableSegment.timestamp
        speakerLabel = editableSegment.speakerLabel
        originalText = editableSegment.originalText
        currentText = editableSegment.currentText
        isEdited = editableSegment.isEdited
    }
}
