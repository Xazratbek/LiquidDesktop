import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: LiquidController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--diagnose") {
            Task {
                await Diagnostics.run()
                NSApp.terminate(nil)
            }
            return
        }

        NSApp.setActivationPolicy(.accessory)

        do {
            let controller = try LiquidController()
            self.controller = controller
            menuBar = MenuBarController(controller: controller)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Liquid Desktop can’t start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        Task { await checkPermission() }
    }

    private func checkPermission() async {
        let state = await ScreenPermission.check()
        let granted = state == .granted
        controller?.isCaptureAllowed = granted
        menuBar?.needsPermission = !granted
        if !Settings.shared.hasOnboarded {
            menuBar?.openOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.openSettings()
        return true
    }
}
