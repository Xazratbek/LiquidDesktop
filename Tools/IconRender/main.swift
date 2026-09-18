import AppKit

// Renders the 1024×1024 app icon: a glossy glass tile, a sunset sky, deep
// water with a glowing crest, and a single sculpted droplet leaping out of
// the surface with its splash crown.

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linear(_ colors: [CGColor], _ locations: [CGFloat], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    cg.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ colors: [CGColor], _ locations: [CGFloat], center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow under the tile.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.45))
cg.addPath(tilePath)
cg.setFillColor(rgb(0x10143A))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(tilePath)
cg.clip()

// Sky.
linear([rgb(0x2B2A8C), rgb(0x7A4FD6), rgb(0xE0679E), rgb(0xFFB27A)], [0, 0.4, 0.78, 1],
       from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 470))
radial([rgb(0xFFE3B8, 0.9), rgb(0xFF9FA0, 0.35), rgb(0xFF9FA0, 0)], [0, 0.35, 1],
       center: CGPoint(x: 512, y: 520), radius: 360)

// A few soft stars.
for (x, y, r) in [(220.0, 830.0, 4.0), (330.0, 880.0, 3.0), (770.0, 850.0, 5.0), (860.0, 760.0, 3.0), (180.0, 720.0, 3.0)] {
    radial([rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)], [0, 1], center: CGPoint(x: x, y: y), radius: r * 3)
}

func surfaceY(_ x: CGFloat) -> CGFloat {
    470 + sin((x - 100) / 824 * .pi * 2 + 0.6) * 26 + sin((x - 100) / 824 * .pi * 5.2 + 1.9) * 10
}

func waterPath(offset: CGFloat = 0) -> CGMutablePath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 60, y: 60))
    var x: CGFloat = 60
    while x <= 964 {
        path.addLine(to: CGPoint(x: x, y: surfaceY(x) + offset))
        x += 3
    }
    path.addLine(to: CGPoint(x: 964, y: 60))
    path.closeSubpath()
    return path
}

// Far swell behind the main surface.
cg.saveGState()
let swell = CGMutablePath()
swell.move(to: CGPoint(x: 60, y: 300))
var sx: CGFloat = 60
while sx <= 964 {
    swell.addLine(to: CGPoint(x: sx, y: 492 + sin(sx / 90 + 2.4) * 16))
    sx += 3
}
swell.addLine(to: CGPoint(x: 964, y: 300))
swell.closeSubpath()
cg.addPath(swell)
cg.setFillColor(rgb(0x9AD9FF, 0.35))
cg.fillPath()
cg.restoreGState()

// Water body.
cg.saveGState()
cg.addPath(waterPath())
cg.clip()
linear([rgb(0x5FE3FF), rgb(0x1E9BF5), rgb(0x0D52C9), rgb(0x061F6E)], [0, 0.22, 0.6, 1],
       from: CGPoint(x: 512, y: 500), to: CGPoint(x: 512, y: 100))
// Light shaft through the water.
radial([rgb(0xB8F4FF, 0.45), rgb(0xB8F4FF, 0)], [0, 1], center: CGPoint(x: 512, y: 430), radius: 330)
// Caustic ribbons.
cg.setLineCap(.round)
for i in 0..<9 {
    let path = CGMutablePath()
    let y0 = 400 - CGFloat(i) * 34
    path.move(to: CGPoint(x: 60, y: y0))
    var x: CGFloat = 60
    while x <= 964 {
        path.addLine(to: CGPoint(x: x, y: y0 + sin(x / 47 + CGFloat(i) * 1.9) * 11 + sin(x / 19 + CGFloat(i)) * 4))
        x += 5
    }
    cg.addPath(path)
    cg.setStrokeColor(rgb(0xDFFBFF, 0.16 - CGFloat(i) * 0.013))
    cg.setLineWidth(6 - CGFloat(i) * 0.4)
    cg.strokePath()
}
// Bubbles.
for (x, y, r) in [(290.0, 300.0, 22.0), (330.0, 236.0, 14.0), (262.0, 196.0, 9.0), (736.0, 262.0, 17.0), (770.0, 330.0, 10.0)] {
    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
    cg.setFillColor(rgb(0xFFFFFF, 0.10))
    cg.fillEllipse(in: rect)
    cg.setStrokeColor(rgb(0xFFFFFF, 0.75))
    cg.setLineWidth(4)
    cg.strokeEllipse(in: rect)
    cg.setFillColor(rgb(0xFFFFFF, 0.9))
    cg.fillEllipse(in: CGRect(x: x - r * 0.45, y: y + r * 0.2, width: r * 0.42, height: r * 0.42))
}
cg.restoreGState()

// Crest: bright meniscus band along the surface.
let crest = CGMutablePath()
var cx: CGFloat = 60
crest.move(to: CGPoint(x: cx, y: surfaceY(cx)))
while cx <= 964 {
    crest.addLine(to: CGPoint(x: cx, y: surfaceY(cx)))
    cx += 3
}
cg.saveGState()
cg.setShadow(offset: .zero, blur: 18, color: rgb(0xB8F6FF, 0.9))
cg.addPath(crest)
cg.setStrokeColor(rgb(0xF2FDFF))
cg.setLineWidth(13)
cg.setLineCap(.round)
cg.strokePath()
cg.restoreGState()

// Splash crown where the droplet left the surface.
let crownCenter = CGPoint(x: 512, y: surfaceY(512) + 4)
cg.saveGState()
cg.setShadow(offset: .zero, blur: 10, color: rgb(0xC9F7FF, 0.8))
cg.setStrokeColor(rgb(0xF4FEFF, 0.95))
cg.setLineWidth(9)
cg.strokeEllipse(in: CGRect(x: crownCenter.x - 120, y: crownCenter.y - 22, width: 240, height: 44))
for (dx, height, radius) in [(-118.0, 52.0, 12.0), (-74.0, 78.0, 10.0), (80.0, 72.0, 11.0), (124.0, 46.0, 9.0)] {
    let base = CGPoint(x: crownCenter.x + dx, y: crownCenter.y + 8)
    let tip = CGPoint(x: base.x + dx * 0.25, y: base.y + height)
    let spike = CGMutablePath()
    spike.move(to: CGPoint(x: base.x - 10, y: base.y))
    spike.addQuadCurve(to: tip, control: CGPoint(x: base.x - 6, y: base.y + height * 0.6))
    spike.addQuadCurve(to: CGPoint(x: base.x + 10, y: base.y), control: CGPoint(x: base.x + 6, y: base.y + height * 0.6))
    spike.closeSubpath()
    cg.addPath(spike)
    cg.setFillColor(rgb(0xE8FCFF, 0.95))
    cg.fillPath()
    cg.setFillColor(rgb(0xFFFFFF))
    cg.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y + 6, width: radius * 2, height: radius * 2))
}
cg.restoreGState()

// The hero droplet.
let dropCenter = CGPoint(x: 512, y: 665)
let dropRadius: CGFloat = 96
let drop = CGMutablePath()
drop.move(to: CGPoint(x: dropCenter.x, y: dropCenter.y + dropRadius * 2.05))
drop.addCurve(to: CGPoint(x: dropCenter.x + dropRadius, y: dropCenter.y),
              control1: CGPoint(x: dropCenter.x + dropRadius * 0.28, y: dropCenter.y + dropRadius * 1.45),
              control2: CGPoint(x: dropCenter.x + dropRadius, y: dropCenter.y + dropRadius * 0.62))
drop.addArc(center: dropCenter, radius: dropRadius, startAngle: 0, endAngle: -.pi, clockwise: true)
drop.addCurve(to: CGPoint(x: dropCenter.x, y: dropCenter.y + dropRadius * 2.05),
              control1: CGPoint(x: dropCenter.x - dropRadius, y: dropCenter.y + dropRadius * 0.62),
              control2: CGPoint(x: dropCenter.x - dropRadius * 0.28, y: dropCenter.y + dropRadius * 1.45))
drop.closeSubpath()

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: rgb(0x0A1E6B, 0.55))
cg.addPath(drop)
cg.setFillColor(rgb(0x2BA8FF))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(drop)
cg.clip()
linear([rgb(0xA8F1FF), rgb(0x45C3FF), rgb(0x1478F0), rgb(0x0B3FB8)], [0, 0.3, 0.72, 1],
       from: CGPoint(x: 440, y: 950), to: CGPoint(x: 590, y: 580))
// Refracted sky glow in the lower belly of the drop.
radial([rgb(0xFFD6C2, 0.75), rgb(0xFFD6C2, 0)], [0, 1], center: CGPoint(x: 544, y: 604), radius: 80)
// Rim darkening for roundness.
cg.setStrokeColor(rgb(0x0A3294, 0.55))
cg.setLineWidth(22)
cg.addPath(drop)
cg.strokePath()
cg.restoreGState()

// Specular highlights.
cg.saveGState()
let highlight = CGMutablePath()
highlight.addArc(center: CGPoint(x: dropCenter.x - 6, y: dropCenter.y + 4), radius: 64,
                 startAngle: .pi * 0.62, endAngle: .pi * 0.98, clockwise: false)
cg.addPath(highlight)
cg.setStrokeColor(rgb(0xFFFFFF, 0.95))
cg.setLineWidth(17)
cg.setLineCap(.round)
cg.strokePath()
cg.setFillColor(rgb(0xFFFFFF, 0.95))
cg.fillEllipse(in: CGRect(x: dropCenter.x - 48, y: dropCenter.y + 74, width: 22, height: 22))
cg.restoreGState()

// Glass sheen and a subtle inner edge.
cg.saveGState()
let sheen = CGMutablePath()
sheen.move(to: CGPoint(x: 100, y: 924))
sheen.addLine(to: CGPoint(x: 100, y: 690))
sheen.addQuadCurve(to: CGPoint(x: 924, y: 860), control: CGPoint(x: 470, y: 760))
sheen.addLine(to: CGPoint(x: 924, y: 924))
sheen.closeSubpath()
cg.addPath(sheen)
cg.clip()
linear([rgb(0xFFFFFF, 0.20), rgb(0xFFFFFF, 0.0)], [0, 1], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 700))
cg.restoreGState()
cg.restoreGState()

cg.addPath(tilePath)
cg.setStrokeColor(rgb(0xFFFFFF, 0.22))
cg.setLineWidth(4)
cg.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
