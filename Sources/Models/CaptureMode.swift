import Foundation

enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case localMeeting
    case call

    var id: Self { self }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .localMeeting:
            return "Local"
        case .call:
            return "Remote"
        }
    }
}

enum AudioSourceType: String, Codable, Sendable {
    case microphoneOnly
    case systemAudioOnly
    case appAudioPlusMicrophone
    case separatedSystemAndMicrophone
    case unknown

    var title: String {
        switch self {
        case .microphoneOnly:
            return "Microphone only"
        case .systemAudioOnly:
            return "System audio only"
        case .appAudioPlusMicrophone:
            return "App audio + microphone"
        case .separatedSystemAndMicrophone:
            return "Separated system + microphone"
        case .unknown:
            return "Unknown"
        }
    }
}

enum DiagnosticCaptureKind: String, Codable, Identifiable, Sendable {
    case microphoneOnly
    case systemAudioOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .microphoneOnly:
            return "Microphone Only Test"
        case .systemAudioOnly:
            return "System Audio Only Test"
        }
    }

    var audioSourceType: AudioSourceType {
        switch self {
        case .microphoneOnly:
            return .microphoneOnly
        case .systemAudioOnly:
            return .systemAudioOnly
        }
    }
}
