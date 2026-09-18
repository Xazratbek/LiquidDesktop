import AppKit

// Renders the DMG window background (660×420 points) at a given scale:
// brand gradient sky, a gentle water band, title, and an arrow from the app
// icon slot to the Applications slot.
// usage: DMGBackground <output.png> <scale>

let output = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let width: CGFloat = 660
let height: CGFloat = 420

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let bounds = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [color(0x2A2780), color(0x6D48C9), color(0xD9679E), color(0xFFAE86)],
           atLocations: [0, 0.38, 0.78, 1], colorSpace: .sRGB)!.draw(in: bounds, angle: -70)
NSGradient(colors: [NSColor(white: 1, alpha: 0.28), NSColor(white: 1, alpha: 0)])!
    .draw(fromCenter: NSPoint(x: 330, y: 250), radius: 0, toCenter: NSPoint(x: 330, y: 250), radius: 300, options: [])

func wave(base: CGFloat, amplitude: CGFloat, length: CGFloat, phase: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 0, y: 0))
    var x: CGFloat = 0
    while x <= width {
        path.line(to: NSPoint(x: x, y: base + sin(x / length * .pi * 2 + phase) * amplitude
                                + sin(x / (length * 0.37) * .pi * 2 + phase * 2) * amplitude * 0.3))
        x += 2
    }
    path.line(to: NSPoint(x: width, y: 0))
    path.close()
    return path
}

color(0x9EE3FF, 0.35).setFill()
wave(base: 104, amplitude: 9, length: 300, phase: 1.3).fill()
let water = wave(base: 92, amplitude: 11, length: 360, phase: 0.2)
NSGraphicsContext.saveGraphicsState()
water.addClip()
NSGradient(colors: [color(0x49D3FF), color(0x157FEA), color(0x0A3A9E)], atLocations: [0, 0.4, 1],
           colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: width, height: 110), angle: -90)
NSGraphicsContext.restoreGraphicsState()
let crest = NSBezierPath()
var cx: CGFloat = 0
while cx <= width {
    let y = 92 + sin(cx / 360 * .pi * 2 + 0.2) * 11 + sin(cx / (360 * 0.37) * .pi * 2 + 0.4) * 11 * 0.3
    if cx == 0 { crest.move(to: NSPoint(x: cx, y: y)) } else { crest.line(to: NSPoint(x: cx, y: y)) }
    cx += 2
}
crest.lineWidth = 2.5
color(0xEFFCFF, 0.9).setStroke()
crest.stroke()
for (x, y, r) in [(90.0, 50.0, 5.0), (112.0, 30.0, 3.0), (560.0, 58.0, 4.0), (590.0, 36.0, 6.0)] {
    let bubble = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    bubble.lineWidth = 1.2
    NSColor(white: 1, alpha: 0.6).setStroke()
    bubble.stroke()
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
shadow.shadowBlurRadius = 6
shadow.shadowOffset = NSSize(width: 0, height: -1)
let titleFont = NSFont.systemFont(ofSize: 30, weight: .heavy)
let rounded = titleFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 30) } ?? titleFont
("Liquid Desktop" as NSString).draw(in: NSRect(x: 0, y: 352, width: width, height: 40), withAttributes: [
    .font: rounded, .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .shadow: shadow,
])
("Drag the app into Applications to install" as NSString).draw(in: NSRect(x: 0, y: 328, width: width, height: 22), withAttributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.88),
    .paragraphStyle: paragraph,
])

// Arrow between the icon slots (icons sit at x=180 and x=480, y=200 from top).
let arrowY: CGFloat = height - 200
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: arrowY))
arrow.curve(to: NSPoint(x: 392, y: arrowY), controlPoint1: NSPoint(x: 300, y: arrowY + 22), controlPoint2: NSPoint(x: 354, y: arrowY + 22))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
let dash: [CGFloat] = [2, 9]
arrow.setLineDash(dash, count: 2, phase: 0)
NSColor(white: 1, alpha: 0.9).setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 380, y: arrowY + 12))
head.line(to: NSPoint(x: 400, y: arrowY - 1))
head.line(to: NSPoint(x: 378, y: arrowY - 10))
head.lineWidth = 4
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
