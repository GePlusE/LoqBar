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

    func ensurePermissions(for diagnosticKind: DiagnosticCaptureKind) async -> PermissionState {
        let microphoneAuthorized: Bool
        let screenCaptureAuthorized: Bool

        switch diagnosticKind {
        case .microphoneOnly:
            microphoneAuthorized = await requestMicrophoneAccessIfNeeded()
            screenCaptureAuthorized = screenCaptureAccessGranted()
        case .systemAudioOnly:
            microphoneAuthorized = currentState().microphoneAuthorized
            screenCaptureAuthorized = requestScreenCaptureAccessIfNeeded()
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

    func resetScreenCapturePermission() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")

        let bundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = (bundleIdentifier?.isEmpty == false) ? bundleIdentifier! : "com.loqbar.app"
        process.arguments = ["reset", "ScreenCapture", identifier]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppError.permissionRepairFailed(
                stderrText.isEmpty
                ? "LoqBar could not reset the ScreenCapture permission state."
                : "LoqBar could not reset the ScreenCapture permission state: \(stderrText)"
            )
        }
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
