import AppKit
import Metal
import QuartzCore

/// A transparent Metal view driven by the display's own refresh clock.
final class LiquidView: NSView {
    var onFrame: ((CAMetalLayer, CFTimeInterval) -> Void)?

    private var displayLink: CADisplayLink?

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    var preferredFramesPerSecond: Float = 60 {
        didSet { applyFrameRate() }
    }

    var isRunning: Bool { displayLink != nil }

    init(device: MTLDevice, colorSpace: CGColorSpace?) {
        super.init(frame: .zero)
        wantsLayer = true
        let metal = CAMetalLayer()
        metal.device = device
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.isOpaque = false
        metal.backgroundColor = NSColor.clear.cgColor
        metal.colorspace = colorSpace
        metal.maximumDrawableCount = 3
        layer = metal
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func start() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        applyFrameRate()
        updateDrawableSize()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func applyFrameRate() {
        let fps = preferredFramesPerSecond
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: fps, preferred: fps)
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame?(metalLayer, link.targetTimestamp)
    }
}

/// Borderless, click-through, all-spaces window covering one screen. Floats
/// above the Dock so the water can cover it, but never takes focus or mouse
/// events — the desktop underneath stays fully usable.
final class OverlayWindow: NSWindow {
    let liquidView: LiquidView

    init(screen: NSScreen, device: MTLDevice) {
        let displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
        liquidView = LiquidView(device: device, colorSpace: ScreenCapture.colorSpace(for: displayID))
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        liquidView.frame = CGRect(origin: .zero, size: screen.frame.size)
        liquidView.autoresizingMask = [.width, .height]
        contentView = liquidView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() {
        liquidView.start()
        orderFrontRegardless()
    }

    func dismiss() {
        liquidView.stop()
        orderOut(nil)
    }
}
