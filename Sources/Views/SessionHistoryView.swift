import SwiftUI

struct SessionHistoryView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard

                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(appModel.sessions) { session in
                            NavigationLink {
                                SessionDetailView(sessionID: session.id)
                                    .environmentObject(appModel)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Recent Sessions")
        }
        .onAppear {
            appModel.bringAuxiliaryWindowToFront(titleContains: "Recent Sessions")
        }
        .onDisappear {
            appModel.restoreMenuBarPresentationIfPossible()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Sessions")
                .font(.largeTitle.weight(.semibold))
            Text("Review completed captures, spot pending transcription work, and jump into speaker labeling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct SessionRow: View {
    let session: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                statusBadge
                Text("\(session.captureMode.title) • \(session.durationSeconds)s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusBadge: some View {
        Text(session.displayStatusTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
