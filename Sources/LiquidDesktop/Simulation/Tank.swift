import Foundation
import simd

/// The screen as a glass tank. Owns the FLIP simulation and turns high-level
/// intent — "the water should sit this high", "the lid just wiggled", "the
/// cursor is dragging through here" — into floor motion and forces.
///
/// The simulation domain extends below the visible screen. A reservoir of
/// water lives down there, and the water level is changed by raising or
/// lowering a hidden floor, so the surface rises and falls with real momentum
/// instead of being teleported.
final class Tank {
    struct Inputs {
        /// Desired surface height as a fraction of the screen height. Negative
        /// values hide the water below the bottom edge.
        var targetLevel: Double = 0.2
        /// In-plane gravity multiplier (1 = screen upright).
        var gravityScale: Double = 1
        /// Lid angular velocity in degrees per second (positive = opening).
        var lidVelocity: Double = 0
        /// Cursor in screen fractions, origin bottom-left, and its velocity in
        /// screen heights per second.
        var cursor: SIMD2<Double>?
        var cursorVelocity: SIMD2<Double> = .zero
    }

    struct Metrics {
        /// Commanded water level as a fraction of the screen height.
        var level: Double = Tank.hiddenLevel
        var surfaceMotion: Float = 0
    }

    static let maxLevel: Double = 0.62
    static let hiddenLevel: Double = -0.06
    static let baseGravity: Float = 900

    let simulation: FluidSimulation
    let columns: Int
    let visibleRows: Float
    let screenBottom: Float
    var screenTop: Float { screenBottom + visibleRows }

    var gravity: Float = Tank.baseGravity
    var waveEnergy: Float = 1
    var cursorStirs = true

    private(set) var surface: [Float]
    private(set) var level: Float
    /// Smoothed mean change of the surface height per second, in cells. Near
    /// zero means the water is visually at rest.
    private(set) var surfaceMotion: Float = 0
    private var previousSurface: [Float]

    private var levelVelocity: Float = 0
    private var depthEstimate: Float
    private var previousFloor: [Float]
    private var sloshSign: Float = 1
    private var lastLidVelocity: Float = 0
    private var slosh: Float = 0
    private var splashCooldown: Float = 0
    private var randomState: UInt32 = 0x9E3779B9
    private var elapsed: Float = 0

    init(aspect: Double, columns: Int = 120) {
        self.columns = columns
        visibleRows = Float(Double(columns) / max(aspect, 0.3))
        let maxLevelCells = Float(Self.maxLevel) * visibleRows
        let hiddenCells = Float(-Self.hiddenLevel) * visibleRows
        let depth = maxLevelCells + hiddenCells + 4
        depthEstimate = depth
        screenBottom = 1 + depth + hiddenCells + 3
        let rows = Int((screenBottom + visibleRows).rounded(.up))

        simulation = FluidSimulation(columns: columns, rows: rows, fillDepth: depth)
        surface = Array(repeating: 0, count: columns)
        previousSurface = surface
        previousFloor = Array(repeating: 1, count: simulation.numX)
        level = Float(Self.hiddenLevel) * visibleRows

        settle()
    }

    /// Lets the freshly seeded particles come to rest so the measured depth
    /// (and therefore the mapping from floor height to visible level) is
    /// accurate before anything is shown.
    private func settle() {
        simulation.gravityY = -gravity
        for i in 1..<(simulation.numX - 1) { simulation.floorHeight[i] = 1 }
        for _ in 0..<90 { simulation.step(dt: 1.0 / 60.0) }
        measureDepth(blend: 1)
        shapeFloor(dt: 1.0 / 60.0)
        for i in 0..<simulation.numX { simulation.floorVelocity[i] = 0 }
    }

    private func measureDepth(blend: Float) {
        surface.withUnsafeMutableBufferPointer { simulation.surfaceHeights(into: $0.baseAddress!) }
        let sorted = surface.sorted()
        let median = sorted[sorted.count / 2]
        var floorSum: Float = 0
        for i in 1...columns { floorSum += simulation.floorHeight[i] }
        let measured = median - floorSum / Float(columns)
        depthEstimate += (measured - depthEstimate) * blend
    }

    /// Moves the water to `fraction` and lets it come to rest before it is
    /// ever shown, so the first visible frame is calm.
    func warmUp(level fraction: Double, seconds: Double = 2.5) {
        level = Float(fraction) * visibleRows
        levelVelocity = 0
        var inputs = Inputs()
        inputs.targetLevel = fraction
        for _ in 0..<Int(seconds * 60) { advance(dt: 1.0 / 60.0, inputs: inputs) }
    }

    /// A burst of water thrown up from the surface, for demos and shortcuts.
    func splash(at fraction: Double? = nil, strength: Double = 1) {
        let x = Float(fraction ?? Double(nextRandom())) * Float(columns) + 1
        let column = min(max(Int(x) - 1, 0), columns - 1)
        let y = surface[column]
        let s = Float(strength) * waveEnergy
        simulation.impulse(x: x, y: y - 2, radius: 9, vx: 0, vy: 260 * s, jitter: 160 * s)
    }

    var metrics: Metrics {
        Metrics(level: Double(level / visibleRows), surfaceMotion: surfaceMotion)
    }

    func apply(theme: LiquidTheme) {
        simulation.flipRatio = theme.flipRatio
        gravity = Self.baseGravity * theme.gravityScale
    }

    func advance(dt frameDelta: Double, inputs: Inputs) {
        let dt = Float(min(max(frameDelta, 1.0 / 240.0), 1.0 / 30.0))
        elapsed += dt

        moveLevel(toward: Float(inputs.targetLevel) * visibleRows, dt: dt)
        driveSlosh(lidVelocity: Float(inputs.lidVelocity), dt: dt)
        shapeFloor(dt: dt)

        simulation.gravityY = -gravity * Float(min(max(inputs.gravityScale, 0.35), 1.2))
        simulation.stir = stir(from: inputs)

        let speed = simulation.speedStatistics()
        let substeps = min(max(Int((speed.max * dt / 4).rounded(.up)), 1), 3)
        let subDt = dt / Float(substeps)
        for _ in 0..<substeps { simulation.step(dt: subDt) }

        surface.withUnsafeMutableBufferPointer { simulation.surfaceHeights(into: $0.baseAddress!) }
        var change: Float = 0
        for i in 0..<columns { change += abs(surface[i] - previousSurface[i]) }
        previousSurface = surface
        surfaceMotion += (change / Float(columns) / dt - surfaceMotion) * min(dt * 4, 1)

        if abs(levelVelocity) < 0.3 && surfaceMotion < 4 {
            measureDepth(blend: min(dt * 0.5, 1))
        }
    }

    private func moveLevel(toward target: Float, dt: Float) {
        let stiffness: Float = 18
        let damping = 2 * stiffness.squareRoot() * 1.05
        let acceleration = stiffness * (target - level) - damping * levelVelocity
        levelVelocity += acceleration * dt
        let limit = visibleRows * 1.4
        levelVelocity = min(max(levelVelocity, -limit), limit)
        level += levelVelocity * dt
        let lowest = Float(Self.hiddenLevel) * visibleRows
        let highest = Float(Self.maxLevel) * visibleRows
        level = min(max(level, lowest), highest)
    }

    /// Rocking the lid back and forth tilts the hidden floor alternately left
    /// and right, which excites the tank's natural sloshing mode. A sharp
    /// reversal also throws a splash off the surface.
    private func driveSlosh(lidVelocity: Float, dt: Float) {
        let energy = waveEnergy
        if lidVelocity * lastLidVelocity < 0 && abs(lastLidVelocity) > 20 {
            sloshSign = -sloshSign
        }
        let reversal = abs(lidVelocity - lastLidVelocity) / max(dt, 1.0 / 240.0)
        lastLidVelocity = lidVelocity

        let target = min(max(abs(lidVelocity) * 0.045 * energy, 0), 5) * sloshSign
        slosh += (target - slosh) * min(dt * 6, 1)

        splashCooldown -= dt
        if reversal > 2600 && abs(lidVelocity) > 25 && splashCooldown <= 0 && level > Float(Self.hiddenLevel) * visibleRows * 0.5 {
            splashCooldown = 0.18
            let strength = Double(min(reversal / 6000, 1.4))
            splash(at: Double(nextRandom()) * 0.8 + 0.1, strength: strength)
        }
    }

    private func shapeFloor(dt: Float) {
        let base = screenBottom + level - depthEstimate
        let rise = min(max(levelVelocity * 0.06 * waveEnergy, -3), 3)
        let floorCap = screenBottom - 3
        let numX = simulation.numX
        for i in 1..<(numX - 1) {
            let x = (Float(i) - 0.5) / Float(columns)
            let hump = -cos(2 * .pi * x) * rise
            let tilt = (x - 0.5) * 2 * slosh
            let height = min(max(base + hump + tilt, 1), floorCap)
            let velocity = (height - previousFloor[i]) / dt
            simulation.floorVelocity[i] = min(max(velocity, -240), 240)
            simulation.floorHeight[i] = height
            previousFloor[i] = height
        }
    }

    private func stir(from inputs: Inputs) -> FluidSimulation.Stir? {
        guard cursorStirs, let cursor = inputs.cursor else { return nil }
        let velocity = SIMD2<Float>(inputs.cursorVelocity) * visibleRows
        guard simd_length(velocity) > 6 else { return nil }
        let x = 1 + Float(cursor.x) * Float(columns)
        let y = screenBottom + Float(cursor.y) * visibleRows
        let clamped = velocity * min(1, 300 / max(simd_length(velocity), 1))
        return .init(x: x, y: y, vx: clamped.x, vy: clamped.y, radius: 5)
    }

    private func nextRandom() -> Float {
        randomState ^= randomState << 13
        randomState ^= randomState >> 17
        randomState ^= randomState << 5
        return Float(randomState & 0xFFFFFF) / Float(0xFFFFFF)
    }
}
