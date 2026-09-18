import AppKit
import Metal
import Combine
import IOKit.ps
import simd

/// Coordinates everything: reads the lid and cursor, steps the liquid on a
/// background queue, draws it every display refresh, and keeps screen capture
/// and the overlay alive only while there is water to show.
@MainActor
final class LiquidController: ObservableObject {
    enum Status: Equatable {
        case idle, running, draining
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var liveAngle: Double
    @Published var isCaptureAllowed = false {
        didSet { if isCaptureAllowed != oldValue { refreshCapture() } }
    }

    var hasSensor: Bool { lid.hasSensor }

    private let settings = Settings.shared
    private let device: MTLDevice
    private let renderer: LiquidRenderer
    private let capture: ScreenCapture
    private let lid = LidTracker()
    private let simulationQueue = DispatchQueue(label: "app.liquiddesktop.simulation", qos: .userInteractive)

    private var overlay: OverlayWindow?
    private var tank: Tank?
    private var tankLayout: (columns: Int, aspect: Double)?
    private var isBuildingTank = false
    private var isStepping = false
    private var pendingActions: [(Tank) -> Void] = []
    private var lastStepTime: CFTimeInterval = 0
    private var metrics = Tank.Metrics()
    private var calmSince: CFTimeInterval?
    private var isFrozen = false
    private var drainedSince: CFTimeInterval?
    private var lastCursor: (point: CGPoint, time: CFTimeInterval)?
    private var cursorVelocity = SIMD2<Double>.zero
    private var isSuspended = ScreenLock.isLocked
    private var onBattery = LiquidController.isOnBatteryPower()
    private var captureSignature: String?
    private var cancellables = Set<AnyCancellable>()
    private let startTime = CACurrentMediaTime()
    private var powerTimer: Timer?

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw ControllerError.noMetalDevice }
        self.device = device
        renderer = try LiquidRenderer(device: device)
        capture = ScreenCapture(device: device)
        liveAngle = LidTracker.fallbackAngle
        liveAngle = lid.angle

        capture.onFrame = { [weak self] frame in
            MainActor.assumeIsolated {
                guard let self, self.status != .idle else { return }
                self.renderer.updateDesktop(from: frame.texture)
            }
        }
        capture.onFailure = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.captureSignature = nil
                self?.renderer.clearDesktop()
            }
        }

        observeSettings()
        observeSystem()
        updateActivity()
    }

    // MARK: - Commands

    func toggleWater() {
        settings.waterVisible.toggle()
    }

    func splash() {
        if !settings.waterVisible { settings.waterVisible = true }
        let energy = settings.waveEnergy
        enqueue { $0.splash(strength: 1.1 * energy) }
    }

    func nextTheme() {
        let all = LiquidTheme.all
        let index = all.firstIndex { $0.id == settings.themeID } ?? 0
        settings.themeID = all[(index + 1) % all.count].id
    }

    // MARK: - Activity

    private var effectiveEfficiency: Bool {
        switch settings.quality {
        case .high: return false
        case .efficient: return true
        case .automatic: return onBattery
        }
    }

    private var shouldShowWater: Bool {
        settings.waterVisible && !isSuspended && !(settings.pauseOnBattery && onBattery)
    }

    private func updateActivity() {
        if isSuspended {
            stopRunning()
        } else if shouldShowWater {
            startRunning()
        } else if status == .running {
            status = .draining
            wake()
        }
    }

    private func startRunning() {
        guard let screen = targetScreen else { return }
        let columns = settings.quality == .efficient ? 100 : 120
        let aspect = Double(screen.frame.width / max(screen.frame.height, 1))

        if overlay == nil || overlay?.frame != screen.frame {
            overlay?.dismiss()
            let window = OverlayWindow(screen: screen, device: device)
            window.liquidView.onFrame = { [weak self] layer, _ in
                MainActor.assumeIsolated { self?.frame(layer: layer) }
            }
            overlay = window
        }

        if tankLayout?.columns != columns || abs((tankLayout?.aspect ?? 0) - aspect) > 0.01 {
            buildTank(columns: columns, aspect: aspect)
        } else if status == .idle {
            enqueue { $0.warmUp(level: Tank.hiddenLevel, seconds: 0.4) }
        }

        let wasIdle = status == .idle
        status = .running
        drainedSince = nil
        wake()
        if wasIdle {
            lid.reset()
            overlay?.present()
        }
        refreshCapture()
    }

    private func stopRunning() {
        guard status != .idle else { return }
        status = .idle
        overlay?.dismiss()
        capture.stop()
        captureSignature = nil
        // Never keep an image of the screen around while nothing is showing.
        renderer.clearDesktop()
        lastStepTime = 0
        isFrozen = false
    }

    private func buildTank(columns: Int, aspect: Double) {
        tank = nil
        tankLayout = (columns, aspect)
        isBuildingTank = true
        let theme = settings.theme
        let energy = Float(settings.waveEnergy)
        let stirs = settings.cursorStirs
        simulationQueue.async { [weak self] in
            let tank = Tank(aspect: aspect, columns: columns)
            tank.apply(theme: theme)
            tank.waveEnergy = energy
            tank.cursorStirs = stirs
            tank.warmUp(level: Tank.hiddenLevel, seconds: 1.5)
            DispatchQueue.main.async {
                guard let self, self.tankLayout?.columns == columns, self.tankLayout?.aspect == aspect else { return }
                self.tank = tank
                self.renderer.prepare(from: tank)
                self.isBuildingTank = false
                self.lastStepTime = 0
            }
        }
    }

    private func enqueue(_ action: @escaping (Tank) -> Void) {
        pendingActions.append(action)
        wake()
    }

    private func wake() {
        isFrozen = false
        calmSince = nil
    }

    // MARK: - Frame

    private func frame(layer: CAMetalLayer) {
        let now = CACurrentMediaTime()
        lid.update(now: now)
        if abs(lid.angle - liveAngle) > 0.4 { liveAngle = lid.angle }
        guard let tank, let overlay else { return }

        let inputs = makeInputs(now: now, screenFrame: overlay.frame)
        trackCalm(now: now, inputs: inputs)

        let efficient = effectiveEfficiency
        let interval = efficient ? 1.0 / 30.0 : 1.0 / 60.0
        if !isStepping && !isBuildingTank && !isFrozen && now - lastStepTime >= interval * 0.92 {
            renderer.prepare(from: tank)
            let dt = lastStepTime == 0 ? interval : min(now - lastStepTime, 1.0 / 20.0)
            lastStepTime = now
            isStepping = true
            let actions = pendingActions
            pendingActions.removeAll()
            simulationQueue.async { [weak self] in
                actions.forEach { $0(tank) }
                tank.advance(dt: dt, inputs: inputs)
                let metrics = tank.metrics
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.metrics = metrics
                    self.isStepping = false
                }
            }
        }

        overlay.liquidView.preferredFramesPerSecond = (isFrozen || efficient) ? 30 : 60

        if let drawable = layer.nextDrawable(), let commandBuffer = renderer.commandQueue.makeCommandBuffer() {
            renderer.encode(theme: settings.theme, time: now - startTime, into: drawable.texture,
                            commandBuffer: commandBuffer)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        if status == .draining {
            let drained = metrics.level <= Tank.hiddenLevel + 0.01 && !renderer.hasVisibleLiquid
            if drained {
                drainedSince = drainedSince ?? now
                if now - (drainedSince ?? now) > 0.4 { stopRunning() }
            } else {
                drainedSince = nil
            }
        }
    }

    private func makeInputs(now: CFTimeInterval, screenFrame: CGRect) -> Tank.Inputs {
        var inputs = Tank.Inputs()
        let mapping = settings.lidMapping
        if status == .running {
            inputs.targetLevel = settings.lidControl ? mapping.level(for: lid.angle) : mapping.lowLevel
        } else {
            inputs.targetLevel = Tank.hiddenLevel - 0.02
        }
        if settings.lidControl {
            inputs.gravityScale = LidMapping.gravityScale(for: lid.angle)
            inputs.lidVelocity = lid.velocity
        }

        let point = NSEvent.mouseLocation
        if let last = lastCursor {
            let dt = max(now - last.time, 1.0 / 240.0)
            let height = Double(max(screenFrame.height, 1))
            let instantaneous = SIMD2(Double(point.x - last.point.x), Double(point.y - last.point.y)) / height / dt
            cursorVelocity += (instantaneous - cursorVelocity) * min(dt * 20, 1)
        }
        lastCursor = (point, now)
        if settings.cursorStirs, screenFrame.contains(point) {
            inputs.cursor = SIMD2(Double((point.x - screenFrame.minX) / screenFrame.width),
                                  Double((point.y - screenFrame.minY) / screenFrame.height))
            inputs.cursorVelocity = cursorVelocity
        }
        return inputs
    }

    /// Stops stepping the simulation once the water has visibly settled and
    /// nothing is disturbing it; the shader keeps the surface shimmering, and
    /// any lid, cursor or level change wakes it instantly.
    private func trackCalm(now: CFTimeInterval, inputs: Tank.Inputs) {
        let cursorDisturbing = inputs.cursor.map { cursor in
            let y = cursor.y
            return simd_length(inputs.cursorVelocity) > 0.05 && y < metrics.level + 0.08
        } ?? false
        let busy = abs(inputs.lidVelocity) > 3
            || cursorDisturbing
            || abs(inputs.targetLevel - metrics.level) > 0.004
            || metrics.surfaceMotion > 2.5
            || !pendingActions.isEmpty
            || status == .draining
        if busy {
            wake()
        } else {
            calmSince = calmSince ?? now
            if now - (calmSince ?? now) > 2.5 { isFrozen = true }
        }
    }

    // MARK: - Capture

    private func refreshCapture() {
        guard status != .idle, isCaptureAllowed, let screen = targetScreen else {
            if !isCaptureAllowed { renderer.clearDesktop() }
            return
        }
        let displayID = Self.displayID(of: screen)
        let efficient = effectiveEfficiency
        let scale = efficient ? 0.5 : 1.0
        let fps: Int32 = efficient ? 30 : 60
        let signature = "\(displayID)-\(scale)-\(fps)"
        guard signature != captureSignature else { return }
        captureSignature = signature
        Task { [capture] in
            do {
                try await capture.start(on: displayID, scale: scale, frameRate: fps)
            } catch {
                await MainActor.run { [weak self] in self?.captureSignature = nil }
            }
        }
    }

    // MARK: - Observation

    private func observeSettings() {
        settings.$waterVisible.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivity() }
            .store(in: &cancellables)
        settings.$pauseOnBattery.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivity() }
            .store(in: &cancellables)
        settings.$quality.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.status != .idle else { return }
                self.captureSignature = nil
                self.startRunning()
            }
            .store(in: &cancellables)
        settings.$themeID.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] id in
                let theme = LiquidTheme.named(id)
                self?.enqueue { $0.apply(theme: theme) }
            }
            .store(in: &cancellables)
        settings.$waveEnergy.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] energy in self?.enqueue { $0.waveEnergy = Float(energy) } }
            .store(in: &cancellables)
        settings.$cursorStirs.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] stirs in self?.enqueue { $0.cursorStirs = stirs } }
            .store(in: &cancellables)
        Publishers.Merge3(settings.$waterAmount.map { _ in () },
                          settings.$tiltSensitivity.map { _ in () },
                          settings.$lidControl.map { _ in () })
            .dropFirst(3).receive(on: RunLoop.main)
            .sink { [weak self] in self?.wake() }
            .store(in: &cancellables)
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeIfUnlocked() }
            }
        }
        ScreenLock.observe(onLock: { [weak self] in
            MainActor.assumeIsolated { self?.suspend() }
        }, onUnlock: { [weak self] in
            MainActor.assumeIsolated { self?.resumeIfUnlocked() }
        })
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopRunning()
                self.overlay = nil
                self.captureSignature = nil
                self.updateActivity()
            }
        }

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let battery = Self.isOnBatteryPower()
                guard battery != self.onBattery else { return }
                self.onBattery = battery
                self.updateActivity()
                self.refreshCapture()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        powerTimer = timer
    }

    private func suspend() {
        isSuspended = true
        stopRunning()
    }

    private func resumeIfUnlocked() {
        isSuspended = ScreenLock.isLocked
        updateActivity()
    }

    // MARK: - Helpers

    /// The laptop's own panel (the one the lid tilts), else the main display.
    private var targetScreen: NSScreen? {
        let builtIn = NSScreen.screens.first { CGDisplayIsBuiltin(Self.displayID(of: $0)) != 0 }
        return builtIn ?? NSScreen.main
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    private static func isOnBatteryPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    enum ControllerError: LocalizedError {
        case noMetalDevice
        var errorDescription: String? { "This Mac has no Metal-capable graphics." }
    }
}
