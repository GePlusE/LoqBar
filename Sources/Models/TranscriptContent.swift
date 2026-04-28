import Foundation

struct TranscriptContent: Sendable {
    let title: String
    let language: String
    let segments: [TranscriptSegment]
    let speakersDetected: Int
    let warningCount: Int
    let summary: String
    let analysis: TranscriptionAnalysis
}

struct TranscriptSegment: Sendable {
    let absoluteTimestamp: Date
    let relativeOffset: TimeInterval
    let speakerLabel: String
    let source: String
    let text: String
    let lowConfidence: Bool
}

struct TranscriptionAnalysis: Sendable {
    let primarySources: [String]
    let notes: [String]
    let engineDescription: String
}
