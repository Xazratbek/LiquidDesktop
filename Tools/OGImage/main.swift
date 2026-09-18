import AppKit

// Renders the 1200×630 social sharing card from a hero still and the icon.
// usage: OGImage <background.jpg> <icon.png> <output.png>

let args = CommandLine.arguments
let width: CGFloat = 1200, height: CGFloat = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
NSColor(srgbRed: 0.027, green: 0.04, blue: 0.11, alpha: 1).setFill()
bounds.fill()
if let background = NSImage(contentsOfFile: args[1]) {
    let aspect = background.size.width / background.size.height
    let drawHeight = height * 1.05
    let drawWidth = drawHeight * aspect
    background.draw(in: NSRect(x: width - drawWidth * 0.78, y: -height * 0.08, width: drawWidth, height: drawHeight),
                    from: .zero, operation: .sourceOver, fraction: 1)
}
NSGradient(colors: [NSColor(srgbRed: 0.027, green: 0.04, blue: 0.11, alpha: 1),
                    NSColor(srgbRed: 0.027, green: 0.04, blue: 0.11, alpha: 0.85),
                    NSColor(srgbRed: 0.027, green: 0.04, blue: 0.11, alpha: 0)],
           atLocations: [0, 0.42, 0.72], colorSpace: .sRGB)!.draw(in: bounds, angle: 0)

if let icon = NSImage(contentsOfFile: args[2]) {
    icon.draw(in: NSRect(x: 64, y: 400, width: 140, height: 140))
}
func rounded(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}
("Your desktop," as NSString).draw(at: NSPoint(x: 72, y: 268), withAttributes: [.font: rounded(78), .foregroundColor: NSColor.white])
("underwater." as NSString).draw(at: NSPoint(x: 72, y: 180), withAttributes: [.font: rounded(78),
    .foregroundColor: NSColor(srgbRed: 0.35, green: 0.78, blue: 1, alpha: 1)])
("Liquid Desktop · real liquid physics for your MacBook" as NSString).draw(at: NSPoint(x: 76, y: 120), withAttributes: [
    .font: NSFont.systemFont(ofSize: 26, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.75)])
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
