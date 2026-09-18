import AppKit
import Metal

/// A believable mock desktop (wallpaper, windows, Dock) for offscreen renders.
enum MockDesktop {
    static func image(width: Int, height: Int) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let s = CGFloat(width) / 1512

        if let wallpaper = NSImage(contentsOfFile: "/System/Library/Desktop Pictures/Sonoma.heic") {
            wallpaper.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSGradient(colors: [.systemIndigo, .systemPink, .systemOrange])!.draw(in: bounds, angle: 35)
        }

        NSColor(white: 0, alpha: 0.28).setFill()
        NSRect(x: 0, y: CGFloat(height) - 30 * s, width: CGFloat(width), height: 30 * s).fill()
        let menuFont = NSFont.systemFont(ofSize: 13 * s, weight: .semibold)
        ("  Finder     File     Edit     View     Go     Window     Help" as NSString).draw(
            at: NSPoint(x: 14 * s, y: CGFloat(height) - 22 * s),
            withAttributes: [.font: menuFont, .foregroundColor: NSColor.white])

        func window(_ frame: NSRect, title: String, lines: [String], accent: NSColor) {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 30 * s
            shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
            shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor(white: 0.97, alpha: 1).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 12 * s, yRadius: 12 * s).fill()
            NSGraphicsContext.restoreGraphicsState()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: frame.minX + (16 + CGFloat(i) * 20) * s,
                                            y: frame.maxY - 24 * s, width: 12 * s, height: 12 * s)).fill()
            }
            (title as NSString).draw(at: NSPoint(x: frame.minX + 90 * s, y: frame.maxY - 26 * s),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 13 * s, weight: .semibold),
                                                      .foregroundColor: NSColor(white: 0.2, alpha: 1)])
            let body = NSFont.systemFont(ofSize: 15 * s)
        for (index, line) in lines.enumerated() {
            let y = frame.maxY - (64 + CGFloat(index) * 30) * s
            guard y > frame.minY + 16 * s else { break }
            let isHeading = index == 0
            (line as NSString).draw(at: NSPoint(x: frame.minX + 24 * s, y: y), withAttributes: [
                .font: isHeading ? NSFont.systemFont(ofSize: 19 * s, weight: .bold) : body,
                .foregroundColor: isHeading ? accent : NSColor(white: 0.22, alpha: 1),
            ])
        }
    }
        window(NSRect(x: 120 * s, y: 250 * s, width: 700 * s, height: 560 * s), title: "Notes", lines: [
            "Weekend in Samarkand",
            "Book the morning train from Tashkent",
            "Registan at sunrise, before the crowds",
            "Lunch: plov at the old bazaar",
            "Shah-i-Zinda in the afternoon light",
            "Buy two ceramic plates for mum",
            "Evening walk along Tashkent Street",
            "Pack a charger and a light jacket",
            "Sunday: Ulugh Beg observatory",
            "Try the Samarkand bread before leaving",
            "Train back at 6:40 pm",
            "Send photos to the family group",
            "Plan the next trip: Bukhara in May",
            "Remember sunscreen this time",
            "Budget: keep it simple",
            "Leave early, travel light",
            "Ask Aziz for restaurant tips",
        ], accent: .systemOrange)
        window(NSRect(x: 760 * s, y: 120 * s, width: 620 * s, height: 480 * s), title: "Reading List", lines: [
            "Design notes for the new app",
            "Why water looks the way it does",
            "Light bends when it changes speed",
            "Surfaces catch the sky as highlights",
            "Deep water swallows red light first",
            "Caustics are light focused by waves",
            "A small tank sloshes faster than a big one",
            "Splashes need surface tension to hold",
            "Keep the interface calm and quiet",
            "Every detail should earn its place",
            "Ship it, then listen closely",
            "Make the first ten seconds count",
        ], accent: .systemBlue)

        let dock = NSRect(x: CGFloat(width) / 2 - 330 * s, y: 8 * s, width: 660 * s, height: 72 * s)
        NSColor(white: 1, alpha: 0.28).setFill()
        NSBezierPath(roundedRect: dock, xRadius: 22 * s, yRadius: 22 * s).fill()
        let icons: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .systemRed, .systemYellow, .systemIndigo, .systemMint]
        for (i, color) in icons.enumerated() {
            let rect = NSRect(x: dock.minX + (14 + CGFloat(i) * 64) * s, y: dock.minY + 10 * s, width: 52 * s, height: 52 * s)
            NSGradient(starting: color.highlight(withLevel: 0.35)!, ending: color)!.draw(
                in: NSBezierPath(roundedRect: rect, xRadius: 12 * s, yRadius: 12 * s), angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    static func texture(device: MTLDevice, width: Int, height: Int) -> MTLTexture {
        let image = self.image(width: width, height: height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }
}
