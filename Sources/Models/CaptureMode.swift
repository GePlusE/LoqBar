import Foundation

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case localMeeting
    case call

    var id: Self { self }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .localMeeting:
            return "Local Meeting Mode"
        case .call:
            return "Call Mode"
        }
    }
}

enum AudioSourceType: String, Codable {
    case microphoneOnly
    case appAudioPlusMicrophone
    case separatedSystemAndMicrophone
    case unknown

    var title: String {
        switch self {
        case .microphoneOnly:
            return "Microphone only"
        case .appAudioPlusMicrophone:
            return "App audio + microphone"
        case .separatedSystemAndMicrophone:
            return "Separated system + microphone"
        case .unknown:
            return "Unknown"
        }
    }
}
