import AppKit
import Combine
import Foundation

@MainActor
extension AppModel {
    func loadInitialState() {
        settings = sessionStore.loadSettings()
        sessions = sessionStore.loadSessions()
        let currentVersion = currentAppVersionDisplay
        let previousVersion = settings.lastLaunchedAppVersion
        recentlyUpdatedToVersion = previousVersion != nil && previousVersion != currentVersion ? currentVersion : nil
        settings.lastLaunchedAppVersion = currentVersion
        permissionState = permissionsService.currentState()
        firstRunState = FirstRunState(
            needsOnboarding: !settings.firstRunCompleted,
            launchAtLogin: settings.launchAtLoginEnabled
        )
        managedTranscriptionInstallStatus = transcriptionSetupStatus.message
        sessionStore.save(settings: settings)
        showPostUpdatePermissionRepairHintIfNeeded()
        runRetentionCleanupIfNeeded()
    }

    func refreshPermissions() {
        permissionState = permissionsService.currentState()
        showPostUpdatePermissionRepairHintIfNeeded()
    }

    func resetScreenCapturePermission() {
        do {
            try permissionsService.resetScreenCapturePermission()
            permissionState = permissionsService.currentState()
            alertContext = AlertContext(
                title: "Screen Permission Reset",
                message: """
                LoqBar reset macOS screen capture permission state.

                If macOS prompts again, allow Screen & System Audio Recording for LoqBar. If Remote mode still looks unavailable, quit and reopen LoqBar once.
                """
            )
        } catch let error as AppError {
            present(error: error)
        } catch {
            present(error: .permissionRepairFailed("LoqBar could not reset screen capture permission state: \(error.localizedDescription)"))
        }
    }

    func completeFirstRun() {
        settings.firstRunCompleted = true
        settings.launchAtLoginEnabled = firstRunState.launchAtLogin

        do {
            try loginItemService.setEnabled(firstRunState.launchAtLogin)
            sessionStore.save(settings: settings)
            firstRunState.needsOnboarding = false
            refreshPermissions()
        } catch {
            present(error: .loginItemUpdateFailed(error.localizedDescription))
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLoginEnabled = enabled

        do {
            try loginItemService.setEnabled(enabled)
            sessionStore.save(settings: settings)
        } catch {
            present(error: .loginItemUpdateFailed(error.localizedDescription))
        }
    }

    func handleUpdateCheckResult(_ result: UpdateCheckResult) {
        let now = Date()

        switch result {
        case let .updateAvailable(release):
            updateStatus = .updateAvailable(version: release.version.displayString, checkedAt: now)

            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = [
                "LoqBar \(release.version.displayString) is available.",
                release.notes?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220).description
            ]
            .compactMap { value in
                guard let value else { return nil }
                return value.isEmpty ? nil : value
            }
            .joined(separator: "\n\n")
            alert.addButton(withTitle: release.primaryActionURL == nil ? "OK" : "Open Release")
            if release.primaryActionURL != nil {
                alert.addButton(withTitle: "Later")
            }

            prepareToPresentAuxiliaryWindow()
            let response = alert.runModal()
            if response == .alertFirstButtonReturn, let url = release.primaryActionURL {
                NSWorkspace.shared.open(url)
            }

        case .upToDate:
            updateStatus = .upToDate(checkedAt: now)
            presentInformationalAlert(
                title: "LoqBar Is Up to Date",
                message: "You already have the latest available release for this build channel."
            )

        case .notConfigured:
            updateStatus = .notConfigured
            presentInformationalAlert(
                title: "Updates Not Configured",
                message: """
                This build does not include a release feed yet. Add a GitHub Releases API URL or release manifest URL during packaging to enable manual update checks.

                Current build: \(currentAppVersionDisplay)
                """
            )

        case let .failed(message):
            updateStatus = .failed(message: message)
            presentInformationalAlert(
                title: "Update Check Failed",
                message: message
            )
        }
    }

    func observeWorkspaceLifecycle() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.handleWorkspaceWillSleep()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleWorkspaceDidWake()
            }
            .store(in: &cancellables)
    }

    func handleWorkspaceWillSleep() {
        guard activeSession != nil || recordingCoordinator.hasActiveCapture else { return }
        stopRecording(interruptionNote: "Recording stopped because the Mac is going to sleep.")
    }

    func handleWorkspaceDidWake() {
        refreshPermissions()
        processingMessage = activeSession == nil && !hasProcessingSessions ? "Ready" : processingMessage
    }

    func showPostUpdatePermissionRepairHintIfNeeded() {
        guard
            let updatedVersion = recentlyUpdatedToVersion,
            !hasShownPostUpdatePermissionHint,
            settings.firstRunCompleted,
            !permissionState.screenCaptureAuthorized
        else {
            if permissionState.screenCaptureAuthorized {
                recentlyUpdatedToVersion = nil
            }
            return
        }

        hasShownPostUpdatePermissionHint = true
        alertContext = AlertContext(
            title: "Check Screen Permission After Update",
            message: """
            LoqBar was updated to \(updatedVersion). After manually replacing a Mac app, macOS can sometimes keep stale Screen Recording permission state.

            If Remote mode looks unavailable even though System Settings shows LoqBar enabled, open Preferences > General and use Reset Screen Permission. Then allow the prompt again and relaunch LoqBar once if needed.
            """
        )
    }

    private func presentInformationalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        prepareToPresentAuxiliaryWindow()
        alert.runModal()
    }
}
