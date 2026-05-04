import Foundation

struct TranscriptionService {
    private let whisperTranscriber = WhisperCLITranscriber()

    func makePlan(for session: SessionRecord) -> TranscriptionPlan {
        let microphoneFileURL = session.audioPath.map(URL.init(fileURLWithPath:))
        let systemAudioFileURL = session.systemAudioPath.map(URL.init(fileURLWithPath:))

        switch session.audioSourceType {
        case .systemAudioOnly:
            return TranscriptionPlan(
                sessionID: session.id,
                title: session.title,
                captureMode: session.captureMode,
                audioSourceType: session.audioSourceType,
                microphoneFileURL: nil,
                systemAudioFileURL: systemAudioFileURL,
                preferredSources: [.systemAudio],
                notes: [
                    "System-audio-only diagnostic run.",
                    "Use ScreenCaptureKit output as the sole transcription source."
                ]
            )

        case .microphoneOnly:
            return TranscriptionPlan(
                sessionID: session.id,
                title: session.title,
                captureMode: session.captureMode,
                audioSourceType: session.audioSourceType,
                microphoneFileURL: microphoneFileURL,
                systemAudioFileURL: nil,
                preferredSources: [.microphone],
                notes: [
                    "Microphone-only capture.",
                    "Use the microphone track as the sole transcription source."
                ]
            )

        case .appAudioPlusMicrophone, .separatedSystemAndMicrophone:
            return TranscriptionPlan(
                sessionID: session.id,
                title: session.title,
                captureMode: session.captureMode,
                audioSourceType: session.audioSourceType,
                microphoneFileURL: microphoneFileURL,
                systemAudioFileURL: systemAudioFileURL,
                preferredSources: [.systemAudio, .microphone],
                notes: [
                    "Teams-call split capture detected.",
                    "Prefer system audio for remote participants and microphone for the local speaker.",
                    "Do not blindly merge both tracks; remote speech may be duplicated if the microphone picked up loudspeaker playback."
                ]
            )

        case .unknown:
            return TranscriptionPlan(
                sessionID: session.id,
                title: session.title,
                captureMode: session.captureMode,
                audioSourceType: session.audioSourceType,
                microphoneFileURL: microphoneFileURL,
                systemAudioFileURL: systemAudioFileURL,
                preferredSources: [.microphone],
                notes: [
                    "Fallback transcription plan.",
                    "Prefer whichever local source is available."
                ]
            )
        }
    }

    func transcribe(plan: TranscriptionPlan, session: SessionRecord, settings: AppSettings) throws -> TranscriptContent {
        let start = session.startedAt
        guard let whisperConfiguration = WhisperConfiguration.from(
            settings: settings,
            languageOverride: session.transcriptionLanguageOverride
        ) else {
            let setupMessage: String

            if settings.hasExternalTranscriptionPaths {
                setupMessage = "Recording finished and audio was saved, but LoqBar could not use the configured transcription files. Open Settings > Transcription and check the whisper-cli path and model path, then retry transcription later."
            } else {
                setupMessage = "Recording finished and audio was saved, but transcription is not set up yet. Open Settings > Transcription to choose an existing whisper-cli and model, or install managed files into the hidden .loqbar folder inside your storage root, then retry later."
            }

            throw AppError.transcriptionConfigurationMissing(
                setupMessage
            )
        }
        let execution = try runTranscription(plan: plan, start: start, configuration: whisperConfiguration)

        return TranscriptContent(
            title: session.title,
            language: execution.language,
            segments: execution.segments,
            speakersDetected: execution.speakersDetected,
            warningCount: execution.segments.filter(\.lowConfidence).count,
            summary: execution.summary,
            analysis: execution.analysis
        )
    }

    private func runTranscription(
        plan: TranscriptionPlan,
        start: Date,
        configuration: WhisperConfiguration
    ) throws -> (segments: [TranscriptSegment], speakersDetected: Int, summary: String, analysis: TranscriptionAnalysis, language: String) {
        let merged = try transcribePreferredSources(plan: plan, sessionStart: start, configuration: configuration)
        let analysis = TranscriptionAnalysis(
            primarySources: plan.preferredSources.map(\.rawValue),
            notes: plan.notes + merged.notes,
            engineDescription: merged.engineDescription
        )
        let resolvedLanguage = merged.language ?? configuration.language ?? "auto"
        return (merged.segments, merged.speakersDetected, summaryText(for: plan, engineDescription: merged.engineDescription), analysis, resolvedLanguage)
    }

    private func transcribePreferredSources(
        plan: TranscriptionPlan,
        sessionStart: Date,
        configuration: WhisperConfiguration
    ) throws -> (segments: [TranscriptSegment], speakersDetected: Int, engineDescription: String, language: String?, notes: [String]) {
        var transcriptSegments: [MergeCandidateSegment] = []
        var engineDescription = "whisper-cli"
        var detectedLanguage: String?

        for source in plan.preferredSources {
            let fileURL: URL?
            let speakerLabel: String

            switch source {
            case .microphone:
                fileURL = plan.microphoneFileURL
                speakerLabel = plan.audioSourceType == .microphoneOnly ? "Speaker1" : "Speaker2"
            case .systemAudio:
                fileURL = plan.systemAudioFileURL
                speakerLabel = "Speaker1"
            }

            guard let fileURL else { continue }

            let transcription = try whisperTranscriber.transcribe(audioFileURL: fileURL, configuration: configuration)
            engineDescription = transcription.engineDescription
            if detectedLanguage == nil {
                let normalizedLanguage = transcription.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                detectedLanguage = normalizedLanguage.isEmpty ? nil : normalizedLanguage
            }

            let mappedSegments = transcription.segments.map { segment in
                MergeCandidateSegment(
                    id: UUID(),
                    absoluteTimestamp: sessionStart.addingTimeInterval(segment.startTime),
                    relativeOffset: segment.startTime,
                    relativeEndOffset: max(segment.endTime, segment.startTime),
                    speakerLabel: speakerLabel,
                    source: source.rawValue,
                    text: segment.text,
                    lowConfidence: false,
                    sourcePriority: source == .systemAudio ? 0 : 1
                )
            }

            transcriptSegments.append(contentsOf: mappedSegments)
        }

        let reconciliation = reconcileSplitSourceSegments(transcriptSegments)
        let sortedSegments = reconciliation.segments.sorted { lhs, rhs in
            if lhs.relativeOffset == rhs.relativeOffset {
                return lhs.sourcePriority < rhs.sourcePriority
            }
            return lhs.relativeOffset < rhs.relativeOffset
        }

        if sortedSegments.isEmpty {
            throw AppError.transcriptionExecutionFailed("whisper.cpp ran, but produced no transcript segments for the selected audio sources.")
        }

        let exportedSegments = sortedSegments.map { segment in
            TranscriptSegment(
                absoluteTimestamp: segment.absoluteTimestamp,
                relativeOffset: segment.relativeOffset,
                speakerLabel: segment.speakerLabel,
                source: segment.source,
                text: segment.text,
                lowConfidence: segment.lowConfidence
            )
        }

        let speakersDetected = Set(exportedSegments.map(\.speakerLabel)).count
        let notes = reconciliation.notes
        return (exportedSegments, max(speakersDetected, 1), engineDescription, detectedLanguage, notes)
    }

    private func reconcileSplitSourceSegments(_ segments: [MergeCandidateSegment]) -> MergeReconciliationReport {
        let filtered = segments.filter { !shouldDropSegment($0) }
        let droppedLowValueCount = segments.count - filtered.count

        let sorted = filtered.sorted { lhs, rhs in
            if lhs.relativeOffset == rhs.relativeOffset {
                return lhs.sourcePriority < rhs.sourcePriority
            }
            return lhs.relativeOffset < rhs.relativeOffset
        }

        var kept: [MergeCandidateSegment] = []
        var duplicateCount = 0
        var microphoneDuplicateCount = 0

        for segment in sorted {
            if let duplicateIndex = kept.firstIndex(where: { existing in
                segmentsLikelyDuplicate(existing, segment)
            }) {
                let existing = kept[duplicateIndex]
                let preferred = preferredSegment(between: existing, and: segment)
                let discarded = preferred.id == existing.id ? segment : existing
                if discarded.source == PreferredTranscriptSource.microphone.rawValue,
                   preferred.source == PreferredTranscriptSource.systemAudio.rawValue {
                    microphoneDuplicateCount += 1
                }
                duplicateCount += 1
                kept[duplicateIndex] = preferred
            } else {
                kept.append(segment)
            }
        }

        var notes: [String] = []

        if droppedLowValueCount > 0 {
            notes.append("Merge reconciliation removed \(droppedLowValueCount) low-value segment\(droppedLowValueCount == 1 ? "" : "s") such as blank-audio placeholders before merging.")
        }

        if duplicateCount > 0 {
            var duplicateNote = "Merge reconciliation removed \(duplicateCount) overlapping duplicate segment\(duplicateCount == 1 ? "" : "s")"
            if microphoneDuplicateCount > 0 {
                duplicateNote += ", including \(microphoneDuplicateCount) microphone segment\(microphoneDuplicateCount == 1 ? "" : "s") that appeared to be loudspeaker bleed from remote audio"
            }
            duplicateNote += "."
            notes.append(duplicateNote)
        }

        if notes.isEmpty {
            notes.append("Merge reconciliation found no obvious duplicate overlap between microphone and system audio segments.")
        }

        return MergeReconciliationReport(
            segments: kept,
            droppedLowValueCount: droppedLowValueCount,
            duplicateCount: duplicateCount,
            microphoneDuplicateCount: microphoneDuplicateCount,
            notes: notes
        )
    }

    private func segmentsLikelyDuplicate(_ lhs: MergeCandidateSegment, _ rhs: MergeCandidateSegment) -> Bool {
        guard lhs.source != rhs.source else { return false }

        let similarity = transcriptSimilarity(lhs.text, rhs.text)
        if segmentLooksLikeStandaloneContent(lhs) && segmentLooksLikeStandaloneContent(rhs) && similarity < 0.72 {
            return false
        }

        let overlap = overlappingDuration(lhs, rhs)
        let shorterDuration = max(min(lhs.duration, rhs.duration), 0.25)
        let overlapRatio = overlap / shorterDuration
        let startDelta = abs(lhs.relativeOffset - rhs.relativeOffset)
        let tokenCountDelta = abs(normalizedTranscriptTokens(from: lhs.text).count - normalizedTranscriptTokens(from: rhs.text).count)

        let strongOverlap = overlapRatio >= 0.45
        let closeInTime = startDelta <= 1.2
        let textMatch = similarity >= 0.72
        let likelyBleedCapture = overlapRatio >= 0.7 && similarity >= 0.55 && tokenCountDelta <= 2

        return (textMatch && (strongOverlap || closeInTime)) || likelyBleedCapture
    }

    private func preferredSegment(between lhs: MergeCandidateSegment, and rhs: MergeCandidateSegment) -> MergeCandidateSegment {
        let lhsScore = segmentPreferenceScore(lhs)
        let rhsScore = segmentPreferenceScore(rhs)

        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }

        if lhs.sourcePriority != rhs.sourcePriority {
            return lhs.sourcePriority < rhs.sourcePriority ? lhs : rhs
        }

        if lhs.text.count != rhs.text.count {
            return lhs.text.count >= rhs.text.count ? lhs : rhs
        }

        return lhs.duration >= rhs.duration ? lhs : rhs
    }

    private func shouldDropSegment(_ segment: MergeCandidateSegment) -> Bool {
        let normalized = normalizedSegmentText(segment.text)

        if normalized.isEmpty {
            return true
        }

        let placeholderPhrases: Set<String> = [
            "blank audio",
            "silence",
            "no speech",
            "no captions"
        ]

        if placeholderPhrases.contains(normalized) {
            return true
        }

        return false
    }

    private func segmentLooksLikeStandaloneContent(_ segment: MergeCandidateSegment) -> Bool {
        let normalized = normalizedTranscriptTokens(from: segment.text)
        return normalized.count >= 4 || segment.text.count >= 24 || segment.duration >= 3.5
    }

    private func segmentPreferenceScore(_ segment: MergeCandidateSegment) -> Int {
        let tokenCount = normalizedTranscriptTokens(from: segment.text).count
        let lengthScore = min(segment.text.count / 12, 4)
        let durationScore = Int(min(segment.duration, 6).rounded(.down))
        let sourceScore = segment.source == PreferredTranscriptSource.systemAudio.rawValue ? 3 : 0
        let blankPenalty = shouldDropSegment(segment) ? -100 : 0
        return blankPenalty + sourceScore + (tokenCount * 2) + lengthScore + durationScore
    }

    private func normalizedSegmentText(_ text: String) -> String {
        normalizedTranscriptTokens(from: text).joined(separator: " ")
    }

    private func overlappingDuration(_ lhs: MergeCandidateSegment, _ rhs: MergeCandidateSegment) -> TimeInterval {
        let start = max(lhs.relativeOffset, rhs.relativeOffset)
        let end = min(lhs.relativeEndOffset, rhs.relativeEndOffset)
        return max(0, end - start)
    }

    private func transcriptSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let normalizedLHS = normalizedTranscriptTokens(from: lhs)
        let normalizedRHS = normalizedTranscriptTokens(from: rhs)

        guard !normalizedLHS.isEmpty, !normalizedRHS.isEmpty else { return 0 }
        if normalizedLHS == normalizedRHS {
            return 1
        }

        let lhsSet = Set(normalizedLHS)
        let rhsSet = Set(normalizedRHS)
        let intersection = lhsSet.intersection(rhsSet).count
        let union = lhsSet.union(rhsSet).count
        let jaccard = union == 0 ? 0 : Double(intersection) / Double(union)

        let lhsJoined = normalizedLHS.joined(separator: " ")
        let rhsJoined = normalizedRHS.joined(separator: " ")
        let containment = lhsJoined.contains(rhsJoined) || rhsJoined.contains(lhsJoined) ? 1.0 : 0.0

        return max(jaccard, containment)
    }

    private func normalizedTranscriptTokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func summaryText(for plan: TranscriptionPlan, engineDescription: String) -> String {
        switch plan.audioSourceType {
        case .systemAudioOnly:
            return "Diagnostic system-audio-only export complete using \(engineDescription)."
        case .microphoneOnly:
            return "Diagnostic microphone-only export complete using \(engineDescription)."
        case .appAudioPlusMicrophone, .separatedSystemAndMicrophone:
            return "Split-source export complete using \(engineDescription). LoqBar plans remote transcription from system audio and local transcription from the microphone track."
        case .unknown:
            return "Fallback export complete using \(engineDescription)."
        }
    }
}

private struct MergeReconciliationReport {
    let segments: [MergeCandidateSegment]
    let droppedLowValueCount: Int
    let duplicateCount: Int
    let microphoneDuplicateCount: Int
    let notes: [String]
}

private struct MergeCandidateSegment {
    let id: UUID
    let absoluteTimestamp: Date
    let relativeOffset: TimeInterval
    let relativeEndOffset: TimeInterval
    let speakerLabel: String
    let source: String
    let text: String
    let lowConfidence: Bool
    let sourcePriority: Int

    var duration: TimeInterval {
        max(relativeEndOffset - relativeOffset, 0)
    }
}
