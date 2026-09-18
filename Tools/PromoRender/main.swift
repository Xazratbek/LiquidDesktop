import AppKit
import Metal
import simd

// Marketing footage: a 3D MacBook with Liquid Desktop running on its screen.
//   reel-9x16.mp4    Instagram / TikTok Reel with captions and end card
//   hero-16x9.mp4    seamless-ish website hero loop
//   theme-<id>.mp4   short loops for the website's theme gallery
// usage: PromoRender <output-dir> <icon-1024.png> [reel|hero|themes|all]

let arguments = CommandLine.arguments
let outputDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".dist/promo")
let icon = NSImage(contentsOfFile: arguments.count > 2 ? arguments[2] : ".dist/icon-1024.png")
let which = arguments.count > 3 ? arguments[3] : "all"
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
let displayWidth = 1512
let displayHeight = 982
let fps = 60
let desktop = MockDesktop.texture(device: device, width: displayWidth, height: displayHeight)

func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { ease((t - a) / (b - a)) }
func window(_ t: Double, _ start: Double, _ end: Double, fade: Double = 0.3) -> Float {
    Float(min(ramp(t, start, start + fade), 1 - ramp(t, end - fade, end)))
}

func glow(for theme: LiquidTheme) -> SIMD3<Float> {
    switch theme.id {
    case "lagoon": return SIMD3(0.08, 0.85, 0.8)
    case "mercury": return SIMD3(0.65, 0.7, 0.82)
    case "lava": return SIMD3(1.0, 0.33, 0.08)
    default: return SIMD3(0.22, 0.5, 1.0)
    }
}

struct Scene {
    var name: String
    var width: Int
    var height: Int
    var seconds: Double
    var crf: Int
    var stills: [Double] = []
    var angle: (Double) -> Double
    var theme: (Double) -> LiquidTheme
    var cursor: (Double) -> (SIMD2<Double>, SIMD2<Double>)? = { _ in nil }
    var camera: (Double) -> (eye: SIMD3<Float>, target: SIMD3<Float>, fov: Float)
    var overlays: (Double) -> [(MTLTexture, Float)] = { _ in [] }
    var mapping = LidMapping()
}

func render(_ scene: Scene) throws {
    let renderer = try LiquidRenderer(device: device)
    renderer.updateDesktop(from: desktop)
    let mockup = try MockupRenderer(device: device, queue: renderer.commandQueue, width: scene.width, height: scene.height)
    let tank = Tank(aspect: Double(displayWidth) / Double(displayHeight))
    let mapping = scene.mapping
    var theme = scene.theme(0)
    tank.apply(theme: theme)
    tank.warmUp(level: mapping.level(for: scene.angle(0)))

    let displayDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: displayWidth, height: displayHeight, mipmapped: false)
    displayDescriptor.usage = [.renderTarget, .shaderRead]
    displayDescriptor.storageMode = .private
    let display = device.makeTexture(descriptor: displayDescriptor)!

    let url = outputDirectory.appendingPathComponent("\(scene.name).mp4")
    let ffmpeg = Process()
    ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ffmpeg.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra",
                        "-s", "\(scene.width)x\(scene.height)", "-r", "\(fps)", "-i", "-",
                        "-c:v", "libx264", "-preset", "slow", "-pix_fmt", "yuv420p", "-crf", "\(scene.crf)",
                        "-movflags", "+faststart", url.path]
    let pipe = Pipe()
    ffmpeg.standardInput = pipe
    try ffmpeg.run()

    let stillFrames = Set(scene.stills.map { Int($0 * Double(fps)) })
    var bytes = [UInt8](repeating: 0, count: scene.width * scene.height * 4)
    var previousAngle = scene.angle(0)
    let frames = Int(scene.seconds * Double(fps))
    for frame in 0..<frames {
        let t = Double(frame) / Double(fps)
        let nextTheme = scene.theme(t)
        if nextTheme.id != theme.id {
            theme = nextTheme
            tank.apply(theme: theme)
            tank.splash(at: 0.5, strength: 1.3)
        }
        let angle = scene.angle(t)
        var inputs = Tank.Inputs()
        inputs.targetLevel = mapping.level(for: angle)
        inputs.gravityScale = LidMapping.gravityScale(for: angle)
        inputs.lidVelocity = (angle - previousAngle) * Double(fps)
        previousAngle = angle
        if let (position, velocity) = scene.cursor(t) {
            inputs.cursor = position
            inputs.cursorVelocity = velocity
        }
        tank.advance(dt: 1.0 / Double(fps), inputs: inputs)

        let commandBuffer = renderer.commandQueue.makeCommandBuffer()!
        renderer.prepare(from: tank)
        renderer.encode(theme: theme, time: t, into: display, commandBuffer: commandBuffer, drawBackdrop: true)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let camera = scene.camera(t)
        var mock = MockupRenderer.Frame(lidAngle: angle, cameraEye: camera.eye, cameraTarget: camera.target,
                                        fovY: camera.fov, glow: glow(for: theme))
        mock.overlays = scene.overlays(t).map { ($0.0, $0.1) }
        mockup.render(display: display, frame: mock)

        mockup.output.getBytes(&bytes, bytesPerRow: scene.width * 4,
                               from: MTLRegionMake2D(0, 0, scene.width, scene.height), mipmapLevel: 0)
        bytes.withUnsafeBufferPointer { pipe.fileHandleForWriting.write(Data(buffer: $0)) }
        if stillFrames.contains(frame) {
            savePNG(bytes, width: scene.width, height: scene.height,
                    to: outputDirectory.appendingPathComponent("\(scene.name)-\(String(format: "%04.1f", t)).png"))
        }
    }
    try pipe.fileHandleForWriting.close()
    ffmpeg.waitUntilExit()
    print("Wrote \(url.path)")
}

func savePNG(_ bytes: [UInt8], width: Int, height: Int, to url: URL) {
    var copy = bytes
    let context = CGContext(data: &copy, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    guard let image = context.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

// MARK: - Reel (9:16)

func reelScene() -> Scene {
    let w = 1080, h = 1920
    let captions = [
        Captions.headline(device: device, width: w, height: h, text: "What if your Mac\nwas *full of water?*", size: 104, top: 250),
        Captions.headline(device: device, width: w, height: h, text: "Tilt the screen —\n*the water follows*", size: 100, top: 250),
        Captions.headline(device: device, width: w, height: h, text: "Rock it.\n*It splashes.*", size: 118, top: 250),
        Captions.headline(device: device, width: w, height: h, text: "Liquid *mercury*", size: 112, top: 300),
        Captions.headline(device: device, width: w, height: h, text: "…or *lava*", size: 124, top: 300),
    ]
    let end = Captions.endCard(device: device, width: w, height: h, icon: icon)
    return Scene(
        name: "reel-9x16", width: w, height: h, seconds: 15, crf: 18,
        stills: [1.5, 4.9, 7.6, 9.8, 11.4, 14.0],
        angle: { t in
            switch t {
            case ..<3.0: return 102
            case ..<6.2: return 102 + 40 * ramp(t, 3.0, 4.8)
            case ..<6.8: return 142 - 34 * ramp(t, 6.2, 6.8)
            case ..<9.0: return 108 + 11 * sin((t - 6.8) * 2 * .pi * 2.3) * ramp(t, 6.8, 7.0)
            default: return 108 + 7 * sin((t - 9.0) * 2 * .pi * 1.4)
            }
        },
        theme: { t in t < 9.0 ? .lagoon : (t < 10.6 ? .mercury : .lava) },
        cursor: { t in
            guard t > 0.7 && t < 2.5 else { return nil }
            let u = (t - 0.7) / 1.8
            return (SIMD2(0.08 + 0.84 * u, 0.1), SIMD2(0.84 / 1.8 * 1.54, 0))
        },
        camera: { t in
            let push = Float(ramp(t, 0, 12))
            let sway = Float(sin(t * 0.45)) * 0.18
            return (SIMD3(sway, 1.6 - push * 0.1, 7.0 - push * 0.4), SIMD3(0, 0.95, 0.3), 30 * .pi / 180)
        },
        overlays: { t in
            [(captions[0], window(t, 0.15, 3.0)), (captions[1], window(t, 3.1, 6.1)),
             (captions[2], window(t, 6.3, 8.95)), (captions[3], window(t, 9.05, 10.55)),
             (captions[4], window(t, 10.65, 12.2)), (end, Float(ramp(t, 12.2, 12.8)))]
        },
        mapping: LidMapping(uprightAngle: 95, reclinedAngle: 140, lowLevel: 0.22, highLevel: 0.56)
    )
}

// MARK: - Website hero (16:9)

func heroScene() -> Scene {
    Scene(
        name: "hero-16x9", width: 1920, height: 1080, seconds: 12, crf: 22,
        stills: [0.5, 3.5, 7.2],
        angle: { t in
            switch t {
            case ..<1.5: return 102
            case ..<5.5: return 102 + 38 * ramp(t, 1.5, 3.8)
            case ..<6.5: return 140 - 34 * ramp(t, 5.5, 6.5)
            case ..<9.5: return 106 + 10 * sin((t - 6.5) * 2 * .pi * 2.0) * (1 - ramp(t, 8.0, 9.5))
            default: return 106 - 4 * ramp(t, 9.5, 11.5)
            }
        },
        theme: { _ in .lagoon },
        camera: { t in
            let sway = Float(sin(t / 12 * 2 * .pi)) * 0.35
            return (SIMD3(sway, 2.0, 5.9), SIMD3(0, 0.42, 0.45), 27 * .pi / 180)
        }
    )
}

func themeScene(_ theme: LiquidTheme) -> Scene {
    Scene(
        name: "theme-\(theme.id)", width: 960, height: 600, seconds: 6, crf: 26,
        stills: [2.0],
        angle: { t in 110 + 9 * sin(t * 2 * .pi * 0.9) * ramp(t, 0.3, 1.0) },
        theme: { _ in theme },
        camera: { _ in (SIMD3(0, 1.9, 5.4), SIMD3(0, 0.45, 0.45), 30 * .pi / 180) }
    )
}

if which == "reel" || which == "all" { try render(reelScene()) }
if which == "hero" || which == "all" { try render(heroScene()) }
if which == "themes" || which == "all" { for theme in LiquidTheme.all { try render(themeScene(theme)) } }
