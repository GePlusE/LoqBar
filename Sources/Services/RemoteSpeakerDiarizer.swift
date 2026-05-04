import Foundation

struct RemoteSpeakerTurn: Sendable, Hashable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let clusterID: String
}

protocol RemoteSpeakerDiarizing {
    func diarizeSystemAudio(audioFileURL: URL) throws -> [RemoteSpeakerTurn]
}

struct NoOpRemoteSpeakerDiarizer: RemoteSpeakerDiarizing {
    func diarizeSystemAudio(audioFileURL: URL) throws -> [RemoteSpeakerTurn] {
        []
    }
}
