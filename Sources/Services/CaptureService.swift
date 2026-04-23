import Foundation

struct CapturePlan {
    let mode: CaptureMode
    let audioSource: AudioSourceType
    let isAvailable: Bool
    let unavailableReason: AppError?
    let userFacingSummary: String
}

struct CaptureService {
    func planCapture(requestedMode: CaptureMode, permissionState: PermissionState) -> CapturePlan {
        guard permissionState.microphoneAuthorized else {
            return CapturePlan(
                mode: requestedMode,
                audioSource: .unknown,
                isAvailable: false,
                unavailableReason: .microphonePermissionMissing,
                userFacingSummary: "Microphone permission is missing."
            )
        }

        switch requestedMode {
        case .localMeeting:
            return CapturePlan(
                mode: .localMeeting,
                audioSource: .microphoneOnly,
                isAvailable: true,
                unavailableReason: nil,
                userFacingSummary: "Local meeting capture planned with microphone input."
            )
        case .call:
            guard permissionState.screenCaptureAuthorized else {
                return CapturePlan(
                    mode: .call,
                    audioSource: .unknown,
                    isAvailable: false,
                    unavailableReason: .screenRecordingPermissionMissing,
                    userFacingSummary: "Screen Recording permission is required for call capture."
                )
            }

            return CapturePlan(
                mode: .call,
                audioSource: .appAudioPlusMicrophone,
                isAvailable: true,
                unavailableReason: nil,
                userFacingSummary: "Call Mode will attempt ScreenCaptureKit system audio plus microphone recording."
            )
        case .auto:
            if permissionState.screenCaptureAuthorized {
                return CapturePlan(
                    mode: .call,
                    audioSource: .appAudioPlusMicrophone,
                    isAvailable: true,
                    unavailableReason: nil,
                    userFacingSummary: "Auto selected Call Mode and will attempt ScreenCaptureKit system audio capture."
                )
            }

            return CapturePlan(
                mode: .localMeeting,
                audioSource: .microphoneOnly,
                isAvailable: true,
                unavailableReason: nil,
                userFacingSummary: "Auto selected Local Meeting Mode because call capture is not available."
            )
        }
    }

    func planDiagnosticCapture(kind: DiagnosticCaptureKind, permissionState: PermissionState) -> CapturePlan {
        switch kind {
        case .microphoneOnly:
            guard permissionState.microphoneAuthorized else {
                return CapturePlan(
                    mode: .localMeeting,
                    audioSource: .unknown,
                    isAvailable: false,
                    unavailableReason: .microphonePermissionMissing,
                    userFacingSummary: "Microphone permission is required for the microphone-only test."
                )
            }

            return CapturePlan(
                mode: .localMeeting,
                audioSource: .microphoneOnly,
                isAvailable: true,
                unavailableReason: nil,
                userFacingSummary: "Diagnostic microphone-only recording active."
            )

        case .systemAudioOnly:
            guard permissionState.screenCaptureAuthorized else {
                return CapturePlan(
                    mode: .call,
                    audioSource: .unknown,
                    isAvailable: false,
                    unavailableReason: .screenRecordingPermissionMissing,
                    userFacingSummary: "Screen Recording permission is required for the system-audio-only test."
                )
            }

            return CapturePlan(
                mode: .call,
                audioSource: .systemAudioOnly,
                isAvailable: true,
                unavailableReason: nil,
                userFacingSummary: "Diagnostic system-audio-only recording active."
            )
        }
    }
}
