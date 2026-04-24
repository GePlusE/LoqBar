import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            modePicker
            if shouldShowPermissionBadges {
                permissionBadges
            }
            quickActions
        }
        .padding(18)
        .frame(width: 360)
        .alert(item: $appModel.alertContext) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                primaryButton: .default(Text("Open Settings")) {
                    appModel.openPermissionsSettings()
                },
                secondaryButton: .cancel(Text("Dismiss")) {
                    appModel.dismissAlert()
                }
            )
        }
    }

    private var header: some View {
        HStack {
            Text("LoqBar")
                .font(.title2.weight(.semibold))

            Spacer()
        }
    }

    private var modePicker: some View {
        Picker("Default Capture Mode", selection: $appModel.settings.defaultCaptureMode) {
            ForEach(CaptureMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .onChange(of: appModel.settings.defaultCaptureMode) { _, _ in
            appModel.persist()
        }
    }

    private var permissionBadges: some View {
        HStack(spacing: 8) {
            permissionChip("Mic", granted: appModel.permissionState.microphoneAuthorized)
            permissionChip("Screen", granted: appModel.permissionState.screenCaptureAuthorized)
        }
    }

    private func permissionChip(_ label: String, granted: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(granted ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
            .clipShape(Capsule())
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(appModel.activeSession == nil ? "Start" : "Stop") {
                if appModel.activeSession == nil {
                    appModel.startRecording()
                } else {
                    appModel.stopRecording()
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Refresh Permissions") {
                appModel.refreshPermissions()
            }
            .buttonStyle(.bordered)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Preferences") {
                appModel.prepareToPresentAuxiliaryWindow()
                openWindow(id: "settings")
                appModel.bringAuxiliaryWindowToFront(titleContains: "Settings")
            }

            Button("Sessions") {
                appModel.prepareToPresentAuxiliaryWindow()
                openWindow(id: "history")
                appModel.bringAuxiliaryWindowToFront(titleContains: "Recent Sessions")
            }

            Menu("More") {
                Button("Refresh Permissions") {
                    appModel.refreshPermissions()
                }

                Divider()

                Button("Transcripts") {
                    appModel.openTranscriptFolder()
                }

                Button("Recordings") {
                    appModel.openRecordingRootFolder()
                }

                Divider()

                Button("Latest Recording Folder") {
                    appModel.openLatestRecordingFolder()
                }
                .disabled(appModel.latestSession == nil)

                Button("Reveal Latest Mic File") {
                    appModel.revealLatestMicrophoneRecording()
                }
                .disabled(appModel.latestSession?.audioPath == nil)

                Button("Reveal Latest System File") {
                    appModel.revealLatestSystemAudioRecording()
                }
                .disabled(appModel.latestSession?.systemAudioPath == nil)

                Divider()

                Button("Mic Only Test") {
                    appModel.startDiagnosticRecording(.microphoneOnly)
                }
                .disabled(appModel.activeSession != nil)

                Button("System Audio Test") {
                    appModel.startDiagnosticRecording(.systemAudioOnly)
                }
                .disabled(appModel.activeSession != nil)
            }

            Divider()

            Button("Quit LoqBar") {
                appModel.quitApp()
            }
        }
        .buttonStyle(.plain)
    }

    private var shouldShowPermissionBadges: Bool {
        !appModel.permissionState.microphoneAuthorized || !appModel.permissionState.screenCaptureAuthorized
    }
}
