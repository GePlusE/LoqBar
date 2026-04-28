import Foundation

@MainActor
extension AppModel {
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
}
