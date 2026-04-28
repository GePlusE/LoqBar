import SwiftUI

struct FirstRunSetupView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to LoqBar")
                    .font(.largeTitle.weight(.semibold))

                Text("This checklist shows what still needs attention before LoqBar is fully ready on this Mac. You can still finish setup now and come back later for optional steps like transcription.")
                    .foregroundStyle(.secondary)

                summaryCard

                Toggle("Launch automatically when I log in", isOn: $appModel.firstRunState.launchAtLogin)

                readinessChecklist

                HStack(spacing: 12) {
                    Button("Open Privacy Settings") {
                        appModel.openPermissionsSettings()
                    }

                    Button("Refresh Status") {
                        appModel.refreshPermissions()
                    }

                    Button("Install Managed Transcription") {
                        appModel.installManagedTranscriptionFiles()
                    }
                    .disabled(appModel.isInstallingManagedTranscription)

                    Spacer()

                    Button("Complete Setup") {
                        appModel.completeFirstRun()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("First Use Readiness")
                .font(.headline)
            Text(appModel.firstUseReadinessSummary)
                .foregroundStyle(.secondary)

            if appModel.isInstallingManagedTranscription || !appModel.managedTranscriptionInstallStatus.isEmpty {
                Text(appModel.managedTranscriptionInstallStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var readinessChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checklist")
                .font(.headline)

            ForEach(appModel.firstUseReadinessItems) { item in
                readinessRow(item)
            }
        }
    }

    private func readinessRow(_ item: FirstUseReadinessItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: item.state))
                .foregroundStyle(iconColor(for: item.state))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)

                    Text(item.state.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(iconColor(for: item.state).opacity(0.16))
                        .foregroundStyle(iconColor(for: item.state))
                        .clipShape(Capsule())
                }
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func iconName(for state: FirstUseReadinessItem.State) -> String {
        switch state {
        case .ready:
            return "checkmark.seal.fill"
        case .recommended:
            return "info.circle"
        case .required:
            return "exclamationmark.circle"
        }
    }

    private func iconColor(for state: FirstUseReadinessItem.State) -> Color {
        switch state {
        case .ready:
            return .green
        case .recommended:
            return .blue
        case .required:
            return .orange
        }
    }
}
