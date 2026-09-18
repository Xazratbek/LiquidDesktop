import Foundation

/// Maps the physical lid angle to the water, within the range a person
/// actually looks at the screen. Tilting the screen back lays the glass
/// flatter: in-plane gravity weakens and the water spreads further up the
/// screen. Bringing it upright pools the water at the bottom again.
struct LidMapping {
    var uprightAngle: Double = 95
    var reclinedAngle: Double = 140
    var lowLevel: Double = 0.14
    var highLevel: Double = 0.46

    func level(for angle: Double) -> Double {
        let span = max(reclinedAngle - uprightAngle, 1)
        let t = min(max((angle - uprightAngle) / span, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return lowLevel + (highLevel - lowLevel) * eased
    }

    static func gravityScale(for angle: Double) -> Double {
        max(sin(angle * .pi / 180), 0.4)
    }
}
