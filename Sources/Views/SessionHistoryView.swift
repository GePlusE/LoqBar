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

            HStack(spacing: 8) {
                statusBadge
                Text("\(session.captureMode.title) • \(session.durationSeconds)s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(session.displayStatusTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.16))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
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
