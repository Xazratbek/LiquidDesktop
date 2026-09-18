import AppKit
import SwiftUI
import ServiceManagement
import Combine

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate, NSMenuDelegate {
    private let controller: LiquidController
    private let settings = Settings.shared
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var panelModel: PanelModel?
    private var contextMenu = NSMenu()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingModel: OnboardingModel?
    private var cancellables = Set<AnyCancellable>()

    var needsPermission = false {
        didSet {
            panelModel?.needsPermission = needsPermission
            refresh()
        }
    }

    init(controller: LiquidController) {
        self.controller = controller
        super.init()
        installStatusItem()
        hotKeys.arm { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleWater: self.controller.toggleWater()
            case .splash: self.controller.splash()
            case .nextTheme: self.controller.nextTheme()
            }
        }
        controller.$status.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        contextMenu.delegate = self
        statusItem = item

        let model = PanelModel(controller: controller)
        model.openSettings = { [weak self] in self?.popover.performClose(nil); self?.openSettings() }
        model.openPermission = { [weak self] in self?.popover.performClose(nil); self?.openOnboarding() }
        model.quit = { NSApp.terminate(nil) }
        panelModel = model
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuPanel(model: model))
        refresh()
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem?.menu = contextMenu
            button.performClick(nil)
            statusItem?.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            panelModel?.needsPermission = needsPermission
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refresh() {
        let symbol: String
        if needsPermission {
            symbol = "drop.triangle"
        } else {
            symbol = settings.waterVisible ? "drop.fill" : "drop"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Liquid Desktop")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item(settings.waterVisible ? "Drain Water" : "Fill Water",
                          #selector(toggleWater), key: "l", shortcut: true))
        menu.addItem(item("Make a Splash", #selector(splash), key: "k", shortcut: true))

        let liquids = NSMenu()
        for theme in LiquidTheme.all {
            let entry = item(theme.name, #selector(selectTheme(_:)))
            entry.representedObject = theme.id
            entry.state = theme.id == settings.themeID ? .on : .off
            liquids.addItem(entry)
        }
        liquids.addItem(.separator())
        liquids.addItem(item("Next Liquid", #selector(nextTheme), key: "t", shortcut: true))
        let liquidItem = NSMenuItem(title: "Liquid", action: nil, keyEquivalent: "")
        liquidItem.submenu = liquids
        menu.addItem(liquidItem)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        let permission = item(needsPermission ? "Allow Screen Recording…" : "Screen Recording…",
                              #selector(openOnboarding))
        if needsPermission {
            permission.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        }
        menu.addItem(permission)
        let login = item("Open at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("About Liquid Desktop", #selector(openAbout)))
        menu.addItem(item("Quit Liquid Desktop", #selector(quit), key: "q"))
    }

    private var statusLine: String {
        if needsPermission { return "Needs Screen Recording to refract" }
        if !controller.hasSensor && settings.lidControl { return "No lid sensor — tilt disabled" }
        switch controller.status {
        case .running: return String(format: "Flowing · lid %.0f°", controller.liveAngle)
        case .draining: return "Draining…"
        case .idle: return settings.waterVisible ? "Paused" : "Drained"
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "", shortcut: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if shortcut { item.keyEquivalentModifierMask = [.control, .option, .command] }
        return item
    }

    @objc private func toggleWater() { controller.toggleWater(); refresh() }
    @objc private func splash() { controller.splash() }
    @objc private func nextTheme() { controller.nextTheme() }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.themeID = id
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc func openSettings() {
        if let settingsWindow {
            bringToFront(settingsWindow)
            return
        }
        let model = SettingsModel(controller: controller) { [weak self] in self?.openOnboarding() }
        model.needsPermission = needsPermission
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Liquid Desktop"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        settingsWindow = window
        bringToFront(window)
    }

    @objc func openOnboarding() {
        if let onboardingWindow {
            onboardingModel?.recheck()
            bringToFront(onboardingWindow)
            return
        }
        let model = OnboardingModel(hasSensor: controller.hasSensor)
        model.onGranted = { [weak self] in
            self?.needsPermission = false
            self?.controller.isCaptureAllowed = true
        }
        model.onFinish = { [weak self] in
            self?.settings.hasOnboarded = true
            self?.onboardingWindow?.close()
        }
        onboardingModel = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
        window.title = "Welcome to Liquid Desktop"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        onboardingWindow = window
        bringToFront(window)
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Real-time liquid physics over your desktop.\nNothing you see is recorded, stored or sent anywhere.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === onboardingWindow {
            onboardingModel?.stopPolling()
            onboardingModel = nil
            onboardingWindow = nil
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Open at Login"
            alert.informativeText = error.localizedDescription
                + "\n\nMove Liquid Desktop to the Applications folder and try again."
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
