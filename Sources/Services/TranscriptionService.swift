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

        let mergedSegments = reconcileSplitSourceSegments(transcriptSegments)
        let sortedSegments = mergedSegments.sorted { lhs, rhs in
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
        let duplicateCount = transcriptSegments.count - sortedSegments.count
        let notes = duplicateCount > 0
            ? ["Merge reconciliation removed \(duplicateCount) overlapping duplicate segment\(duplicateCount == 1 ? "" : "s"), preferring system audio when both sources appeared to contain the same speech."]
            : ["Merge reconciliation found no obvious duplicate overlap between microphone and system audio segments."]
        return (exportedSegments, max(speakersDetected, 1), engineDescription, detectedLanguage, notes)
    }

    private func reconcileSplitSourceSegments(_ segments: [MergeCandidateSegment]) -> [MergeCandidateSegment] {
        let sorted = segments.sorted { lhs, rhs in
            if lhs.relativeOffset == rhs.relativeOffset {
                return lhs.sourcePriority < rhs.sourcePriority
            }
            return lhs.relativeOffset < rhs.relativeOffset
        }

        var kept: [MergeCandidateSegment] = []

        for segment in sorted {
            if let duplicateIndex = kept.firstIndex(where: { existing in
                segmentsLikelyDuplicate(existing, segment)
            }) {
                let preferred = preferredSegment(between: kept[duplicateIndex], and: segment)
                kept[duplicateIndex] = preferred
            } else {
                kept.append(segment)
            }
        }

        return kept
    }

    private func segmentsLikelyDuplicate(_ lhs: MergeCandidateSegment, _ rhs: MergeCandidateSegment) -> Bool {
        guard lhs.source != rhs.source else { return false }

        let overlap = overlappingDuration(lhs, rhs)
        let shorterDuration = max(min(lhs.duration, rhs.duration), 0.25)
        let overlapRatio = overlap / shorterDuration
        let startDelta = abs(lhs.relativeOffset - rhs.relativeOffset)
        let similarity = transcriptSimilarity(lhs.text, rhs.text)

        let strongOverlap = overlapRatio >= 0.45
        let closeInTime = startDelta <= 1.2
        let textMatch = similarity >= 0.72

        return textMatch && (strongOverlap || closeInTime)
    }

    private func preferredSegment(between lhs: MergeCandidateSegment, and rhs: MergeCandidateSegment) -> MergeCandidateSegment {
        if lhs.sourcePriority != rhs.sourcePriority {
            return lhs.sourcePriority < rhs.sourcePriority ? lhs : rhs
        }

        if lhs.text.count != rhs.text.count {
            return lhs.text.count >= rhs.text.count ? lhs : rhs
        }

        return lhs.duration >= rhs.duration ? lhs : rhs
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

private struct MergeCandidateSegment {
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
