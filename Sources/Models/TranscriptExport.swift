import Foundation

struct TranscriptExport: Sendable {
    let path: String
    let warningCount: Int
    let speakersDetected: Int
    let summary: String
    let planNotes: [String]
}
