import Foundation

@MainActor
extension AppModel {
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
            sessions[sessionIndex].speakerCount = max(
                sessions[sessionIndex].speakerCount,
                result.speakerCount,
                result.suggestedSpeakerRosterCount
            )
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
