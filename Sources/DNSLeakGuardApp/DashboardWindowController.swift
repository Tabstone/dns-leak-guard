import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()

    private var window: NSWindow?
    private weak var model: AppModel?

    func show(model: AppModel) {
        self.model = model
        if window == nil {
            let root = DashboardView()
                .environmentObject(model)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "DNS Leak Guard"
            window.styleMask = [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 1_040, height: 700)
            window.setContentSize(NSSize(width: 1_180, height: 820))
            window.collectionBehavior = [.fullScreenPrimary]
            window.tabbingMode = .disallowed
            window.delegate = self
            window.center()
            self.window = window
        }
        if window?.isVisible != true {
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.setDashboardVisible(true)
        model.refreshLaunchAtLoginStatus()
        model.refreshMemoryFootprint()
    }

    func windowWillClose(_ notification: Notification) {
        model?.setDashboardVisible(false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model?.setDashboardVisible(true)
        model?.refreshMemoryFootprint()
    }
}
