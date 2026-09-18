import Foundation
import QuartzCore

/// Smooths the raw lid angle and derives its angular velocity. Without a
/// sensor it reports a fixed, comfortable viewing angle.
final class LidTracker {
    static let fallbackAngle: Double = 110

    private let sensor = LidAngleSensor(pollInterval: 1.0 / 90.0)
    private var lastUpdate: CFTimeInterval = 0

    private(set) var angle: Double
    private(set) var velocity: Double = 0

    var hasSensor: Bool { sensor.isAvailable }
    var rawAngle: Double? { sensor.currentAngle() }

    init() {
        angle = sensor.currentAngle() ?? Self.fallbackAngle
    }

    func update(now: CFTimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60.0 : min(max(now - lastUpdate, 1.0 / 240.0), 0.1)
        lastUpdate = now
        guard let raw = sensor.currentAngle() else {
            angle = Self.fallbackAngle
            velocity = 0
            return
        }
        // A lid that is shut (or a bogus reading while it closes) should never
        // yank the water around.
        let clamped = min(max(raw, 60), 180)
        let smoothed = angle + (clamped - angle) * min(dt * 22, 1)
        let instantaneous = (smoothed - angle) / dt
        velocity += (instantaneous - velocity) * min(dt * 14, 1)
        angle = smoothed
    }

    func reset() {
        angle = sensor.currentAngle().map { min(max($0, 60), 180) } ?? Self.fallbackAngle
        velocity = 0
        lastUpdate = 0
    }
}
