import SwiftUI
import Darwin

@main
struct LoqBarApp: App {
    private let singleInstanceGuard = SingleInstanceGuard()
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appModel)
        } label: {
            Label("LoqBar", systemImage: appModel.menuBarIconName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .frame(minWidth: 560, minHeight: 420)
        }

        Window("Recent Sessions", id: "history") {
            SessionHistoryView()
                .environmentObject(appModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 720, height: 480)
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
