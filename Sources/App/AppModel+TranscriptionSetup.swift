import AppKit
import Foundation

@MainActor
extension AppModel {
    func openManagedTranscriptionFolder() {
        let url = URL(fileURLWithPath: settings.managedTranscriptionRootFolder, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            present(error: .storageSetupFailed("LoqBar could not open the managed transcription folder: \(error.localizedDescription)"))
        }
    }

    func clearExternalTranscriptionPaths() {
        settings.transcriptionExecutablePath = ""
        settings.transcriptionModelPath = ""
        persist()
    }

    func runCleanupNow() {
        runRetentionCleanup(markRunTimestamp: true)
    }

    func checkForUpdates() {
        guard updateStatus != .checking else { return }

        updateStatus = .checking
        let currentVersion = AppVersion.current()
        let configuration = AppReleaseFeedConfiguration.fromMainBundle()

        Task {
            let result = await updateCheckService.checkForUpdates(
                currentVersion: currentVersion,
                configuration: configuration
            )

            await MainActor.run {
                handleUpdateCheckResult(result)
            }
        }
    }

    func installManagedTranscriptionFiles() {
        guard !isInstallingManagedTranscription else { return }

        isInstallingManagedTranscription = true
        managedTranscriptionInstallStatus = "Preparing managed transcription setup…"

        Task {
            do {
                let result = try await managedTranscriptionInstallService.install(
                    settings: settings
                ) { [weak self] progress in
                    await MainActor.run {
                        self?.managedTranscriptionInstallStatus = progress
                    }
                }

                await MainActor.run {
                    self.managedTranscriptionInstallStatus = """
                    Managed transcription is ready.
                    \(result.executableSourceDescription)
                    \(result.modelSourceDescription)
                    """
                    self.isInstallingManagedTranscription = false
                    self.persist()
                }
            } catch let error as AppError {
                await MainActor.run {
                    self.isInstallingManagedTranscription = false
                    self.managedTranscriptionInstallStatus = "Managed transcription setup failed."
                    self.present(error: error)
                }
            } catch {
                await MainActor.run {
                    self.isInstallingManagedTranscription = false
                    self.managedTranscriptionInstallStatus = "Managed transcription setup failed."
                    self.present(error: .storageSetupFailed("LoqBar could not install the managed transcription files: \(error.localizedDescription)"))
                }
            }
        }
    }
}
