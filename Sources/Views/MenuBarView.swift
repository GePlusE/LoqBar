import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            modePicker
            sessionStatus
            controls
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LoqBar")
                    .font(.title2.weight(.semibold))
                Text("Capture meetings locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(statusTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture Mode")
                .font(.headline)

            Picker("Capture Mode", selection: $appModel.settings.defaultCaptureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appModel.settings.defaultCaptureMode) { _, _ in
                appModel.persist()
            }
        }
    }

    private var sessionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Session", systemImage: appModel.menuBarIconName)
                .font(.headline)

            Text(statusSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            permissionBadges
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
            Button(appModel.activeSession == nil ? "Start Recording" : "Stop Recording") {
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

            Button("Transcripts") {
                appModel.openTranscriptFolder()
            }

            Button("Recordings") {
                appModel.openRecordingRootFolder()
            }

            Menu("More") {
                Button("Refresh Permissions") {
                    appModel.refreshPermissions()
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

            if appModel.firstRunState.needsOnboarding {
                Divider()

                NavigationLink {
                    FirstRunSetupView()
                        .environmentObject(appModel)
                } label: {
                    Text("Finish Setup")
                }
            }

            Divider()

            Button("Quit LoqBar") {
                appModel.quitApp()
            }
        }
        .buttonStyle(.plain)
    }

    private var statusTitle: String {
        appModel.activeSession?.status.title ?? "Idle"
    }

    private var statusSubtitle: String {
        if let activeSession = appModel.activeSession {
            return activeSession.notes.isEmpty ? "Session in progress" : activeSession.notes
        }

        return appModel.processingMessage
    }
}
