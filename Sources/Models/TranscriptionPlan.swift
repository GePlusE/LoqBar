import Foundation

struct TranscriptionPlan: Sendable {
    let sessionID: UUID
    let title: String
    let captureMode: CaptureMode
    let audioSourceType: AudioSourceType
    let microphoneFileURL: URL?
    let systemAudioFileURL: URL?
    let preferredSources: [PreferredTranscriptSource]
    let notes: [String]
}

enum PreferredTranscriptSource: String, Sendable {
    case microphone
    case systemAudio
}
