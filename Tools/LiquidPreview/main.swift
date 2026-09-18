import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers

// Renders Liquid Desktop offscreen over a mock desktop while a scripted lid
// performance plays out, then encodes an MP4 (and a few PNG stills) with
// ffmpeg. No window, no display, no permissions — the quickest way to judge
// how the liquid looks and moves, and the source of marketing footage.
//
// usage: LiquidPreview <output-dir> [theme-id|all] [width] [height] [seconds]

let arguments = CommandLine.arguments
let outputDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "./preview")
let themeArgument = arguments.count > 2 ? arguments[2] : "clear"
let width = arguments.count > 3 ? Int(arguments[3]) ?? 1512 : 1512
let height = arguments.count > 4 ? Int(arguments[4]) ?? 982 : 982
let duration = arguments.count > 5 ? Double(arguments[5]) ?? 10 : 10
let fps = 60
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }

func writePNG(_ bytes: [UInt8], to url: URL) {
    var copy = bytes
    let context = CGContext(data: &copy, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// The scripted performance: rest, recline, return upright, rock the lid,
/// then drag the cursor through the water.
func lidAngle(at t: Double) -> Double {
    func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
    switch t {
    case ..<1.0: return 100
    case ..<2.8: return 100 + 42 * ease((t - 1.0) / 1.8)
    case ..<3.8: return 142
    case ..<5.2: return 142 - 42 * ease((t - 3.8) / 1.4)
    case ..<7.0: return 108 + 10 * sin((t - 5.2) * 2 * .pi * 2.2) * ease((t - 5.2) / 0.3)
    default: return 100
    }
}

func cursor(at t: Double) -> (SIMD2<Double>, SIMD2<Double>)? {
    guard t > 7.6 && t < 9.2 else { return nil }
    let u = (t - 7.6) / 1.6
    let position = SIMD2(0.1 + 0.8 * u, 0.1 + 0.03 * sin(u * 9))
    let velocity = SIMD2(0.8 / 1.6 * (1512.0 / 982.0), 0.03 * 9 * cos(u * 9) / 1.6)
    return (position, velocity)
}

let desktopTexture = MockDesktop.texture(device: device, width: width, height: height)
let themes = themeArgument == "all" ? LiquidTheme.all : [LiquidTheme.named(themeArgument)]

for theme in themes {
    let renderer = try LiquidRenderer(device: device)
    renderer.updateDesktop(from: desktopTexture)
    let tank = Tank(aspect: Double(width) / Double(height))
    tank.gravity *= theme.gravityScale
    tank.simulation.flipRatio = theme.flipRatio
    let mapping = LidMapping()
    tank.warmUp(level: mapping.level(for: lidAngle(at: 0)))

    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    targetDescriptor.usage = [.renderTarget, .shaderRead]
    targetDescriptor.storageMode = .shared
    let target = device.makeTexture(descriptor: targetDescriptor)!

    let videoURL = outputDirectory.appendingPathComponent("liquid-\(theme.id).mp4")
    let ffmpeg = Process()
    ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ffmpeg.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra",
                        "-s", "\(width)x\(height)", "-r", "\(fps)", "-i", "-",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", videoURL.path]
    let pipe = Pipe()
    ffmpeg.standardInput = pipe
    try ffmpeg.run()

    let stillFrames: Set<Int> = [40, 200, 330, 400, 430, 470, 540]
    var previousAngle = lidAngle(at: 0)
    var simulationTime = 0.0
    var renderTime = 0.0
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let frameCount = Int(duration * Double(fps))

    for frame in 0..<frameCount {
        let t = Double(frame) / Double(fps)
        let angle = lidAngle(at: t)
        var inputs = Tank.Inputs()
        inputs.targetLevel = mapping.level(for: angle)
        inputs.gravityScale = LidMapping.gravityScale(for: angle)
        inputs.lidVelocity = (angle - previousAngle) * Double(fps)
        previousAngle = angle
        if let (position, velocity) = cursor(at: t) {
            inputs.cursor = position
            inputs.cursorVelocity = velocity
        }

        let simStart = Date()
        tank.advance(dt: 1.0 / Double(fps), inputs: inputs)
        simulationTime += Date().timeIntervalSince(simStart)

        let renderStart = Date()
        let commandBuffer = renderer.commandQueue.makeCommandBuffer()!
        renderer.prepare(from: tank)
        renderer.encode(theme: theme, time: t, into: target, commandBuffer: commandBuffer, drawBackdrop: true)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        renderTime += Date().timeIntervalSince(renderStart)

        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        bytes.withUnsafeBufferPointer { pipe.fileHandleForWriting.write(Data(buffer: $0)) }
        if stillFrames.contains(frame) {
            writePNG(bytes, to: outputDirectory.appendingPathComponent("\(theme.id)-\(frame).png"))
        }
    }
    try pipe.fileHandleForWriting.close()
    ffmpeg.waitUntilExit()
    print(String(format: "%@: sim %.2f ms/frame, gpu %.2f ms/frame -> %@", theme.id,
                 simulationTime * 1000 / Double(frameCount), renderTime * 1000 / Double(frameCount), videoURL.path))
}
