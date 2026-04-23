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

                        LabeledContent("Status", value: session.status.title)
                        LabeledContent("Capture mode", value: session.captureMode.title)
                        LabeledContent("Audio source", value: session.audioSourceType.title)
                        LabeledContent("Microphone audio", value: session.audioPath ?? "Not available")
                        LabeledContent("System audio", value: session.systemAudioPath ?? "Not available")
                        LabeledContent("Transcript", value: session.transcriptPath ?? "Not exported yet")
                    }

                    Section("Speaker Aliases") {
                        ForEach(1...max(session.speakerCount, 3), id: \.self) { index in
                            let key = "Speaker\(index)"
                            TextField(key, text: Binding(
                                get: { session.aliasMapping[key] ?? "" },
                                set: { appModel.updateAlias(for: session, speakerLabel: key, alias: $0) }
                            ))
                        }
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "tray")
            }
        }
    }
}
