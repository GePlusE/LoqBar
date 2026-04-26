import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let appModel: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(appModel: AppModel) {
        self.appModel = appModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        observeAppModel()
        startEventMonitor()
        updateIcon()
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: appModel.menuBarIconName, accessibilityDescription: "LoqBar")
        button.image?.isTemplate = true
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 320)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appModel)
        )
    }

    private func observeAppModel() {
        appModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfNeeded()
            }
        }
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        switch event.type {
        case .rightMouseUp:
            closePopoverIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.appModel.toggleRecordingFromStatusItem()
            }
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopoverIfNeeded()
            return
        }

        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopoverIfNeeded() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}
