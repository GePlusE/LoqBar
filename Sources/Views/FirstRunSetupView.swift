import SwiftUI

struct FirstRunSetupView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to LoqBar")
                .font(.largeTitle.weight(.semibold))

            Text("This setup keeps things simple: choose whether LoqBar launches at login, then grant the permissions needed for local meeting capture.")
                .foregroundStyle(.secondary)

            Toggle("Launch automatically when I log in", isOn: $appModel.firstRunState.launchAtLogin)

            permissionChecklist

            HStack(spacing: 12) {
                Button("Open Privacy Settings") {
                    appModel.openPermissionsSettings()
                }

                Button("Refresh Status") {
                    appModel.refreshPermissions()
                }

                Spacer()

                Button("Complete Setup") {
                    appModel.completeFirstRun()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private var permissionChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.headline)

            permissionRow(
                title: "Microphone",
                description: "Needed for in-person meetings and your own voice during calls.",
                granted: appModel.permissionState.microphoneAuthorized
            )

            permissionRow(
                title: "Screen Recording",
                description: "Needed to investigate capturing Teams or system audio while you use headphones.",
                granted: appModel.permissionState.screenCaptureAuthorized
            )
        }
    }

    private func permissionRow(title: String, description: String, granted: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
