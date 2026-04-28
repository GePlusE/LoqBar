import AppKit
import Foundation

@MainActor
extension AppModel {
    func openPermissionsSettings() {
        permissionsService.openRelevantSettings()
    }

    func openTranscriptFolder() {
        sessionStore.openTranscriptFolder(settings: settings)
    }

    func openRecordingRootFolder() {
        sessionStore.openRecordingRootFolder(settings: settings)
    }

    func openLatestRecordingFolder() {
        guard let session = latestSession else { return }
        sessionStore.openRecordingFolder(for: session)
    }

    func revealLatestMicrophoneRecording() {
        guard let path = latestSession?.audioPath else { return }
        sessionStore.revealFile(at: path)
    }

    func revealLatestSystemAudioRecording() {
        guard let path = latestSession?.systemAudioPath else { return }
        sessionStore.revealFile(at: path)
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func prepareToPresentAuxiliaryWindow() {
        _ = NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringAuxiliaryWindowToFront(titleContains titleFragment: String, remainingAttempts: Int = 8) {
        prepareToPresentAuxiliaryWindow()

        let matchingWindow = NSApp.windows.first { window in
            window.title.localizedCaseInsensitiveContains(titleFragment)
        }

        if let matchingWindow {
            matchingWindow.collectionBehavior.insert(.moveToActiveSpace)
            matchingWindow.level = .normal
            matchingWindow.orderFrontRegardless()
            matchingWindow.makeKeyAndOrderFront(nil)
            matchingWindow.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard remainingAttempts > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.bringAuxiliaryWindowToFront(
                titleContains: titleFragment,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    func restoreMenuBarPresentationIfPossible() {
        let auxiliaryWindowsAreVisible = NSApp.windows.contains { window in
            (window.title.localizedCaseInsensitiveContains("Settings") ||
             window.title.localizedCaseInsensitiveContains("Recent Sessions")) &&
            window.isVisible
        }

        guard !auxiliaryWindowsAreVisible else { return }

        _ = NSApp.setActivationPolicy(.accessory)
    }

    func chooseStorageRootFolder() {
        prepareToPresentAuxiliaryWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose the root folder where LoqBar should store recordings, transcripts, and managed files."
        panel.directoryURL = URL(fileURLWithPath: settings.storageRootFolder, isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            settings.storageRootFolder = url.path
        }
    }

    func createStorageRootFolder() {
        prepareToPresentAuxiliaryWindow()

        let currentRoot = URL(fileURLWithPath: settings.storageRootFolder, isDirectory: true)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Create Folder"
        panel.title = "Create Storage Root Folder"
        panel.message = "Create a new root folder for LoqBar recordings, transcripts, and managed files."
        panel.nameFieldLabel = "Folder name:"
        panel.nameFieldStringValue = currentRoot.lastPathComponent.isEmpty ? "LoqBar" : currentRoot.lastPathComponent
        panel.directoryURL = currentRoot.deletingLastPathComponent()
        panel.isExtensionHidden = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            settings.storageRootFolder = url.path
        } catch {
            present(error: .storageSetupFailed("LoqBar could not create the selected storage folder: \(error.localizedDescription)"))
        }
    }

    func chooseExternalWhisperExecutable() {
        prepareToPresentAuxiliaryWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Executable"
        let startingPath = settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.directoryURL = URL(fileURLWithPath: startingPath.isEmpty ? StoragePaths.appSupportFolder.path : startingPath)

        if panel.runModal() == .OK, let url = panel.url {
            settings.transcriptionExecutablePath = url.path
        }
    }

    func chooseExternalModelFile() {
        prepareToPresentAuxiliaryWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Model File"
        let startingPath = settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.directoryURL = URL(fileURLWithPath: startingPath.isEmpty ? settings.storageRootFolder : startingPath)

        if panel.runModal() == .OK, let url = panel.url {
            settings.transcriptionModelPath = url.path
        }
    }
}
