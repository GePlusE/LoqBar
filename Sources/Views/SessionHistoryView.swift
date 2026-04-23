import SwiftUI

struct SessionHistoryView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(appModel.sessions) { session in
                    NavigationLink {
                        SessionDetailView(sessionID: session.id)
                            .environmentObject(appModel)
                    } label: {
                        SessionRow(session: session)
                    }
                }
            }
            .navigationTitle("Recent Sessions")
        }
        .onAppear {
            appModel.bringAuxiliaryWindowToFront(titleContains: "Recent Sessions")
        }
        .onDisappear {
            appModel.restoreMenuBarPresentationIfPossible()
        }
    }
}

private struct SessionRow: View {
    let session: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.headline)
            Text("\(session.status.title) • \(session.captureMode.title) • \(session.durationSeconds)s")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
