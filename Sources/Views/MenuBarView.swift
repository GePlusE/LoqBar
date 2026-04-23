import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modePicker
            sessionStatus
            controls
            diagnostics
            quickActions
        }
        .padding(16)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("LoqBar")
                .font(.title2.weight(.semibold))
            Text("Capture meetings locally. Export structured transcripts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            Label(statusTitle, systemImage: appModel.menuBarIconName)
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

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.headline)

            Button("Start Microphone Only Test") {
                appModel.startDiagnosticRecording(.microphoneOnly)
            }
            .disabled(appModel.activeSession != nil)

            Button("Start System Audio Only Test") {
                appModel.startDiagnosticRecording(.systemAudioOnly)
            }
            .disabled(appModel.activeSession != nil)
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Settings") {
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                openWindow(id: "settings")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NSApp.windows.forEach { window in
                        if window.title.localizedCaseInsensitiveContains("Settings") {
                            window.orderFrontRegardless()
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            Button("Open Recent Sessions") {
                openWindow(id: "history")
            }

            Button("Open Transcript Folder") {
                appModel.openTranscriptFolder()
            }

            Button("Open Recording Root Folder") {
                appModel.openRecordingRootFolder()
            }

            Button("Open Latest Recording Folder") {
                appModel.openLatestRecordingFolder()
            }
            .disabled(appModel.latestSession == nil)

            Button("Reveal Latest Microphone File") {
                appModel.revealLatestMicrophoneRecording()
            }
            .disabled(appModel.latestSession?.audioPath == nil)

            Button("Reveal Latest System Audio File") {
                appModel.revealLatestSystemAudioRecording()
            }
            .disabled(appModel.latestSession?.systemAudioPath == nil)

            if appModel.firstRunState.needsOnboarding {
                Divider()

                NavigationLink {
                    FirstRunSetupView()
                        .environmentObject(appModel)
                } label: {
                    Text("Finish First-Run Setup")
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
