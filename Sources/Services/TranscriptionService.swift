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
        guard let whisperConfiguration = WhisperConfiguration.from(settings: settings) else {
            throw AppError.transcriptionConfigurationMissing(
                "Recording finished and audio was saved, but transcription is not configured yet. Set both the `whisper-cli path` and `Model file path` in Settings, then retry transcription later."
            )
        }
        let execution = try runTranscription(plan: plan, start: start, configuration: whisperConfiguration)

        return TranscriptContent(
            title: session.title,
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
    ) throws -> (segments: [TranscriptSegment], speakersDetected: Int, summary: String, analysis: TranscriptionAnalysis) {
        let merged = try transcribePreferredSources(plan: plan, sessionStart: start, configuration: configuration)
        let analysis = TranscriptionAnalysis(
            primarySources: plan.preferredSources.map(\.rawValue),
            notes: plan.notes,
            engineDescription: merged.engineDescription
        )
        return (merged.segments, merged.speakersDetected, summaryText(for: plan, engineDescription: merged.engineDescription), analysis)
    }

    private func transcribePreferredSources(
        plan: TranscriptionPlan,
        sessionStart: Date,
        configuration: WhisperConfiguration
    ) throws -> (segments: [TranscriptSegment], speakersDetected: Int, engineDescription: String) {
        var transcriptSegments: [TranscriptSegment] = []
        var engineDescription = "whisper-cli"

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

            let mappedSegments = transcription.segments.enumerated().map { index, segment in
                TranscriptSegment(
                    absoluteTimestamp: sessionStart.addingTimeInterval(segment.startTime),
                    relativeOffset: segment.startTime,
                    speakerLabel: speakerLabel,
                    text: segment.text,
                    lowConfidence: false
                )
            }

            transcriptSegments.append(contentsOf: mappedSegments)
        }

        let sortedSegments = transcriptSegments.sorted { lhs, rhs in
            lhs.relativeOffset < rhs.relativeOffset
        }

        if sortedSegments.isEmpty {
            throw AppError.transcriptionExecutionFailed("whisper.cpp ran, but produced no transcript segments for the selected audio sources.")
        }

        let speakersDetected = Set(sortedSegments.map(\.speakerLabel)).count
        return (sortedSegments, max(speakersDetected, 1), engineDescription)
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
