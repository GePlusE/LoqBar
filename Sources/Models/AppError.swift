import Foundation

enum AppError: Error {
    case microphonePermissionMissing
    case screenRecordingPermissionMissing
    case callAudioCaptureUnavailable
    case loginItemUpdateFailed(String)
    case transcriptExportFailed(String)
    case storageSetupFailed(String)

    var title: String {
        switch self {
        case .microphonePermissionMissing:
            return "Microphone Permission Needed"
        case .screenRecordingPermissionMissing:
            return "Screen Recording Permission Needed"
        case .callAudioCaptureUnavailable:
            return "Call Capture Unavailable"
        case .loginItemUpdateFailed:
            return "Launch at Login Could Not Be Updated"
        case .transcriptExportFailed:
            return "Transcript Export Failed"
        case .storageSetupFailed:
            return "Storage Setup Failed"
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .microphonePermissionMissing:
            return "Enable microphone access in System Settings so LoqBar can capture local meeting audio."
        case .screenRecordingPermissionMissing:
            return "Enable Screen Recording so LoqBar can attempt app or system audio capture for calls."
        case .callAudioCaptureUnavailable:
            return "Teams or system audio capture is not available yet. Use Local Meeting Mode as a fallback while the call-capture spike is implemented."
        case let .loginItemUpdateFailed(details):
            return details
        case let .transcriptExportFailed(details):
            return details
        case let .storageSetupFailed(details):
            return details
        }
    }
}

struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
