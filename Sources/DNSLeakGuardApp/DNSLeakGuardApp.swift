import AppKit
import Carbon
import Combine
import DNSLeakCore
import OSLog
import SwiftUI

@main
@MainActor
enum DNSLeakGuardMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel.shared
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var cachedSymbol: String?
    private var cachedToolTip: String?
    private var hasFinishedLaunching = false
    private var pendingDeepLinkURL: URL?
    private var lastDeepLink: (url: String, date: Date)?
    private let deepLinkLogger = Logger(
        subsystem: "io.dnsleakguard.app",
        category: "DeepLink"
    )

    override init() {
        super.init()
        deepLinkLogger.debug("Installing URL handler during delegate init")
        installDeepLinkHandler()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        deepLinkLogger.debug("Application will finish launching")
        installDeepLinkHandler()
        captureCurrentAppleEventURL()
    }

    private func installDeepLinkHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        deepLinkLogger.debug("Application did finish launching")
        hasFinishedLaunching = true
        captureCurrentAppleEventURL()
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        configureStatusItem()
        configurePopover()
        observeModel()

        if let pendingDeepLinkURL {
            self.pendingDeepLinkURL = nil
            lastDeepLink = nil
            handleIncomingDeepLink(pendingDeepLinkURL)
        } else if !UserDefaults.standard.bool(forKey: "app.didShowDashboard") {
            UserDefaults.standard.set(true, forKey: "app.didShowDashboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.showDashboard()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showDashboard()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        deepLinkLogger.debug("Received \(urls.count) URL(s) from AppKit")
        for url in urls {
            handleIncomingDeepLink(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        changeStatusIcon(symbol: "shield.slash", toolTip: "DNS Leak Guard")
    }

    @objc
    private func handleURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(
            forKeyword: AEKeyword(keyDirectObject)
        )?.stringValue,
        let url = URL(string: value) else {
            NSSound.beep()
            return
        }
        handleIncomingDeepLink(url)
    }

    private func captureCurrentAppleEventURL() {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kInternetEventClass),
              event.eventID == AEEventID(kAEGetURL),
              let value = event.paramDescriptor(
                forKeyword: AEKeyword(keyDirectObject)
              )?.stringValue,
              let url = URL(string: value) else {
            deepLinkLogger.debug("No pending GetURL Apple Event")
            return
        }
        deepLinkLogger.debug("Captured pending GetURL Apple Event")
        handleIncomingDeepLink(url)
    }

    private func handleIncomingDeepLink(_ url: URL) {
        guard let link = DNSLeakGuardDeepLink.parse(url) else {
            deepLinkLogger.error(
                "Rejected deep link: \(url.absoluteString, privacy: .public)"
            )
            NSSound.beep()
            return
        }

        let now = Date()
        if let lastDeepLink,
           lastDeepLink.url == url.absoluteString,
           now.timeIntervalSince(lastDeepLink.date) < 1 {
            deepLinkLogger.debug("Ignored duplicate deep link")
            return
        }
        lastDeepLink = (url.absoluteString, now)

        guard hasFinishedLaunching else {
            deepLinkLogger.debug("Queued deep link until launch completes")
            pendingDeepLinkURL = url
            return
        }

        deepLinkLogger.notice(
            "Accepted deep link: \(url.absoluteString, privacy: .public)"
        )
        showDashboard()
        model.handleDeepLink(link)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        statusItem = item
        updateStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 366, height: 516)
        popover.delegate = self
        let root = MenuPanelView(
            model: model,
            openDashboard: { [weak self] in
                self?.showDashboard()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: root)
    }

    private func observeModel() {
        model.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(90), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }

    @objc
    private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.refreshMemoryFootprint()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        popover.performClose(nil)
        let menu = NSMenu()

        let status = NSMenuItem(
            title: "DNS Leak Guard · \(model.protectionState.label)",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(
            menuItem(
                "立即检测并在线复验",
                action: #selector(detectNow),
                symbol: "arrow.clockwise"
            )
        )
        menu.addItem(
            menuItem(
                "应用已勾选修复",
                action: #selector(repairNow),
                symbol: "wrench.and.screwdriver"
            )
        )
        menu.addItem(.separator())

        let enabled = menuItem(
            "启用实时守护",
            action: #selector(toggleProtection),
            symbol: "shield.lefthalf.filled"
        )
        enabled.state = model.protectionEnabled ? .on : .off
        menu.addItem(enabled)

        let notifyOnly = menuItem(
            "保护模式：仅监测",
            action: #selector(useNotifyMode),
            symbol: nil
        )
        notifyOnly.state = model.protectionMode == .notifyOnly ? .on : .off
        notifyOnly.isEnabled = model.protectionEnabled
        menu.addItem(notifyOnly)

        let autoRepair = menuItem(
            "保护模式：自动修复",
            action: #selector(useAutoRepairMode),
            symbol: nil
        )
        autoRepair.state = model.protectionMode == .autoRepair ? .on : .off
        autoRepair.isEnabled = model.protectionEnabled
        menu.addItem(autoRepair)

        if model.isProtectionPaused {
            menu.addItem(
                menuItem(
                    "恢复实时守护",
                    action: #selector(resumeProtection),
                    symbol: "play.fill"
                )
            )
        } else {
            menu.addItem(
                menuItem(
                    "暂停 15 分钟",
                    action: #selector(pauseFifteenMinutes),
                    symbol: "pause.fill"
                )
            )
            menu.addItem(
                menuItem(
                    "暂停 1 小时",
                    action: #selector(pauseOneHour),
                    symbol: "pause.fill"
                )
            )
        }
        menu.addItem(.separator())

        let login = menuItem(
            "登录时启动",
            action: #selector(toggleLaunchAtLogin),
            symbol: "power"
        )
        login.state = model.launchAtLoginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(
            menuItem(
                "打开 BrowserLeaks DNS 测试",
                action: #selector(openBrowserLeaks),
                symbol: "safari"
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                "打开控制台",
                action: #selector(openDashboardFromMenu),
                symbol: "macwindow"
            )
        )
        menu.addItem(
            menuItem(
                "退出 DNS Leak Guard",
                action: #selector(quitApplication),
                symbol: "xmark.circle"
            )
        )

        menu.items.forEach { $0.target = self }
        if let button = statusItem?.button {
            statusItem?.menu = menu
            button.performClick(nil)
            statusItem?.menu = nil
        }
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        symbol: String?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func updateStatusItem() {
        let symbol: String
        let statusText: String
        if model.protectionEnabled {
            symbol = model.protectionIconName
            statusText = model.protectionState.label
        } else if model.riskCount > 0 {
            symbol = model.riskCount > 2 ? "exclamationmark.shield.fill" : "exclamationmark.shield"
            statusText = "\(model.riskCount) 项 DNS 风险"
        } else if model.analysis != nil {
            symbol = "checkmark.shield"
            statusText = "DNS 配置正常"
        } else {
            symbol = "shield"
            statusText = "等待检测"
        }
        let activity = model.isBusy ? " · \(model.activity.label)" : ""
        changeStatusIcon(
            symbol: symbol,
            toolTip: "DNS Leak Guard · \(statusText)\(activity)"
        )
    }

    private func changeStatusIcon(symbol: String, toolTip: String) {
        guard symbol != cachedSymbol || toolTip != cachedToolTip else { return }
        cachedSymbol = symbol
        cachedToolTip = toolTip
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "DNS Leak Guard"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.toolTip = toolTip
    }

    private func showDashboard() {
        popover.performClose(nil)
        DashboardWindowController.shared.show(model: model)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        appMenu.addItem(
            withTitle: "关于 DNS Leak Guard",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "隐藏 DNS Leak Guard",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(
            withTitle: "退出 DNS Leak Guard",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        appMenu.items.forEach { if $0.target == nil { $0.target = NSApp } }

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "全选",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "关闭",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        NSApp.mainMenu = mainMenu
    }

    @objc private func detectNow() {
        Task { await model.runDetection() }
    }

    @objc private func repairNow() {
        Task { await model.applySelectedOnly() }
    }

    @objc private func toggleProtection() {
        model.setProtectionEnabled(!model.protectionEnabled)
    }

    @objc private func useNotifyMode() {
        model.setProtectionMode(.notifyOnly)
    }

    @objc private func useAutoRepairMode() {
        model.setProtectionMode(.autoRepair)
    }

    @objc private func pauseFifteenMinutes() {
        model.pauseProtection(for: 15 * 60)
    }

    @objc private func pauseOneHour() {
        model.pauseProtection(for: 60 * 60)
    }

    @objc private func resumeProtection() {
        model.resumeProtectionNow()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLoginEnabled)
    }

    @objc private func openBrowserLeaks() {
        model.openBrowserLeaks()
    }

    @objc private func openDashboardFromMenu() {
        showDashboard()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
