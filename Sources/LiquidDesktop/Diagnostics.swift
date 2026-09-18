import AppKit
import Metal

/// `--diagnose`: prints what the app can see — lid sensor, permission,
/// displays and GPU — without showing anything on screen.
enum Diagnostics {
    @MainActor
    static func run() async {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary
        lines.append("Liquid Desktop \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("GPU: \(MTLCreateSystemDefaultDevice()?.name ?? "none")")

        let sensor = LidAngleSensor()
        try? await Task.sleep(nanoseconds: 150_000_000)
        if let angle = sensor.currentAngle() {
            lines.append(String(format: "Lid sensor: available, %.1f°", angle))
        } else {
            lines.append("Lid sensor: \(sensor.isAvailable ? "available, no reading" : "not found")")
        }

        switch await ScreenPermission.check() {
        case .granted: lines.append("Screen Recording: granted")
        case .denied: lines.append("Screen Recording: not granted")
        case .unavailable(let reason): lines.append("Screen Recording: unavailable (\(reason))")
        }

        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            lines.append(String(format: "Display %u: %.0fx%.0f @%.0fx%@", id, screen.frame.width, screen.frame.height,
                                screen.backingScaleFactor, CGDisplayIsBuiltin(id) != 0 ? " (built-in)" : ""))
        }
        print(lines.joined(separator: "\n"))
    }
}
