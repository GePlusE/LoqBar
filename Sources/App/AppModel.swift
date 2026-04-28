import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = AppSettings.defaultValue
    @Published var sessions: [SessionRecord] = []
    @Published var permissionState = PermissionState.unknown
    @Published var firstRunState = FirstRunState()
    @Published var alertContext: AlertContext?
    @Published var processingMessage = "Ready"
    @Published var updateStatus = UpdateStatusSummary.idle
    @Published var managedTranscriptionInstallStatus = "Managed transcription is not installing right now."
    @Published var isInstallingManagedTranscription = false
    @Published var isLocalMicCapturePaused = false

    private let permissionsService: PermissionsService
    private let loginItemService: LoginItemService
    private let sessionStore: SessionStore
    private let transcriptExporter: TranscriptExporter
    private let transcriptionService: TranscriptionService
    private let captureService: CaptureService
    private let recordingCoordinator: AudioCaptureCoordinator
    private let audioStorageOptimizer: AudioStorageOptimizer
    private let transcriptRevisionService: TranscriptRevisionService
    private let retentionCleanupService: RetentionCleanupService
    private let updateCheckService: UpdateCheckService
    private let managedTranscriptionInstallService: ManagedTranscriptionInstallService
    private var cancellables = Set<AnyCancellable>()

    init(
        permissionsService: PermissionsService = PermissionsService(),
        loginItemService: LoginItemService = LoginItemService(),
        sessionStore: SessionStore = SessionStore(),
        transcriptExporter: TranscriptExporter = TranscriptExporter(),
        transcriptionService: TranscriptionService = TranscriptionService(),
        captureService: CaptureService = CaptureService(),
        recordingCoordinator: AudioCaptureCoordinator = AudioCaptureCoordinator(),
        audioStorageOptimizer: AudioStorageOptimizer = AudioStorageOptimizer(),
        transcriptRevisionService: TranscriptRevisionService = TranscriptRevisionService(),
        retentionCleanupService: RetentionCleanupService = RetentionCleanupService(),
        updateCheckService: UpdateCheckService = UpdateCheckService(),
        managedTranscriptionInstallService: ManagedTranscriptionInstallService = ManagedTranscriptionInstallService()
    ) {
        self.permissionsService = permissionsService
        self.loginItemService = loginItemService
        self.sessionStore = sessionStore
        self.transcriptExporter = transcriptExporter
        self.transcriptionService = transcriptionService
        self.captureService = captureService
        self.recordingCoordinator = recordingCoordinator
        self.audioStorageOptimizer = audioStorageOptimizer
        self.transcriptRevisionService = transcriptRevisionService
        self.retentionCleanupService = retentionCleanupService
        self.updateCheckService = updateCheckService
        self.managedTranscriptionInstallService = managedTranscriptionInstallService
        self.recordingCoordinator.onCaptureInterrupted = { [weak self] reason in
            Task { @MainActor in
                self?.handleCaptureInterruption(reason)
            }
        }

        loadInitialState()
        observeWorkspaceLifecycle()
    }

    var activeSession: SessionRecord? {
        sessions.first(where: \.isRecording)
    }

    var hasProcessingSessions: Bool {
        sessions.contains(where: \.isProcessing)
    }

    var latestSession: SessionRecord? {
        sessions.sorted(by: { $0.startedAt > $1.startedAt }).first
    }

    var menuBarIconName: String {
        isRecordingInMenuBar ? "apple.books.pages.fill" : "apple.books.pages"
    }

    var isRecordingInMenuBar: Bool {
        activeSession != nil || recordingCoordinator.hasActiveCapture
    }

    var canToggleLocalMicCapture: Bool {
        recordingCoordinator.hasMicrophoneCapture && activeSession != nil
    }

    var transcriptionSetupStatus: TranscriptionSetupStatus {
        TranscriptionSetupStatus.from(settings: settings)
    }

    var currentAppVersionDisplay: String {
        AppVersion.current().displayString
    }

    var updateFeedConfiguration: AppReleaseFeedConfiguration {
        AppReleaseFeedConfiguration.fromMainBundle()
    }

    var updateSourceSummary: String {
        if let feedURL = updateFeedConfiguration.feedURL {
            return feedURL.absoluteString
        }

        return "No release feed is configured in this build yet."
    }

    func loadInitialState() {
        settings = sessionStore.loadSettings()
        sessions = sessionStore.loadSessions()
        permissionState = permissionsService.currentState()
        firstRunState = FirstRunState(
            needsOnboarding: !settings.firstRunCompleted,
            launchAtLogin: settings.launchAtLoginEnabled
        )
        managedTranscriptionInstallStatus = transcriptionSetupStatus.message
        runRetentionCleanupIfNeeded()
    }

    func refreshPermissions() {
        permissionState = permissionsService.currentState()
    }

    func resetScreenCapturePermission() {
        do {
            try permissionsService.resetScreenCapturePermission()
            permissionState = permissionsService.currentState()
            alertContext = AlertContext(
                title: "Screen Permission Reset",
                message: """
                LoqBar reset macOS screen capture permission state.

                If macOS prompts again, allow Screen & System Audio Recording for LoqBar. If Remote mode still looks unavailable, quit and reopen LoqBar once.
                """
            )
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .permissionRepairFailed("LoqBar could not reset screen capture permission state: \(error.localizedDescription)"))
        }
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
        guard !recordingCoordinator.hasActiveCapture else { return }

        Task {
            let refreshedPermissions = await permissionsService.ensurePermissions(for: settings.defaultCaptureMode)

            await MainActor.run {
                permissionState = refreshedPermissions
            }

            let capturePlan = captureService.planCapture(
                requestedMode: settings.defaultCaptureMode,
                permissionState: refreshedPermissions
            )

            guard capturePlan.isAvailable else {
                await MainActor.run {
                    present(error: capturePlan.unavailableReason ?? .callAudioCaptureUnavailable)
                }
                return
            }

            var session = SessionRecord.newDraft(
                captureMode: capturePlan.mode,
                audioSourceType: capturePlan.audioSource
            )
            session.status = .recording
            session.notes = "Starting capture..."

            await MainActor.run {
                sessions.insert(session, at: 0)
                persist()
            }

            do {
                let activeCapture = try await recordingCoordinator.start(
                    sessionID: session.id,
                    mode: capturePlan.mode,
                    recordingRootFolderPath: settings.recordingOutputFolder
                )
                await MainActor.run {
                    apply(activeCapture, to: session.id, fallbackNote: capturePlan.userFacingSummary)
                    isLocalMicCapturePaused = false
                }
            } catch {
                await MainActor.run {
                    isLocalMicCapturePaused = false
                    markSessionFailed(session.id, error: .recordingStartupFailed(error.localizedDescription))
                }
            }
        }
    }

    func startDiagnosticRecording(_ diagnosticKind: DiagnosticCaptureKind) {
        guard activeSession == nil else { return }
        guard !recordingCoordinator.hasActiveCapture else { return }

        Task {
            let refreshedPermissions = await permissionsService.ensurePermissions(for: diagnosticKind)

            await MainActor.run {
                permissionState = refreshedPermissions
            }

            let capturePlan = captureService.planDiagnosticCapture(
                kind: diagnosticKind,
                permissionState: refreshedPermissions
            )

            guard capturePlan.isAvailable else {
                await MainActor.run {
                    present(error: capturePlan.unavailableReason ?? .callAudioCaptureUnavailable)
                }
                return
            }

            var session = SessionRecord.newDraft(
                captureMode: capturePlan.mode,
                audioSourceType: capturePlan.audioSource
            )
            session.status = .recording
            session.title = diagnosticKind.title
            session.notes = "Starting diagnostic capture..."

            await MainActor.run {
                sessions.insert(session, at: 0)
                persist()
            }

            do {
                let activeCapture = try await recordingCoordinator.start(
                    sessionID: session.id,
                    mode: capturePlan.mode,
                    recordingRootFolderPath: settings.recordingOutputFolder,
                    diagnosticKind: diagnosticKind
                )
                await MainActor.run {
                    apply(activeCapture, to: session.id, fallbackNote: capturePlan.userFacingSummary)
                    isLocalMicCapturePaused = false
                }
            } catch {
                await MainActor.run {
                    isLocalMicCapturePaused = false
                    markSessionFailed(session.id, error: .recordingStartupFailed(error.localizedDescription))
                }
            }
        }
    }

    func stopRecording() {
        stopRecording(interruptionNote: nil)
    }

    func stopRecording(interruptionNote: String?) {
        guard let session = activeSession else { return }

        if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[sessionIndex].status = .processing
            sessions[sessionIndex].notes = interruptionNote ?? "Stopping capture..."
            persist()
        }

        Task {
            do {
                let activeCapture = try await recordingCoordinator.stop()
                guard let snapshot = prepareStoppedSessionForBackgroundProcessing(
                    sessionID: session.id,
                    capture: activeCapture,
                    notePrefix: interruptionNote
                ) else { return }

                startBackgroundProcessing(for: snapshot)
            } catch {
                markSessionFailed(session.id, error: .recordingStopFailed(error.localizedDescription))
            }
        }
    }

    func toggleRecordingFromStatusItem() {
        if activeSession == nil {
            startRecording()
        } else {
            stopRecording()
        }
    }

    func toggleLocalMicCapture() {
        let nextPausedState = !isLocalMicCapturePaused

        do {
            try recordingCoordinator.setMicrophonePaused(nextPausedState)
            isLocalMicCapturePaused = nextPausedState
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .recordingStopFailed("LoqBar could not update local microphone capture: \(error.localizedDescription)"))
        }
    }

    func renameSession(_ session: SessionRecord, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? sessions[index].title
        do {
            try transcriptRevisionService.refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after renaming the session: \(error.localizedDescription)"))
        }
    }

    func deleteSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions[index]

        guard !session.isRecording else {
            present(error: .sessionDeletionFailed("Stop the active recording before deleting this session."))
            return
        }

        guard !session.isProcessing else {
            present(error: .sessionDeletionFailed("Wait for the current transcription/export work to finish before deleting this session."))
            return
        }

        do {
            try sessionStore.deleteArtifacts(for: session)
            sessions.remove(at: index)
            isLocalMicCapturePaused = false
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .sessionDeletionFailed("LoqBar could not delete this session: \(error.localizedDescription)"))
        }
    }

    func updateSessionTranscriptionLanguage(_ sessionID: UUID, language: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].transcriptionLanguageOverride = language == TranscriptionLanguageOption.auto.rawValue ? nil : language
        if language != TranscriptionLanguageOption.auto.rawValue {
            sessions[index].language = language
        }

        do {
            try transcriptRevisionService.refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after updating the transcription language: \(error.localizedDescription)"))
        }
    }

    func retryTranscription(for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard !sessions[index].isRecording else { return }
        guard !sessions[index].isProcessing else { return }
        guard sessions[index].audioPath != nil || sessions[index].systemAudioPath != nil else {
            present(error: .transcriptionExecutionFailed("This session does not have any saved audio files to transcribe yet."))
            return
        }

        sessions[index].status = .processing
        sessions[index].notes = "Retrying transcription..."
        processingMessage = "Processing in background"
        persist()

        startBackgroundProcessing(
            for: BackgroundProcessingRequest(
                session: sessions[index],
                captureSummary: sessions[index].notes,
                notePrefix: nil,
                shouldOptimizeAudio: false
            )
        )
    }

    func updateAlias(for session: SessionRecord, speakerLabel: String, alias: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].aliasMapping[speakerLabel] = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try transcriptRevisionService.refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after updating speaker aliases: \(error.localizedDescription)"))
        }
    }

    func addSpeakerSlot(to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].speakerCount = max(sessions[index].speakerCount + 1, 1)

        do {
            try transcriptRevisionService.refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after adding another speaker slot: \(error.localizedDescription)"))
        }
    }

    func updateSpeakerAssignment(
        for sessionID: UUID,
        segmentKey: String,
        speakerLabel: String,
        originalSpeakerLabel: String
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        if speakerLabel == originalSpeakerLabel {
            sessions[index].speakerAssignments.removeValue(forKey: segmentKey)
        } else {
            sessions[index].speakerAssignments[segmentKey] = speakerLabel
        }

        do {
            try transcriptRevisionService.refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after changing the speaker assignment: \(error.localizedDescription)"))
        }
    }

    func editableTranscriptSegments(for session: SessionRecord) -> [EditableTranscriptSegment] {
        guard let transcriptPath = session.transcriptPath else { return [] }
        return transcriptRevisionService.loadEditableSegments(from: transcriptPath, session: session)
    }

    func updateTranscriptSegment(
        for sessionID: UUID,
        segmentKey: String,
        originalText: String,
        editedText: String
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[index].transcriptPath != nil else {
            present(error: .transcriptExportFailed("LoqBar could not find the transcript file to save your manual correction."))
            return
        }

        let normalizedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEdited = editedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedEdited.isEmpty {
            present(error: .transcriptExportFailed("Manual transcript corrections cannot be empty."))
            return
        }

        if normalizedEdited == normalizedOriginal {
            sessions[index].transcriptEdits.removeValue(forKey: segmentKey)
        } else {
            sessions[index].transcriptEdits[segmentKey] = TranscriptEdit(
                originalText: normalizedOriginal,
                editedText: normalizedEdited,
                editedAt: Date()
            )
        }

        do {
            try transcriptRevisionService.applyEdits(to: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not save the transcript correction: \(error.localizedDescription)"))
        }
    }

    func updateSessionContext(
        for sessionID: UUID,
        sharedLinks: String,
        contextNotes: String
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[index].sharedLinks = sharedLinks.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[index].contextNotes = contextNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try transcriptRevisionService.refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after saving session context: \(error.localizedDescription)"))
        }
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

    func openRecordingRootFolder() {
        sessionStore.openRecordingRootFolder(settings: settings)
    }

    func openLatestRecordingFolder() {
        guard let session = latestSession else { return }
        sessionStore.openRecordingFolder(for: session)
    }

    func revealLatestMicrophoneRecording() {
        guard let path = latestSession?.audioPath else { return }
        sessionStore.revealFile(at: path)
    }

    func revealLatestSystemAudioRecording() {
        guard let path = latestSession?.systemAudioPath else { return }
        sessionStore.revealFile(at: path)
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func prepareToPresentAuxiliaryWindow() {
        _ = NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringAuxiliaryWindowToFront(titleContains titleFragment: String, remainingAttempts: Int = 8) {
        prepareToPresentAuxiliaryWindow()

        let matchingWindow = NSApp.windows.first { window in
            window.title.localizedCaseInsensitiveContains(titleFragment)
        }

        if let matchingWindow {
            matchingWindow.collectionBehavior.insert(.moveToActiveSpace)
            matchingWindow.level = .normal
            matchingWindow.orderFrontRegardless()
            matchingWindow.makeKeyAndOrderFront(nil)
            matchingWindow.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard remainingAttempts > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.bringAuxiliaryWindowToFront(
                titleContains: titleFragment,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    func restoreMenuBarPresentationIfPossible() {
        let auxiliaryWindowsAreVisible = NSApp.windows.contains { window in
            (window.title.localizedCaseInsensitiveContains("Settings") ||
             window.title.localizedCaseInsensitiveContains("Recent Sessions")) &&
            window.isVisible
        }

        guard !auxiliaryWindowsAreVisible else { return }

        _ = NSApp.setActivationPolicy(.accessory)
    }

    func chooseStorageRootFolder() {
        prepareToPresentAuxiliaryWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose the root folder where LoqBar should store recordings, transcripts, and managed files."
        panel.directoryURL = URL(fileURLWithPath: settings.storageRootFolder, isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            settings.storageRootFolder = url.path
        }
    }

    func createStorageRootFolder() {
        prepareToPresentAuxiliaryWindow()

        let currentRoot = URL(fileURLWithPath: settings.storageRootFolder, isDirectory: true)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Create Folder"
        panel.title = "Create Storage Root Folder"
        panel.message = "Create a new root folder for LoqBar recordings, transcripts, and managed files."
        panel.nameFieldLabel = "Folder name:"
        panel.nameFieldStringValue = currentRoot.lastPathComponent.isEmpty ? "LoqBar" : currentRoot.lastPathComponent
        panel.directoryURL = currentRoot.deletingLastPathComponent()
        panel.isExtensionHidden = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            settings.storageRootFolder = url.path
        } catch {
            present(error: .storageSetupFailed("LoqBar could not create the selected storage folder: \(error.localizedDescription)"))
        }
    }

    func chooseExternalWhisperExecutable() {
        prepareToPresentAuxiliaryWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Executable"
        panel.directoryURL = URL(fileURLWithPath: settings.transcriptionExecutablePath.nilIfEmpty ?? StoragePaths.appSupportFolder.path)

        if panel.runModal() == .OK, let url = panel.url {
            settings.transcriptionExecutablePath = url.path
        }
    }

    func chooseExternalModelFile() {
        prepareToPresentAuxiliaryWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Model File"
        panel.directoryURL = URL(fileURLWithPath: settings.transcriptionModelPath.nilIfEmpty ?? settings.storageRootFolder)

        if panel.runModal() == .OK, let url = panel.url {
            settings.transcriptionModelPath = url.path
        }
    }

    func clearExternalTranscriptionPaths() {
        settings.transcriptionExecutablePath = ""
        settings.transcriptionModelPath = ""
        persist()
    }

    func runCleanupNow() {
        runRetentionCleanup(markRunTimestamp: true)
    }

    func checkForUpdates() {
        guard updateStatus != .checking else { return }

        updateStatus = .checking
        let currentVersion = AppVersion.current()
        let configuration = AppReleaseFeedConfiguration.fromMainBundle()

        Task {
            let result = await updateCheckService.checkForUpdates(
                currentVersion: currentVersion,
                configuration: configuration
            )

            await MainActor.run {
                handleUpdateCheckResult(result)
            }
        }
    }

    func installManagedTranscriptionFiles() {
        guard !isInstallingManagedTranscription else { return }

        isInstallingManagedTranscription = true
        managedTranscriptionInstallStatus = "Preparing managed transcription setup…"

        Task {
            do {
                let result = try await managedTranscriptionInstallService.install(
                    settings: settings
                ) { [weak self] progress in
                    await MainActor.run {
                        self?.managedTranscriptionInstallStatus = progress
                    }
                }

                await MainActor.run {
                    self.managedTranscriptionInstallStatus = """
                    Managed transcription is ready.
                    \(result.executableSourceDescription)
                    \(result.modelSourceDescription)
                    """
                    self.isInstallingManagedTranscription = false
                    self.persist()
                }
            } catch let error as AppError {
                await MainActor.run {
                    self.isInstallingManagedTranscription = false
                    self.managedTranscriptionInstallStatus = "Managed transcription setup failed."
                    self.present(error: error)
                }
            } catch {
                await MainActor.run {
                    self.isInstallingManagedTranscription = false
                    self.managedTranscriptionInstallStatus = "Managed transcription setup failed."
                    self.present(error: .storageSetupFailed("LoqBar could not install the managed transcription files: \(error.localizedDescription)"))
                }
            }
        }
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

    private func apply(
        _ activeCapture: ActiveCaptureSession,
        optimizedAudio: OptimizedAudioFiles? = nil,
        to sessionID: UUID,
        fallbackNote: String
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].audioPath = optimizedAudio?.microphoneFileURL?.path ?? activeCapture.microphoneFileURL?.path
        sessions[index].systemAudioPath = optimizedAudio?.systemAudioFileURL?.path ?? activeCapture.systemAudioFileURL?.path

        let baseNote = activeCapture.summary.isEmpty ? fallbackNote : activeCapture.summary
        let optimizationNote = optimizedAudio?.notes.joined(separator: " ") ?? ""
        sessions[index].notes = [baseNote, optimizationNote]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        persist()
    }

    private func prepareStoppedSessionForBackgroundProcessing(
        sessionID: UUID,
        capture: ActiveCaptureSession,
        notePrefix: String?
    ) -> BackgroundProcessingRequest? {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }

        sessions[sessionIndex].endedAt = Date()
        sessions[sessionIndex].durationSeconds = max(
            Int(sessions[sessionIndex].endedAt?.timeIntervalSince(sessions[sessionIndex].startedAt) ?? 0),
            1
        )
        sessions[sessionIndex].audioPath = capture.microphoneFileURL?.path
        sessions[sessionIndex].systemAudioPath = capture.systemAudioFileURL?.path
        sessions[sessionIndex].notes = capture.summary
        isLocalMicCapturePaused = false
        processingMessage = "Processing in background"
        persist()

        return BackgroundProcessingRequest(
            session: sessions[sessionIndex],
            captureSummary: capture.summary,
            notePrefix: notePrefix,
            shouldOptimizeAudio: true
        )
    }

    private func startBackgroundProcessing(for request: BackgroundProcessingRequest) {
        let settingsSnapshot = settings

        Task.detached(priority: .userInitiated) {
            let outcome = SessionBackgroundProcessor.process(
                request: request,
                settings: settingsSnapshot
            )

            await MainActor.run {
                self.applyBackgroundProcessingOutcome(outcome, for: request.session.id)
            }
        }
    }

    private func applyBackgroundProcessingOutcome(_ outcome: BackgroundProcessingOutcome, for sessionID: UUID) {
        switch outcome {
        case let .success(result):
            guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

            sessions[sessionIndex].audioPath = result.audioPath
            sessions[sessionIndex].systemAudioPath = result.systemAudioPath
            sessions[sessionIndex].status = .completed
            sessions[sessionIndex].transcriptPath = result.transcriptPath
            sessions[sessionIndex].warningCount = result.warningCount
            sessions[sessionIndex].speakerCount = max(sessions[sessionIndex].speakerCount, result.speakerCount)
            sessions[sessionIndex].notes = result.notes
            sessions[sessionIndex].language = result.language
            persist()
            processingMessage = hasProcessingSessions ? "Processing in background" : "Transcript exported"
            isLocalMicCapturePaused = false
            runRetentionCleanupIfNeeded()

        case let .transcriptionPending(result):
            guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

            sessions[sessionIndex].audioPath = result.audioPath
            sessions[sessionIndex].systemAudioPath = result.systemAudioPath
            sessions[sessionIndex].status = .completed
            sessions[sessionIndex].notes = result.note
            persist()
            processingMessage = hasProcessingSessions ? "Processing in background" : "Recording saved, transcription pending"
            isLocalMicCapturePaused = false
            present(error: result.error)
        }
    }

    private func runRetentionCleanupIfNeeded() {
        guard settings.autoCleanupEnabled else { return }
        runRetentionCleanup(markRunTimestamp: false)
    }

    private func runRetentionCleanup(markRunTimestamp: Bool) {
        let result = retentionCleanupService.run(sessions: sessions, settings: settings)
        sessions = result.sessions

        if markRunTimestamp || result.deletedFileCount > 0 || result.deletedSessionFolderCount > 0 || settings.lastCleanupAt == nil {
            settings.lastCleanupAt = Date()
            settings.lastCleanupSummary = result.summary
        }

        persist()
    }

    private func handleUpdateCheckResult(_ result: UpdateCheckResult) {
        let now = Date()

        switch result {
        case let .updateAvailable(release):
            updateStatus = .updateAvailable(version: release.version.displayString, checkedAt: now)

            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = [
                "LoqBar \(release.version.displayString) is available.",
                release.notes?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220).description
            ]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: "\n\n")
            alert.addButton(withTitle: release.primaryActionURL == nil ? "OK" : "Open Release")
            if release.primaryActionURL != nil {
                alert.addButton(withTitle: "Later")
            }

            prepareToPresentAuxiliaryWindow()
            let response = alert.runModal()
            if response == .alertFirstButtonReturn, let url = release.primaryActionURL {
                NSWorkspace.shared.open(url)
            }

        case .upToDate:
            updateStatus = .upToDate(checkedAt: now)
            presentInformationalAlert(
                title: "LoqBar Is Up to Date",
                message: "You already have the latest available release for this build channel."
            )

        case .notConfigured:
            updateStatus = .notConfigured
            presentInformationalAlert(
                title: "Updates Not Configured",
                message: """
                This build does not include a release feed yet. Add a GitHub Releases API URL or release manifest URL during packaging to enable manual update checks.

                Current build: \(currentAppVersionDisplay)
                """
            )

        case let .failed(message):
            updateStatus = .failed(message: message)
            presentInformationalAlert(
                title: "Update Check Failed",
                message: message
            )
        }
    }

    private func presentInformationalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        prepareToPresentAuxiliaryWindow()
        alert.runModal()
    }

    private func observeWorkspaceLifecycle() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.handleWorkspaceWillSleep()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleWorkspaceDidWake()
            }
            .store(in: &cancellables)
    }

    private func handleWorkspaceWillSleep() {
        guard activeSession != nil || recordingCoordinator.hasActiveCapture else { return }
        stopRecording(interruptionNote: "Recording stopped because the Mac is going to sleep.")
    }

    private func handleWorkspaceDidWake() {
        refreshPermissions()
        processingMessage = activeSession == nil && !hasProcessingSessions ? "Ready" : processingMessage
    }

    private func handleCaptureInterruption(_ reason: CaptureInterruptionReason) {
        guard activeSession?.isRecording == true else { return }
        stopRecording(interruptionNote: reason.userFacingSummary)
    }

    private func markSessionFailed(_ sessionID: UUID, error: AppError) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .failed
            sessions[index].notes = error.recoverySuggestion
            isLocalMicCapturePaused = false
            persist()
        }
        present(error: error)
    }

    private func markSessionCompletedWithTranscriptionIssue(_ sessionID: UUID, error: AppError) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .completed
            sessions[index].notes = "Recording saved. Transcription pending: \(error.recoverySuggestion)"
            isLocalMicCapturePaused = false
            persist()
        }
        processingMessage = hasProcessingSessions ? "Processing in background" : "Recording saved, transcription pending"
        present(error: error)
    }
}

private struct BackgroundProcessingRequest: Sendable {
    let session: SessionRecord
    let captureSummary: String
    let notePrefix: String?
    let shouldOptimizeAudio: Bool
}

private struct BackgroundProcessingSuccess: Sendable {
    let audioPath: String?
    let systemAudioPath: String?
    let transcriptPath: String
    let warningCount: Int
    let speakerCount: Int
    let notes: String
    let language: String
}

private struct BackgroundProcessingFailure: Sendable {
    let audioPath: String?
    let systemAudioPath: String?
    let note: String
    let error: AppError
}

private enum BackgroundProcessingOutcome: Sendable {
    case success(BackgroundProcessingSuccess)
    case transcriptionPending(BackgroundProcessingFailure)
}

private enum SessionBackgroundProcessor {
    static func process(
        request: BackgroundProcessingRequest,
        settings: AppSettings
    ) -> BackgroundProcessingOutcome {
        var workingSession = request.session

        let optimizer = AudioStorageOptimizer()
        let transcriptionService = TranscriptionService()
        let transcriptExporter = TranscriptExporter()

        let optimizedAudio: OptimizedAudioFiles?
        if request.shouldOptimizeAudio {
            optimizedAudio = try? optimizer.optimize(
                microphoneFileURL: workingSession.audioPath.map(URL.init(fileURLWithPath:)),
                systemAudioFileURL: workingSession.systemAudioPath.map(URL.init(fileURLWithPath:))
            )
        } else {
            optimizedAudio = nil
        }

        workingSession.audioPath = optimizedAudio?.microphoneFileURL?.path ?? workingSession.audioPath
        workingSession.systemAudioPath = optimizedAudio?.systemAudioFileURL?.path ?? workingSession.systemAudioPath

        do {
            let plan = transcriptionService.makePlan(for: workingSession)
            let content = try transcriptionService.transcribe(
                plan: plan,
                session: workingSession,
                settings: settings
            )
            let transcript = try transcriptExporter.exportTranscript(
                for: workingSession,
                settings: settings,
                content: content
            )

            let finalNotes = ([transcript.summary] + transcript.planNotes).joined(separator: " ")
            let note = [request.notePrefix, finalNotes]
                .compactMap { $0?.nilIfEmpty }
                .joined(separator: " ")

            return .success(
                BackgroundProcessingSuccess(
                    audioPath: workingSession.audioPath,
                    systemAudioPath: workingSession.systemAudioPath,
                    transcriptPath: transcript.path,
                    warningCount: transcript.warningCount,
                    speakerCount: transcript.speakersDetected,
                    notes: note.isEmpty ? finalNotes : note,
                    language: content.language
                )
            )
        } catch let error as AppError {
            let note = "Recording saved. Transcription pending: \(error.recoverySuggestion)"
            return .transcriptionPending(
                BackgroundProcessingFailure(
                    audioPath: workingSession.audioPath,
                    systemAudioPath: workingSession.systemAudioPath,
                    note: note,
                    error: error
                )
            )
        } catch {
            let appError = AppError.transcriptionExecutionFailed(
                "Recording finished and audio was saved, but transcription could not complete: \(error.localizedDescription)"
            )
            let note = "Recording saved. Transcription pending: \(appError.recoverySuggestion)"
            return .transcriptionPending(
                BackgroundProcessingFailure(
                    audioPath: workingSession.audioPath,
                    systemAudioPath: workingSession.systemAudioPath,
                    note: note,
                    error: appError
                )
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
