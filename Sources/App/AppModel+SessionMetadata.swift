import Foundation

@MainActor
extension AppModel {
    func renameSession(_ session: SessionRecord, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[index].title = normalizedTitle.isEmpty ? sessions[index].title : normalizedTitle
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
}
