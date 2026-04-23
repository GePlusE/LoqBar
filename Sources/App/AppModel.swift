import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = AppSettings.defaultValue
    @Published var sessions: [SessionRecord] = []
    @Published var permissionState = PermissionState.unknown
    @Published var firstRunState = FirstRunState()
    @Published var alertContext: AlertContext?
    @Published var processingMessage = "Ready"

    private let permissionsService: PermissionsService
    private let loginItemService: LoginItemService
    private let sessionStore: SessionStore
    private let transcriptExporter: TranscriptExporter
    private let captureService: CaptureService

    init(
        permissionsService: PermissionsService = PermissionsService(),
        loginItemService: LoginItemService = LoginItemService(),
        sessionStore: SessionStore = SessionStore(),
        transcriptExporter: TranscriptExporter = TranscriptExporter(),
        captureService: CaptureService = CaptureService()
    ) {
        self.permissionsService = permissionsService
        self.loginItemService = loginItemService
        self.sessionStore = sessionStore
        self.transcriptExporter = transcriptExporter
        self.captureService = captureService

        loadInitialState()
    }

    var activeSession: SessionRecord? {
        sessions.first(where: \.isActive)
    }

    var menuBarIconName: String {
        switch activeSession?.status {
        case .recording:
            return "waveform.circle.fill"
        case .processing:
            return "gearshape.2.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .none, .idle:
            return "mic.circle"
        }
    }

    func loadInitialState() {
        settings = sessionStore.loadSettings()
        sessions = sessionStore.loadSessions()
        permissionState = permissionsService.currentState()
        firstRunState = FirstRunState(
            needsOnboarding: !settings.firstRunCompleted,
            launchAtLogin: settings.launchAtLoginEnabled
        )
    }

    func refreshPermissions() {
        permissionState = permissionsService.currentState()
    }

    func completeFirstRun() {
        settings.firstRunCompleted = true
        settings.launchAtLoginEnabled = firstRunState.launchAtLogin

        do {
            try loginItemService.setEnabled(firstRunState.launchAtLogin)
            sessionStore.save(settings: settings)
            firstRunState.needsOnboarding = false
            refreshPermissions()
        } catch {
            present(error: .loginItemUpdateFailed(error.localizedDescription))
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLoginEnabled = enabled

        do {
            try loginItemService.setEnabled(enabled)
            sessionStore.save(settings: settings)
        } catch {
            present(error: .loginItemUpdateFailed(error.localizedDescription))
        }
    }

    func startRecording() {
        guard activeSession == nil else { return }

        let capturePlan = captureService.planCapture(
            requestedMode: settings.defaultCaptureMode,
            permissionState: permissionState
        )

        guard capturePlan.isAvailable else {
            present(error: capturePlan.unavailableReason ?? .callAudioCaptureUnavailable)
            return
        }

        var session = SessionRecord.newDraft(
            captureMode: capturePlan.mode,
            audioSourceType: capturePlan.audioSource
        )
        session.status = .recording
        session.notes = capturePlan.userFacingSummary
        sessions.insert(session, at: 0)
        persist()
    }

    func stopRecording() {
        guard let sessionIndex = sessions.firstIndex(where: \.isActive) else { return }

        sessions[sessionIndex].status = .processing
        sessions[sessionIndex].endedAt = Date()
        sessions[sessionIndex].durationSeconds = max(
            Int(sessions[sessionIndex].endedAt?.timeIntervalSince(sessions[sessionIndex].startedAt) ?? 0),
            1
        )
        processingMessage = "Generating sample transcript export"

        do {
            let transcript = try transcriptExporter.exportTranscript(for: sessions[sessionIndex], settings: settings)
            sessions[sessionIndex].status = .completed
            sessions[sessionIndex].transcriptPath = transcript.path
            sessions[sessionIndex].warningCount = transcript.warningCount
            sessions[sessionIndex].speakerCount = transcript.speakersDetected
            sessions[sessionIndex].notes = transcript.summary
            processingMessage = "Transcript exported"
            persist()
        } catch {
            sessions[sessionIndex].status = .failed
            processingMessage = "Export failed"
            present(error: .transcriptExportFailed(error.localizedDescription))
            persist()
        }
    }

    func renameSession(_ session: SessionRecord, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? sessions[index].title
        persist()
    }

    func updateAlias(for session: SessionRecord, speakerLabel: String, alias: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].aliasMapping[speakerLabel] = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func dismissAlert() {
        alertContext = nil
    }

    func openPermissionsSettings() {
        permissionsService.openRelevantSettings()
    }

    func openTranscriptFolder() {
        sessionStore.openTranscriptFolder(settings: settings)
    }

    func persist() {
        sessionStore.save(settings: settings)
        sessionStore.save(sessions: sessions)
    }

    private func present(error: AppError) {
        alertContext = AlertContext(
            title: error.title,
            message: error.recoverySuggestion
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
