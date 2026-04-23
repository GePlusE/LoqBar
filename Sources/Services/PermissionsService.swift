import AVFoundation
import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

import AppKit

struct PermissionsService {
    func currentState() -> PermissionState {
        PermissionState(
            microphoneAuthorized: AVAudioApplication.shared.recordPermission == .granted,
            screenCaptureAuthorized: screenCaptureAccessGranted()
        )
    }

    func ensurePermissions(for mode: CaptureMode) async -> PermissionState {
        let microphoneAuthorized = await requestMicrophoneAccessIfNeeded()
        let screenCaptureAuthorized: Bool

        switch mode {
        case .call:
            screenCaptureAuthorized = requestScreenCaptureAccessIfNeeded()
        case .auto:
            screenCaptureAuthorized = screenCaptureAccessGranted() || requestScreenCaptureAccessIfNeeded()
        case .localMeeting:
            screenCaptureAuthorized = screenCaptureAccessGranted()
        }

        return PermissionState(
            microphoneAuthorized: microphoneAuthorized,
            screenCaptureAuthorized: screenCaptureAuthorized
        )
    }

    func openRelevantSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func screenCaptureAccessGranted() -> Bool {
        #if canImport(ScreenCaptureKit)
        return CGPreflightScreenCaptureAccess()
        #else
        return false
        #endif
    }

    private func requestScreenCaptureAccessIfNeeded() -> Bool {
        #if canImport(ScreenCaptureKit)
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
        #else
        return false
        #endif
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }
}
