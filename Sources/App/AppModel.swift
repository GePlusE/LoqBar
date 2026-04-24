import Foundation
import SwiftUI
import AppKit

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
    private let transcriptionService: TranscriptionService
    private let captureService: CaptureService
    private let recordingCoordinator: AudioCaptureCoordinator
    private let audioStorageOptimizer: AudioStorageOptimizer
    private let transcriptRevisionService: TranscriptRevisionService
    private let retentionCleanupService: RetentionCleanupService

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
        retentionCleanupService: RetentionCleanupService = RetentionCleanupService()
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

        loadInitialState()
    }

    var activeSession: SessionRecord? {
        sessions.first(where: \.isActive)
    }

    var latestSession: SessionRecord? {
        sessions.sorted(by: { $0.startedAt > $1.startedAt }).first
    }

    var menuBarIconName: String {
        isRecordingInMenuBar ? "apple.books.pages.fill" : "apple.books.pages"
    }

    var isRecordingInMenuBar: Bool {
        activeSession != nil
    }

    var transcriptionSetupStatus: TranscriptionSetupStatus {
        TranscriptionSetupStatus.from(settings: settings)
    }

    func loadInitialState() {
        settings = sessionStore.loadSettings()
        sessions = sessionStore.loadSessions()
        permissionState = permissionsService.currentState()
        firstRunState = FirstRunState(
            needsOnboarding: !settings.firstRunCompleted,
            launchAtLogin: settings.launchAtLoginEnabled
        )
        runRetentionCleanupIfNeeded()
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
                }
            } catch {
                await MainActor.run {
                    markSessionFailed(session.id, error: .recordingStartupFailed(error.localizedDescription))
                }
            }
        }
    }

    func startDiagnosticRecording(_ diagnosticKind: DiagnosticCaptureKind) {
        guard activeSession == nil else { return }

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
                }
            } catch {
                await MainActor.run {
                    markSessionFailed(session.id, error: .recordingStartupFailed(error.localizedDescription))
                }
            }
        }
    }

    func stopRecording() {
        guard let session = activeSession else { return }

        if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[sessionIndex].status = .processing
            sessions[sessionIndex].notes = "Stopping capture..."
            persist()
        }

        Task {
            do {
                let activeCapture = try await recordingCoordinator.stop()
                let optimizedAudio = try? audioStorageOptimizer.optimize(activeCapture)
                apply(
                    activeCapture,
                    optimizedAudio: optimizedAudio,
                    to: session.id,
                    fallbackNote: "Capture finished."
                )
                finalizeSession(session.id)
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

    func renameSession(_ session: SessionRecord, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? sessions[index].title
        persist()
    }

    func deleteSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions[index]

        guard !session.isActive else {
            present(error: .sessionDeletionFailed("Stop the active recording before deleting this session."))
            return
        }

        do {
            try sessionStore.deleteArtifacts(for: session)
            sessions.remove(at: index)
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
        persist()
    }

    func retryTranscription(for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard !sessions[index].isActive else { return }
        guard sessions[index].audioPath != nil || sessions[index].systemAudioPath != nil else {
            present(error: .transcriptionExecutionFailed("This session does not have any saved audio files to transcribe yet."))
            return
        }

        sessions[index].status = .processing
        sessions[index].notes = "Retrying transcription..."
        persist()

        Task {
            do {
                try transcribeAndExportSession(sessionID)
            } catch let error as AppError {
                markSessionCompletedWithTranscriptionIssue(sessionID, error: error)
            } catch {
                markSessionCompletedWithTranscriptionIssue(
                    sessionID,
                    error: .transcriptionExecutionFailed("Recording finished and audio was saved, but transcription could not complete: \(error.localizedDescription)")
                )
            }
        }
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
        guard let transcriptPath = sessions[index].transcriptPath else {
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
            try transcriptRevisionService.applyEdits(
                to: transcriptPath,
                edits: sessions[index].transcriptEdits,
                speakerAssignments: sessions[index].speakerAssignments
            )
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not save the transcript correction: \(error.localizedDescription)"))
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
            matchingWindow.level = .floating
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

    func installManagedTranscriptionFiles() {
        do {
            let source = try resolveManagedTranscriptionInstallSource()
            let fileManager = FileManager.default

            let executableURL = URL(fileURLWithPath: settings.managedTranscriptionExecutablePath)
            let modelURL = URL(fileURLWithPath: settings.managedTranscriptionModelPath)

            try fileManager.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: executableURL.path) {
                try fileManager.removeItem(at: executableURL)
            }
            if fileManager.fileExists(atPath: modelURL.path) {
                try fileManager.removeItem(at: modelURL)
            }

            try fileManager.copyItem(at: source.executableURL, to: executableURL)
            try fileManager.copyItem(at: source.modelURL, to: modelURL)

            var permissions = stat()
            if stat(executableURL.path, &permissions) == 0 {
                chmod(executableURL.path, permissions.st_mode | S_IXUSR | S_IXGRP | S_IXOTH)
            }

            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .storageSetupFailed("LoqBar could not install the managed transcription files: \(error.localizedDescription)"))
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

    private func resolveManagedTranscriptionInstallSource() throws -> (executableURL: URL, modelURL: URL) {
        let fileManager = FileManager.default

        let externalExecutable = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalModel = settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if !externalExecutable.isEmpty,
           !externalModel.isEmpty,
           fileManager.isExecutableFile(atPath: externalExecutable),
           fileManager.fileExists(atPath: externalModel) {
            return (
                executableURL: URL(fileURLWithPath: externalExecutable),
                modelURL: URL(fileURLWithPath: externalModel)
            )
        }

        let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let bundledExecutable = workspaceRoot
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("whisper.cpp", isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli")
        let bundledModel = workspaceRoot
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("whisper.cpp", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("ggml-base.bin")

        if fileManager.isExecutableFile(atPath: bundledExecutable.path),
           fileManager.fileExists(atPath: bundledModel.path) {
            return (executableURL: bundledExecutable, modelURL: bundledModel)
        }

        throw AppError.transcriptionConfigurationMissing(
            "LoqBar could not find a usable whisper-cli and model pair to install. Choose working external files first, or provide a managed source in the developer workspace."
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

    private func finalizeSession(_ sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[sessionIndex].endedAt = Date()
        sessions[sessionIndex].durationSeconds = max(
            Int(sessions[sessionIndex].endedAt?.timeIntervalSince(sessions[sessionIndex].startedAt) ?? 0),
            1
        )
        processingMessage = "Generating transcript export"

        do {
            try transcribeAndExportSession(sessionID)
            runRetentionCleanupIfNeeded()
        } catch let error as AppError {
            markSessionCompletedWithTranscriptionIssue(sessionID, error: error)
        } catch {
            markSessionCompletedWithTranscriptionIssue(
                sessionID,
                error: .transcriptionExecutionFailed("Recording finished and audio was saved, but transcription could not complete: \(error.localizedDescription)")
            )
        }
    }

    private func transcribeAndExportSession(_ sessionID: UUID) throws {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        do {
            let plan = transcriptionService.makePlan(for: sessions[sessionIndex])
            let content = try transcriptionService.transcribe(
                plan: plan,
                session: sessions[sessionIndex],
                settings: settings
            )
            let transcript = try transcriptExporter.exportTranscript(
                for: sessions[sessionIndex],
                settings: settings,
                content: content
            )
            sessions[sessionIndex].status = .completed
            sessions[sessionIndex].transcriptPath = transcript.path
            sessions[sessionIndex].warningCount = transcript.warningCount
            sessions[sessionIndex].speakerCount = transcript.speakersDetected
            sessions[sessionIndex].notes = ([transcript.summary] + transcript.planNotes).joined(separator: " ")
            processingMessage = "Transcript exported"
            persist()
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

    private func markSessionFailed(_ sessionID: UUID, error: AppError) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .failed
            sessions[index].notes = error.recoverySuggestion
            persist()
        }
        present(error: error)
    }

    private func markSessionCompletedWithTranscriptionIssue(_ sessionID: UUID, error: AppError) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .completed
            sessions[index].notes = "Recording saved. Transcription pending: \(error.recoverySuggestion)"
            persist()
        }
        processingMessage = "Recording saved, transcription pending"
        present(error: error)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
