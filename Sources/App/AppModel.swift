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
    var recentlyUpdatedToVersion: String?
    var hasShownPostUpdatePermissionHint = false

    let permissionsService: PermissionsService
    let loginItemService: LoginItemService
    let sessionStore: SessionStore
    private let transcriptExporter: TranscriptExporter
    private let transcriptionService: TranscriptionService
    let captureService: CaptureService
    let recordingCoordinator: AudioCaptureCoordinator
    private let audioStorageOptimizer: AudioStorageOptimizer
    private let transcriptRevisionService: TranscriptRevisionService
    private let retentionCleanupService: RetentionCleanupService
    let updateCheckService: UpdateCheckService
    let managedTranscriptionInstallService: ManagedTranscriptionInstallService
    var cancellables = Set<AnyCancellable>()

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

    var firstUseReadinessItems: [FirstUseReadinessItem] {
        [
            FirstUseReadinessItem(
                title: "Microphone Permission",
                detail: permissionState.microphoneAuthorized
                    ? "LoqBar can record your local voice and in-person meetings."
                    : "Required for any local recording. Enable microphone access in System Settings.",
                state: permissionState.microphoneAuthorized ? .ready : .required
            ),
            FirstUseReadinessItem(
                title: "Screen & System Audio Recording",
                detail: permissionState.screenCaptureAuthorized
                    ? "LoqBar can attempt Remote mode call capture."
                    : "Recommended if you want Remote mode for calls. Local mode still works without it.",
                state: permissionState.screenCaptureAuthorized ? .ready : .recommended
            ),
            FirstUseReadinessItem(
                title: "Storage Root Folder",
                detail: settings.storageRootFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Choose where LoqBar should keep recordings, transcripts, and managed files."
                    : "LoqBar will store recordings and transcripts under \(settings.storageRootFolder).",
                state: settings.storageRootFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .required : .ready
            ),
            FirstUseReadinessItem(
                title: "Transcription Setup",
                detail: transcriptionSetupStatus.isReady
                    ? "LoqBar can transcribe recordings locally on this Mac."
                    : "Recommended if you want transcripts. Open Transcription settings and install a managed copy or choose external whisper files.",
                state: transcriptionSetupStatus.isReady ? .ready : .recommended
            )
        ]
    }

    var firstUseReadinessSummary: String {
        let requiredCount = firstUseReadinessItems.filter { $0.state == .required }.count
        let recommendedCount = firstUseReadinessItems.filter { $0.state == .recommended }.count

        if requiredCount == 0 && recommendedCount == 0 {
            return "LoqBar is ready for recording and transcription on this Mac."
        }

        if requiredCount == 0 {
            return "LoqBar is ready for recording. \(recommendedCount) optional setup step\(recommendedCount == 1 ? "" : "s") can still improve the full workflow."
        }

        return "\(requiredCount) required setup step\(requiredCount == 1 ? "" : "s") still needs attention before LoqBar is fully ready."
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

    func renameSession(_ session: SessionRecord, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? sessions[index].title
        do {
            try refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after renaming the session: \(error.localizedDescription)"))
        }
    }

    func updateSessionTranscriptionLanguage(_ sessionID: UUID, language: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].transcriptionLanguageOverride = language == TranscriptionLanguageOption.auto.rawValue ? nil : language
        if language != TranscriptionLanguageOption.auto.rawValue {
            sessions[index].language = language
        }

        do {
            try refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after updating the transcription language: \(error.localizedDescription)"))
        }
    }

    func updateAlias(for session: SessionRecord, speakerLabel: String, alias: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].aliasMapping[speakerLabel] = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try refreshTranscriptPresentation(for: sessions[index])
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
            try refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after changing the speaker assignment: \(error.localizedDescription)"))
        }
    }

    func persist() {
        sessionStore.save(settings: settings)
        sessionStore.save(sessions: sessions)
    }

    func present(error: AppError) {
        alertContext = AlertContext(
            title: error.title,
            message: error.recoverySuggestion
        )
    }

    func dismissAlert() {
        alertContext = nil
    }

    func refreshTranscriptPresentation(for session: SessionRecord) throws {
        try transcriptRevisionService.refreshTranscriptPresentation(for: session)
    }

    func applyTranscriptEdits(to session: SessionRecord) throws {
        try transcriptRevisionService.applyEdits(to: session)
    }

    func loadEditableTranscriptSegments(for session: SessionRecord) -> [EditableTranscriptSegment] {
        guard let transcriptPath = session.transcriptPath else { return [] }
        return transcriptRevisionService.loadEditableSegments(from: transcriptPath, session: session)
    }

    func apply(
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

    func prepareStoppedSessionForBackgroundProcessing(
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

    func startBackgroundProcessing(for request: BackgroundProcessingRequest) {
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

    func applyBackgroundProcessingOutcome(_ outcome: BackgroundProcessingOutcome, for sessionID: UUID) {
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

    func runRetentionCleanupIfNeeded() {
        guard settings.autoCleanupEnabled else { return }
        runRetentionCleanup(markRunTimestamp: false)
    }

    func runRetentionCleanup(markRunTimestamp: Bool) {
        let result = retentionCleanupService.run(sessions: sessions, settings: settings)
        sessions = result.sessions

        if markRunTimestamp || result.deletedFileCount > 0 || result.deletedSessionFolderCount > 0 || settings.lastCleanupAt == nil {
            settings.lastCleanupAt = Date()
            settings.lastCleanupSummary = result.summary
        }

        persist()
    }

    func handleCaptureInterruption(_ reason: CaptureInterruptionReason) {
        guard activeSession?.isRecording == true else { return }
        stopRecording(interruptionNote: reason.userFacingSummary)
    }

    func markSessionFailed(_ sessionID: UUID, error: AppError) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .failed
            sessions[index].notes = error.recoverySuggestion
            isLocalMicCapturePaused = false
            persist()
        }
        present(error: error)
    }

    func markSessionCompletedWithTranscriptionIssue(_ sessionID: UUID, error: AppError) {
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

struct BackgroundProcessingRequest: Sendable {
    let session: SessionRecord
    let captureSummary: String
    let notePrefix: String?
    let shouldOptimizeAudio: Bool
}

struct BackgroundProcessingSuccess: Sendable {
    let audioPath: String?
    let systemAudioPath: String?
    let transcriptPath: String
    let warningCount: Int
    let speakerCount: Int
    let notes: String
    let language: String
}

struct BackgroundProcessingFailure: Sendable {
    let audioPath: String?
    let systemAudioPath: String?
    let note: String
    let error: AppError
}

enum BackgroundProcessingOutcome: Sendable {
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

struct FirstUseReadinessItem: Identifiable {
    enum State {
        case ready
        case recommended
        case required

        var title: String {
            switch self {
            case .ready:
                return "Ready"
            case .recommended:
                return "Recommended"
            case .required:
                return "Required"
            }
        }
    }

    let id = UUID()
    let title: String
    let detail: String
    let state: State
}
