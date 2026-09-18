import Foundation

/// 2D FLIP liquid on a staggered (MAC) grid, following the structure of
/// Matthias Müller's "Ten Minute Physics" FLIP solver: particles carry
/// velocity, the grid enforces incompressibility, and a density-drift term
/// keeps particles from slowly compacting.
///
/// Units are grid cells: cell size is 1, positions are in cells, velocities in
/// cells per second. Column 0, column numX-1, row 0 and row numY-1 are walls.
/// The bottom is a per-column movable floor whose velocity is fed into the
/// boundary conditions so a rising floor genuinely pushes the water.
final class FluidSimulation {
    private static let fluidCell: UInt8 = 0
    private static let airCell: UInt8 = 1
    private static let solidCell: UInt8 = 2

    struct Stir {
        var x: Float
        var y: Float
        var vx: Float
        var vy: Float
        var radius: Float
    }

    let numX: Int
    let numY: Int
    let particleRadius: Float = 0.3
    let particleCount: Int

    let posX: UnsafeMutablePointer<Float>
    let posY: UnsafeMutablePointer<Float>
    let velX: UnsafeMutablePointer<Float>
    let velY: UnsafeMutablePointer<Float>

    let floorHeight: UnsafeMutablePointer<Float>
    let floorVelocity: UnsafeMutablePointer<Float>

    var gravityX: Float = 0
    var gravityY: Float = -900
    var flipRatio: Float = 0.9
    var pressureIterations = 60
    var pressureTolerance: Float = 0.05
    var separationIterations = 1
    var driftCorrection: Float = 1
    var stir: Stir?
    var maxSpeed: Float = 420
    /// Fraction of particle velocity removed per second; a little keeps the
    /// body from fizzing without visibly deadening waves.
    var damping: Float = 0

    private(set) var restDensity: Float = 0

    private let cellCount: Int
    private let u: UnsafeMutablePointer<Float>
    private let v: UnsafeMutablePointer<Float>
    private let du: UnsafeMutablePointer<Float>
    private let dv: UnsafeMutablePointer<Float>
    private let prevU: UnsafeMutablePointer<Float>
    private let prevV: UnsafeMutablePointer<Float>
    private let solidity: UnsafeMutablePointer<Float>
    private let density: UnsafeMutablePointer<Float>
    private let cellType: UnsafeMutablePointer<UInt8>

    private let solveCells: UnsafeMutablePointer<Int32>
    private let solveBias: UnsafeMutablePointer<Float>
    private let pcgPressure: UnsafeMutablePointer<Float>
    private let pcgResidual: UnsafeMutablePointer<Float>
    private let pcgAux: UnsafeMutablePointer<Float>
    private let pcgSearch: UnsafeMutablePointer<Float>
    private let pcgPrecon: UnsafeMutablePointer<Float>

    private let hashInvSpacing: Float
    private let hashNumX: Int
    private let hashNumY: Int
    private let hashCount: UnsafeMutablePointer<Int32>
    private let hashStart: UnsafeMutablePointer<Int32>
    private let hashIds: UnsafeMutablePointer<Int32>

    /// - Parameters:
    ///   - columns: interior cell columns.
    ///   - rows: interior cell rows.
    ///   - fillDepth: initial water depth in cells, measured from the floor.
    init(columns: Int, rows: Int, fillDepth: Float) {
        numX = columns + 2
        numY = rows + 2
        cellCount = numX * numY

        let spacingX = 2 * particleRadius
        let spacingY = spacingX * 0.8660254
        let across = Int((Float(columns) - 2 * particleRadius) / spacingX)
        let up = Int((min(fillDepth, Float(rows)) - 2 * particleRadius) / spacingY) + 1
        particleCount = max(across * up, 1)

        func floats(_ count: Int) -> UnsafeMutablePointer<Float> {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
            pointer.initialize(repeating: 0, count: count)
            return pointer
        }

        posX = floats(particleCount)
        posY = floats(particleCount)
        velX = floats(particleCount)
        velY = floats(particleCount)
        floorHeight = floats(numX)
        floorVelocity = floats(numX)
        u = floats(cellCount)
        v = floats(cellCount)
        du = floats(cellCount)
        dv = floats(cellCount)
        prevU = floats(cellCount)
        prevV = floats(cellCount)
        solidity = floats(cellCount)
        density = floats(cellCount)
        cellType = UnsafeMutablePointer<UInt8>.allocate(capacity: cellCount)
        cellType.initialize(repeating: Self.airCell, count: cellCount)
        solveCells = UnsafeMutablePointer<Int32>.allocate(capacity: cellCount)
        solveBias = floats(cellCount)
        pcgPressure = floats(cellCount)
        pcgResidual = floats(cellCount)
        pcgAux = floats(cellCount)
        pcgSearch = floats(cellCount)
        pcgPrecon = floats(cellCount)

        hashInvSpacing = 1 / (2.2 * particleRadius)
        hashNumX = Int(Float(numX) * hashInvSpacing) + 1
        hashNumY = Int(Float(numY) * hashInvSpacing) + 1
        let hashCells = hashNumX * hashNumY
        hashCount = UnsafeMutablePointer<Int32>.allocate(capacity: hashCells)
        hashCount.initialize(repeating: 0, count: hashCells)
        hashStart = UnsafeMutablePointer<Int32>.allocate(capacity: hashCells + 1)
        hashStart.initialize(repeating: 0, count: hashCells + 1)
        hashIds = UnsafeMutablePointer<Int32>.allocate(capacity: particleCount)
        hashIds.initialize(repeating: 0, count: particleCount)

        for i in 0..<numX { floorHeight[i] = 1 }

        var index = 0
        for row in 0..<up {
            for column in 0..<across where index < particleCount {
                let shift: Float = row % 2 == 0 ? 0 : particleRadius
                posX[index] = 1 + particleRadius + spacingX * Float(column) + shift
                posY[index] = 1 + particleRadius + spacingY * Float(row)
                index += 1
            }
        }
        updateSolidity()
    }

    deinit {
        for pointer in [posX, posY, velX, velY, floorHeight, floorVelocity,
                        u, v, du, dv, prevU, prevV, solidity, density] {
            pointer.deallocate()
        }
        cellType.deallocate()
        solveCells.deallocate()
        solveBias.deallocate()
        for pointer in [pcgPressure, pcgResidual, pcgAux, pcgSearch, pcgPrecon] { pointer.deallocate() }
        hashCount.deallocate()
        hashStart.deallocate()
        hashIds.deallocate()
    }

    // MARK: - Step

    func step(dt: Float) {
        updateSolidity()
        integrateParticles(dt: dt)
        if separationIterations > 0 { pushParticlesApart() }
        handleCollisions()
        transferToGrid()
        updateDensity()
        solveIncompressibility()
        transferToParticles()
    }

    /// World-space height of the water surface above each column. Scans down
    /// from the top for the first run of three dense cells, so spray and
    /// loose droplets above the body are ignored, then smooths across columns
    /// so a single sparse column can't cut a seam through the liquid.
    func surfaceHeights(into output: UnsafeMutablePointer<Float>) {
        let n = numY
        let columns = numX - 2
        let threshold = max(restDensity * 0.45, 0.2)
        for i in 1..<(numX - 1) {
            let floorTop = floorHeight[i]
            var surface = floorTop
            var j = numY - 2
            let lowest = max(Int(floorTop), 1) + 2
            while j >= lowest {
                let c = i * n + j
                if density[c] >= threshold && density[c - 1] >= threshold && density[c - 2] >= threshold {
                    let above = density[c + 1]
                    let t = density[c] > above ? (density[c] - threshold) / (density[c] - above) : 0
                    surface = Float(j) + 0.5 + min(max(t, 0), 1)
                    break
                }
                j -= 1
            }
            output[i - 1] = max(surface, floorTop)
        }
        for _ in 0..<2 {
            var previous = output[0]
            for i in 0..<columns {
                let current = output[i]
                let next = i + 1 < columns ? output[i + 1] : current
                output[i] = (previous + 2 * current + next) * 0.25
                previous = current
            }
        }
    }

    /// Fastest particle and the mean particle speed, in cells per second.
    func speedStatistics() -> (max: Float, mean: Float) {
        var best: Float = 0
        var total: Float = 0
        for p in 0..<particleCount {
            let s = velX[p] * velX[p] + velY[p] * velY[p]
            if s > best { best = s }
            total += s.squareRoot()
        }
        return (best.squareRoot(), total / Float(particleCount))
    }

    /// Adds velocity to particles near a point, falling off with distance.
    func impulse(x: Float, y: Float, radius: Float, vx: Float, vy: Float, jitter: Float) {
        let r2 = radius * radius
        var seed = UInt32(truncatingIfNeeded: Int(x * 131 + y * 977)) | 1
        for p in 0..<particleCount {
            let dx = posX[p] - x
            let dy = posY[p] - y
            let d2 = dx * dx + dy * dy
            guard d2 < r2 else { continue }
            let falloff = 1 - d2 / r2
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let noise = Float(seed & 0xFFFF) / 65535 - 0.5
            velX[p] += (vx + noise * jitter) * falloff
            velY[p] += (vy + abs(noise) * jitter) * falloff
        }
    }

    // MARK: - Internals

    private func updateSolidity() {
        let n = numY
        for i in 0..<numX {
            let floorTop = floorHeight[min(max(i, 1), numX - 2)]
            for j in 0..<numY {
                let isWall = i == 0 || i == numX - 1 || j == 0 || j == numY - 1
                let isFloor = Float(j) + 0.5 < floorTop
                solidity[i * n + j] = (isWall || isFloor) ? 0 : 1
            }
        }
    }

    private func integrateParticles(dt: Float) {
        let gx = gravityX * dt
        let gy = gravityY * dt
        let limit = maxSpeed * maxSpeed
        let keep = max(1 - damping * dt, 0)
        for p in 0..<particleCount {
            var vx = velX[p] * keep + gx
            var vy = velY[p] * keep + gy
            let s = vx * vx + vy * vy
            if s > limit {
                let scale = maxSpeed / s.squareRoot()
                vx *= scale
                vy *= scale
            }
            velX[p] = vx
            velY[p] = vy
            posX[p] += vx * dt
            posY[p] += vy * dt
        }
    }

    private func pushParticlesApart() {
        let posX = self.posX, posY = self.posY
        let hashCount = self.hashCount, hashStart = self.hashStart, hashIds = self.hashIds
        let inv = hashInvSpacing
        let hx = hashNumX, hy = hashNumY
        let count = particleCount
        let hashCells = hx * hy
        hashCount.update(repeating: 0, count: hashCells)

        var p = 0
        while p < count {
            let xi = min(max(Int(posX[p] * inv), 0), hx - 1)
            let yi = min(max(Int(posY[p] * inv), 0), hy - 1)
            hashCount[xi * hy + yi] += 1
            p += 1
        }
        var running: Int32 = 0
        for c in 0..<hashCells {
            running += hashCount[c]
            hashStart[c] = running
        }
        hashStart[hashCells] = running
        p = 0
        while p < count {
            let xi = min(max(Int(posX[p] * inv), 0), hx - 1)
            let yi = min(max(Int(posY[p] * inv), 0), hy - 1)
            let c = xi * hy + yi
            hashStart[c] -= 1
            hashIds[Int(hashStart[c])] = Int32(p)
            p += 1
        }

        let minDist = 2 * particleRadius
        let minDist2 = minDist * minDist
        for _ in 0..<separationIterations {
            // Walk particles in hash order for cache locality, and resolve each
            // pair once (q > p) instead of from both sides.
            var k = 0
            while k < count {
                let p = Int(hashIds[k])
                k += 1
                let pxi = min(max(Int(posX[p] * inv), 0), hx - 1)
                let pyi = min(max(Int(posY[p] * inv), 0), hy - 1)
                let x0 = max(pxi - 1, 0), x1 = min(pxi + 1, hx - 1)
                let y0 = max(pyi - 1, 0), y1 = min(pyi + 1, hy - 1)
                var xi = x0
                while xi <= x1 {
                    var yi = y0
                    while yi <= y1 {
                        let c = xi * hy + yi
                        var m = Int(hashStart[c])
                        let last = Int(hashStart[c + 1])
                        while m < last {
                            let q = Int(hashIds[m])
                            m += 1
                            if q <= p { continue }
                            var dx = posX[q] - posX[p]
                            var dy = posY[q] - posY[p]
                            let d2 = dx * dx + dy * dy
                            if d2 > minDist2 || d2 == 0 { continue }
                            let d = d2.squareRoot()
                            let s = 0.5 * (minDist - d) / d
                            dx *= s
                            dy *= s
                            posX[p] -= dx
                            posY[p] -= dy
                            posX[q] += dx
                            posY[q] += dy
                        }
                        yi += 1
                    }
                    xi += 1
                }
            }
        }
    }

    private func handleCollisions() {
        let r = particleRadius
        let minX = 1 + r
        let maxX = Float(numX - 1) - r
        let maxY = Float(numY - 1) - r
        let stir = self.stir
        for p in 0..<particleCount {
            var x = posX[p]
            var y = posY[p]
            if x < minX { x = minX; velX[p] = 0 }
            if x > maxX { x = maxX; velX[p] = 0 }
            let column = min(max(Int(x), 1), numX - 2)
            let floorTop = floorHeight[column] + r
            if y < floorTop {
                y = floorTop
                if velY[p] < floorVelocity[column] { velY[p] = floorVelocity[column] }
            }
            if y > maxY { y = maxY; velY[p] = 0 }
            if let stir {
                let dx = x - stir.x
                let dy = y - stir.y
                let d2 = dx * dx + dy * dy
                let r2 = stir.radius * stir.radius
                if d2 < r2 {
                    let w = (1 - d2.squareRoot() / stir.radius) * 0.35
                    velX[p] += (stir.vx - velX[p]) * w
                    velY[p] += (stir.vy - velY[p]) * w
                }
            }
            posX[p] = x
            posY[p] = y
        }
    }

    private func transferToGrid() {
        let n = numY
        prevU.update(from: u, count: cellCount)
        prevV.update(from: v, count: cellCount)
        u.update(repeating: 0, count: cellCount)
        v.update(repeating: 0, count: cellCount)
        du.update(repeating: 0, count: cellCount)
        dv.update(repeating: 0, count: cellCount)

        for c in 0..<cellCount {
            cellType[c] = solidity[c] == 0 ? Self.solidCell : Self.airCell
        }
        for p in 0..<particleCount {
            let xi = min(max(Int(posX[p]), 0), numX - 1)
            let yi = min(max(Int(posY[p]), 0), numY - 1)
            let c = xi * n + yi
            if cellType[c] == Self.airCell { cellType[c] = Self.fluidCell }
        }

        splat(field: u, weights: du, velocity: velX, dx: 0, dy: 0.5)
        splat(field: v, weights: dv, velocity: velY, dx: 0.5, dy: 0)

        for c in 0..<cellCount {
            if du[c] > 0 { u[c] /= du[c] }
            if dv[c] > 0 { v[c] /= dv[c] }
        }

        for i in 0..<numX {
            for j in 0..<numY {
                let c = i * n + j
                let solidHere = cellType[c] == Self.solidCell
                if solidHere || (i > 0 && cellType[c - n] == Self.solidCell) {
                    u[c] = 0
                }
                let solidBelow = j > 0 && cellType[c - 1] == Self.solidCell
                if solidHere || solidBelow {
                    let isFloorFace = !solidHere && solidBelow && i > 0 && i < numX - 1
                    v[c] = isFloorFace ? floorVelocity[i] : 0
                }
            }
        }
    }

    private func splat(field: UnsafeMutablePointer<Float>, weights: UnsafeMutablePointer<Float>,
                       velocity: UnsafeMutablePointer<Float>, dx: Float, dy: Float) {
        let n = numY
        let maxX = Float(numX - 1)
        let maxY = Float(numY - 1)
        for p in 0..<particleCount {
            let x = min(max(posX[p], 1), maxX) - dx
            let y = min(max(posY[p], 1), maxY) - dy
            let x0 = min(Int(x), numX - 2)
            let y0 = min(Int(y), numY - 2)
            let tx = x - Float(x0)
            let ty = y - Float(y0)
            let x1 = min(x0 + 1, numX - 2)
            let y1 = min(y0 + 1, numY - 2)
            let sx = 1 - tx
            let sy = 1 - ty
            let w0 = sx * sy, w1 = tx * sy, w2 = tx * ty, w3 = sx * ty
            let c0 = x0 * n + y0, c1 = x1 * n + y0, c2 = x1 * n + y1, c3 = x0 * n + y1
            let value = velocity[p]
            field[c0] += value * w0; weights[c0] += w0
            field[c1] += value * w1; weights[c1] += w1
            field[c2] += value * w2; weights[c2] += w2
            field[c3] += value * w3; weights[c3] += w3
        }
    }

    private func updateDensity() {
        let n = numY
        density.update(repeating: 0, count: cellCount)
        let maxX = Float(numX - 1)
        let maxY = Float(numY - 1)
        for p in 0..<particleCount {
            let x = min(max(posX[p], 1), maxX) - 0.5
            let y = min(max(posY[p], 1), maxY) - 0.5
            let x0 = Int(x)
            let y0 = Int(y)
            let tx = x - Float(x0)
            let ty = y - Float(y0)
            let x1 = min(x0 + 1, numX - 2)
            let y1 = min(y0 + 1, numY - 2)
            let sx = 1 - tx
            let sy = 1 - ty
            density[x0 * n + y0] += sx * sy
            density[x1 * n + y0] += tx * sy
            density[x1 * n + y1] += tx * ty
            density[x0 * n + y1] += sx * ty
        }

        if restDensity == 0 {
            var sum: Float = 0
            var fluidCells = 0
            for c in 0..<cellCount where cellType[c] == Self.fluidCell {
                sum += density[c]
                fluidCells += 1
            }
            if fluidCells > 0 { restDensity = sum / Float(fluidCells) }
        }
    }

    /// Makes the grid velocity divergence-free by solving the pressure
    /// Poisson equation with MIC(0)-preconditioned conjugate gradient. Air
    /// cells hold zero pressure, walls and floor are Neumann boundaries.
    /// Gauss-Seidel sweeps were not enough here: the reservoir under the
    /// screen is deep, and an unconverged solve lets every frame's gravity leak
    /// through, so the water compacts and fizzes.
    private func solveIncompressibility() {
        let n = numY
        let u = self.u, v = self.v, solidity = self.solidity, density = self.density
        let cellType = self.cellType
        let cells = solveCells
        let pressure = pcgPressure, residual = pcgResidual, auxiliary = pcgAux
        let search = pcgSearch, precon = pcgPrecon, diagonal = solveBias
        prevU.update(from: u, count: cellCount)
        prevV.update(from: v, count: cellCount)
        pressure.update(repeating: 0, count: cellCount)
        auxiliary.update(repeating: 0, count: cellCount)
        search.update(repeating: 0, count: cellCount)
        precon.update(repeating: 0, count: cellCount)

        let fluid = Self.fluidCell
        let rest = restDensity
        let drift = driftCorrection
        var active = 0
        var maxResidual: Float = 0
        for i in 1..<(numX - 1) {
            for j in 1..<(numY - 1) {
                let c = i * n + j
                guard cellType[c] == fluid else { continue }
                let neighbours = solidity[c - n] + solidity[c + n] + solidity[c - 1] + solidity[c + 1]
                guard neighbours > 0 else { continue }
                cells[active] = Int32(c)
                active += 1
                diagonal[c] = neighbours
                var divergence = u[c + n] - u[c] + v[c + 1] - v[c]
                if rest > 0 {
                    let compression = density[c] - rest
                    if compression > 0 { divergence -= drift * compression }
                }
                residual[c] = -divergence
                maxResidual = max(maxResidual, abs(divergence))
            }
        }
        guard active > 0, maxResidual > 1e-4 else { return }

        // A[c][right] = -1 when the right neighbour is fluid, likewise for top.
        @inline(__always) func offX(_ c: Int) -> Float { cellType[c + n] == fluid ? -1 : 0 }
        @inline(__always) func offY(_ c: Int) -> Float { cellType[c + 1] == fluid ? -1 : 0 }
        @inline(__always) func isActive(_ c: Int) -> Bool { cellType[c] == fluid && diagonal[c] > 0 }

        let tuning: Float = 0.97
        let safety: Float = 0.25
        for k in 0..<active {
            let c = Int(cells[k])
            let left = c - n, below = c - 1
            let pl = isActive(left) ? precon[left] : 0
            let pb = isActive(below) ? precon[below] : 0
            let ax = isActive(left) ? offX(left) : 0
            let ay = isActive(below) ? offY(below) : 0
            let axy = isActive(left) ? offY(left) : 0
            let ayx = isActive(below) ? offX(below) : 0
            var e = diagonal[c] - (ax * pl) * (ax * pl) - (ay * pb) * (ay * pb)
                - tuning * (ax * axy * pl * pl + ay * ayx * pb * pb)
            if e < safety * diagonal[c] { e = diagonal[c] }
            precon[c] = 1 / e.squareRoot()
        }

        func applyPreconditioner(to r: UnsafeMutablePointer<Float>, into z: UnsafeMutablePointer<Float>) {
            for k in 0..<active {
                let c = Int(cells[k])
                let left = c - n, below = c - 1
                var t = r[c]
                if isActive(left) { t -= offX(left) * precon[left] * z[left] }
                if isActive(below) { t -= offY(below) * precon[below] * z[below] }
                z[c] = t * precon[c]
            }
            var k = active - 1
            while k >= 0 {
                let c = Int(cells[k])
                var t = z[c]
                if isActive(c + n) { t -= offX(c) * precon[c] * z[c + n] }
                if isActive(c + 1) { t -= offY(c) * precon[c] * z[c + 1] }
                z[c] = t * precon[c]
                k -= 1
            }
        }

        func dot(_ a: UnsafeMutablePointer<Float>, _ b: UnsafeMutablePointer<Float>) -> Float {
            var sum: Float = 0
            for k in 0..<active {
                let c = Int(cells[k])
                sum += a[c] * b[c]
            }
            return sum
        }

        applyPreconditioner(to: residual, into: auxiliary)
        for k in 0..<active { let c = Int(cells[k]); search[c] = auxiliary[c] }
        var sigma = dot(auxiliary, residual)
        let tolerance = pressureTolerance

        for _ in 0..<pressureIterations {
            // auxiliary = A * search
            for k in 0..<active {
                let c = Int(cells[k])
                var value = diagonal[c] * search[c]
                if isActive(c - n) { value -= search[c - n] }
                if isActive(c + n) { value -= search[c + n] }
                if isActive(c - 1) { value -= search[c - 1] }
                if isActive(c + 1) { value -= search[c + 1] }
                auxiliary[c] = value
            }
            let denominator = dot(auxiliary, search)
            guard denominator != 0 else { break }
            let alpha = sigma / denominator
            var largest: Float = 0
            for k in 0..<active {
                let c = Int(cells[k])
                pressure[c] += alpha * search[c]
                residual[c] -= alpha * auxiliary[c]
                largest = max(largest, abs(residual[c]))
            }
            if largest < tolerance { break }
            applyPreconditioner(to: residual, into: auxiliary)
            let sigmaNew = dot(auxiliary, residual)
            let beta = sigmaNew / max(sigma, 1e-20)
            for k in 0..<active {
                let c = Int(cells[k])
                search[c] = auxiliary[c] + beta * search[c]
            }
            sigma = sigmaNew
        }

        // Subtract the pressure gradient on every face between two non-solid
        // cells. Air cells keep zero pressure; faces touching solids keep the
        // boundary velocity set during transfer.
        for i in 1..<(numX - 1) {
            for j in 1..<(numY - 1) {
                let c = i * n + j
                guard solidity[c] > 0 else { continue }
                let here = cellType[c] == fluid ? pressure[c] : 0
                if solidity[c - n] > 0 {
                    let left = cellType[c - n] == fluid ? pressure[c - n] : 0
                    if cellType[c] == fluid || cellType[c - n] == fluid { u[c] -= here - left }
                }
                if solidity[c - 1] > 0 {
                    let below = cellType[c - 1] == fluid ? pressure[c - 1] : 0
                    if cellType[c] == fluid || cellType[c - 1] == fluid { v[c] -= here - below }
                }
            }
        }
        for c in 0..<cellCount { diagonal[c] = 0 }
    }

    private func transferToParticles() {
        gather(field: u, previous: prevU, velocity: velX, dx: 0, dy: 0.5, offset: numY)
        gather(field: v, previous: prevV, velocity: velY, dx: 0.5, dy: 0, offset: 1)
    }

    private func gather(field: UnsafeMutablePointer<Float>, previous: UnsafeMutablePointer<Float>,
                        velocity: UnsafeMutablePointer<Float>, dx: Float, dy: Float, offset: Int) {
        let n = numY
        let maxX = Float(numX - 1)
        let maxY = Float(numY - 1)
        let flip = flipRatio
        let air = Self.airCell
        for p in 0..<particleCount {
            let x = min(max(posX[p], 1), maxX) - dx
            let y = min(max(posY[p], 1), maxY) - dy
            let x0 = min(Int(x), numX - 2)
            let y0 = min(Int(y), numY - 2)
            let tx = x - Float(x0)
            let ty = y - Float(y0)
            let x1 = min(x0 + 1, numX - 2)
            let y1 = min(y0 + 1, numY - 2)
            let sx = 1 - tx
            let sy = 1 - ty
            let c0 = x0 * n + y0, c1 = x1 * n + y0, c2 = x1 * n + y1, c3 = x0 * n + y1

            @inline(__always) func valid(_ c: Int) -> Float {
                (cellType[c] != air || cellType[c - offset] != air) ? 1 : 0
            }
            let w0 = valid(c0) * sx * sy
            let w1 = valid(c1) * tx * sy
            let w2 = valid(c2) * tx * ty
            let w3 = valid(c3) * sx * ty
            let total = w0 + w1 + w2 + w3
            guard total > 0 else { continue }

            let pic = (w0 * field[c0] + w1 * field[c1] + w2 * field[c2] + w3 * field[c3]) / total
            let correction = (w0 * (field[c0] - previous[c0]) + w1 * (field[c1] - previous[c1])
                + w2 * (field[c2] - previous[c2]) + w3 * (field[c3] - previous[c3])) / total
            velocity[p] = (1 - flip) * pic + flip * (velocity[p] + correction)
        }
    }
}
