import Foundation

struct TranscriptContent {
    let title: String
    let segments: [TranscriptSegment]
    let speakersDetected: Int
    let warningCount: Int
    let summary: String
    let analysis: TranscriptionAnalysis
}

struct TranscriptSegment {
    let absoluteTimestamp: Date
    let relativeOffset: TimeInterval
    let speakerLabel: String
    let text: String
    let lowConfidence: Bool
}

struct TranscriptionAnalysis {
    let primarySources: [String]
    let notes: [String]
    let engineDescription: String
}
