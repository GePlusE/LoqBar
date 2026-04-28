import Foundation

@MainActor
extension AppModel {
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

    func addSpeakerSlot(to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].speakerCount = max(sessions[index].speakerCount + 1, 1)

        do {
            try refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after adding another speaker slot: \(error.localizedDescription)"))
        }
    }

    func editableTranscriptSegments(for session: SessionRecord) -> [EditableTranscriptSegment] {
        loadEditableTranscriptSegments(for: session)
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
            try applyTranscriptEdits(to: sessions[index])
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
            try refreshTranscriptPresentation(for: sessions[index])
            persist()
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .transcriptExportFailed("LoqBar could not refresh the transcript after saving session context: \(error.localizedDescription)"))
        }
    }
}
