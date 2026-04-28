import Foundation

enum AppError: Error, Sendable {
    case microphonePermissionMissing
    case screenRecordingPermissionMissing
    case callAudioCaptureUnavailable
    case recordingStartupFailed(String)
    case recordingStopFailed(String)
    case transcriptionConfigurationMissing(String)
    case transcriptionExecutionFailed(String)
    case loginItemUpdateFailed(String)
    case permissionRepairFailed(String)
    case transcriptExportFailed(String)
    case storageSetupFailed(String)
    case sessionDeletionFailed(String)

    var title: String {
        switch self {
        case .microphonePermissionMissing:
            return "Microphone Permission Needed"
        case .screenRecordingPermissionMissing:
            return "Screen Recording Permission Needed"
        case .callAudioCaptureUnavailable:
            return "Call Capture Unavailable"
        case .recordingStartupFailed:
            return "Recording Could Not Start"
        case .recordingStopFailed:
            return "Recording Could Not Stop Cleanly"
        case .transcriptionConfigurationMissing:
            return "Transcription Needs Setup"
        case .transcriptionExecutionFailed:
            return "Transcription Could Not Run"
        case .loginItemUpdateFailed:
            return "Launch at Login Could Not Be Updated"
        case .permissionRepairFailed:
            return "Permission Repair Failed"
        case .transcriptExportFailed:
            return "Transcript Export Failed"
        case .storageSetupFailed:
            return "Storage Setup Failed"
        case .sessionDeletionFailed:
            return "Session Could Not Be Deleted"
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
        case let .recordingStartupFailed(details):
            return details
        case let .recordingStopFailed(details):
            return details
        case let .transcriptionConfigurationMissing(details):
            return details
        case let .transcriptionExecutionFailed(details):
            return details
        case let .loginItemUpdateFailed(details):
            return details
        case let .permissionRepairFailed(details):
            return details
        case let .transcriptExportFailed(details):
            return details
        case let .storageSetupFailed(details):
            return details
        case let .sessionDeletionFailed(details):
            return details
        }
    }
}

extension AppError: LocalizedError {
    var errorDescription: String? {
        recoverySuggestion
    }
}

struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
