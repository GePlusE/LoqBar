import Foundation

struct TranscriptionService {
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

    func transcribe(plan: TranscriptionPlan, session: SessionRecord) -> TranscriptContent {
        let start = session.startedAt
        let summary = summaryText(for: plan)
        let analysis = TranscriptionAnalysis(
            primarySources: plan.preferredSources.map(\.rawValue),
            notes: plan.notes
        )

        let segments = buildPlaceholderSegments(for: plan, start: start)
        return TranscriptContent(
            title: session.title,
            segments: segments,
            speakersDetected: inferredSpeakerCount(for: plan),
            warningCount: segments.filter(\.lowConfidence).count,
            summary: summary,
            analysis: analysis
        )
    }

    private func buildPlaceholderSegments(for plan: TranscriptionPlan, start: Date) -> [TranscriptSegment] {
        switch plan.audioSourceType {
        case .systemAudioOnly:
            return [
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(2),
                    relativeOffset: 2,
                    speakerLabel: "Speaker1",
                    text: "Placeholder transcript for the system-audio-only diagnostic recording.",
                    lowConfidence: false
                ),
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(7),
                    relativeOffset: 7,
                    speakerLabel: "Speaker1",
                    text: "The next step is to send this source through whisper.cpp and verify it maps cleanly to the remote participant track.",
                    lowConfidence: true
                ),
            ]

        case .microphoneOnly:
            return [
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(2),
                    relativeOffset: 2,
                    speakerLabel: "Speaker1",
                    text: "Placeholder transcript for the microphone-only diagnostic recording.",
                    lowConfidence: false
                ),
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(6),
                    relativeOffset: 6,
                    speakerLabel: "Speaker1",
                    text: "This path should represent the local speaker when call playback is isolated away from the microphone.",
                    lowConfidence: true
                ),
            ]

        case .appAudioPlusMicrophone, .separatedSystemAndMicrophone:
            return [
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(3),
                    relativeOffset: 3,
                    speakerLabel: "Speaker1",
                    text: "Placeholder transcript for the remote-participant system-audio source.",
                    lowConfidence: false
                ),
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(9),
                    relativeOffset: 9,
                    speakerLabel: "Speaker2",
                    text: "Placeholder transcript for the local-speaker microphone source.",
                    lowConfidence: false
                ),
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(15),
                    relativeOffset: 15,
                    speakerLabel: "Speaker1",
                    text: "Whisper.cpp integration should transcribe these sources separately before any diarization or merge step.",
                    lowConfidence: true
                ),
            ]

        case .unknown:
            return [
                TranscriptSegment(
                    absoluteTimestamp: start.addingTimeInterval(2),
                    relativeOffset: 2,
                    speakerLabel: "Speaker1",
                    text: "Placeholder transcript for the available local source.",
                    lowConfidence: true
                ),
            ]
        }
    }

    private func inferredSpeakerCount(for plan: TranscriptionPlan) -> Int {
        switch plan.audioSourceType {
        case .appAudioPlusMicrophone, .separatedSystemAndMicrophone:
            return 2
        default:
            return 1
        }
    }

    private func summaryText(for plan: TranscriptionPlan) -> String {
        switch plan.audioSourceType {
        case .systemAudioOnly:
            return "Diagnostic system-audio-only export complete. The source-selection pipeline is ready for whisper.cpp integration."
        case .microphoneOnly:
            return "Diagnostic microphone-only export complete. The source-selection pipeline is ready for whisper.cpp integration."
        case .appAudioPlusMicrophone, .separatedSystemAndMicrophone:
            return "Split-source export complete. LoqBar now plans remote transcription from system audio and local transcription from the microphone track."
        case .unknown:
            return "Fallback export complete. A real transcription engine still needs to be attached."
        }
    }
}
