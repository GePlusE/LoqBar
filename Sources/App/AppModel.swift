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
    let retentionCleanupService: RetentionCleanupService
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

enum SessionBackgroundProcessor {
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
