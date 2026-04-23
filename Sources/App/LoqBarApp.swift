import SwiftUI

@main
struct LoqBarApp: App {
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
