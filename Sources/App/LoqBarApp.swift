import SwiftUI
import Darwin

@main
struct LoqBarApp: App {
    @NSApplicationDelegateAdaptor(LoqBarAppDelegate.self) private var appDelegate
    private let singleInstanceGuard = SingleInstanceGuard()
    @StateObject private var appModel: AppModel

    init() {
        let model = AppModel()
        _appModel = StateObject(wrappedValue: model)
        appDelegate.installIfNeeded(appModel: model)
    }

    var body: some Scene {
        Window("LoqBar Settings", id: "settings") {
            SettingsView()
                .environmentObject(appModel)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 980, height: 680)

        Window("Recent Sessions", id: "history") {
            SessionHistoryView()
                .environmentObject(appModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 720, height: 480)
    }
}

final class LoqBarAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    func installIfNeeded(appModel: AppModel) {
        if statusBarController == nil {
            statusBarController = StatusBarController(appModel: appModel)
        }
        statusBarController?.updateIcon()
    }
}

final class SingleInstanceGuard {
    private var lockFileDescriptor: Int32 = -1

    init() {
        let lockURL = StoragePaths.appSupportFolder.appendingPathComponent("loqbar.lock")

        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        lockFileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFileDescriptor != -1 else { return }

        let lockResult = flock(lockFileDescriptor, LOCK_EX | LOCK_NB)
        guard lockResult == 0 else {
            close(lockFileDescriptor)
            lockFileDescriptor = -1
            exit(0)
        }
    }

    deinit {
        guard lockFileDescriptor != -1 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
    }
}
