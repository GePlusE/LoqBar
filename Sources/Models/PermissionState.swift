import Foundation

struct PermissionState {
    var microphoneAuthorized: Bool
    var screenCaptureAuthorized: Bool

    static let unknown = PermissionState(
        microphoneAuthorized: false,
        screenCaptureAuthorized: false
    )
}

struct FirstRunState {
    var needsOnboarding = true
    var launchAtLogin = false
}
