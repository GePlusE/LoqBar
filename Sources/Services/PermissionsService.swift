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
}
