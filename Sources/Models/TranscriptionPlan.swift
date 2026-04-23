import Foundation

struct TranscriptionPlan {
    let sessionID: UUID
    let title: String
    let captureMode: CaptureMode
    let audioSourceType: AudioSourceType
    let microphoneFileURL: URL?
    let systemAudioFileURL: URL?
    let preferredSources: [PreferredTranscriptSource]
    let notes: [String]
}

enum PreferredTranscriptSource: String {
    case microphone
    case systemAudio
}
