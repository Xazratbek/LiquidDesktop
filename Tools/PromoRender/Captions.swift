import AppKit
import Metal

/// Full-canvas text overlays rendered with AppKit into premultiplied BGRA
/// textures, so they composite exactly over the Metal frame.
enum Captions {
    static let highlight = NSColor(srgbRed: 0.45, green: 0.86, blue: 1.0, alpha: 1)

    static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func texture(device: MTLDevice, width: Int, height: Int, draw: (NSRect) -> Void) -> MTLTexture {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    /// A headline centred near the top; words wrapped in *asterisks* are
    /// coloured with the highlight colour.
    static func headline(device: MTLDevice, width: Int, height: Int, text: String, size: CGFloat, top: CGFloat) -> MTLTexture {
        texture(device: device, width: width, height: height) { bounds in
            let attributed = NSMutableAttributedString()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineHeightMultiple = 0.92
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
            shadow.shadowBlurRadius = size * 0.35
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.04)
            for (index, part) in text.components(separatedBy: "*").enumerated() {
                attributed.append(NSAttributedString(string: part, attributes: [
                    .font: roundedFont(size, .heavy),
                    .foregroundColor: index % 2 == 1 ? highlight : NSColor.white,
                    .paragraphStyle: paragraph,
                    .shadow: shadow,
                    .kern: -size * 0.01,
                ]))
            }
            let rect = NSRect(x: bounds.width * 0.06, y: 0, width: bounds.width * 0.88, height: bounds.height - top)
            let measured = attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
            attributed.draw(with: NSRect(x: rect.minX, y: bounds.height - top - measured.height,
                                         width: rect.width, height: measured.height),
                            options: [.usesLineFragmentOrigin])
        }
    }

    static func endCard(device: MTLDevice, width: Int, height: Int, icon: NSImage?) -> MTLTexture {
        texture(device: device, width: width, height: height) { bounds in
            NSColor(srgbRed: 0.02, green: 0.03, blue: 0.08, alpha: 0.78).setFill()
            bounds.fill()
            let scale = bounds.width / 1080
            let center = bounds.midX
            let iconSize = 300 * scale
            let iconY = bounds.midY + 150 * scale
            icon?.draw(in: NSRect(x: center - iconSize / 2, y: iconY, width: iconSize, height: iconSize))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            func line(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
                (text as NSString).draw(in: NSRect(x: 0, y: y, width: bounds.width, height: font.pointSize * 1.4),
                                        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
            }
            line("Liquid Desktop", font: roundedFont(96 * scale, .heavy), color: .white, y: iconY - 150 * scale)
            line("Real liquid physics for your MacBook", font: NSFont.systemFont(ofSize: 40 * scale, weight: .medium),
                 color: NSColor(white: 1, alpha: 0.8), y: iconY - 220 * scale)

            let pill = NSRect(x: center - 270 * scale, y: iconY - 400 * scale, width: 540 * scale, height: 110 * scale)
            let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
            NSGradient(colors: [NSColor(srgbRed: 0.25, green: 0.72, blue: 1, alpha: 1),
                                NSColor(srgbRed: 0.42, green: 0.33, blue: 0.98, alpha: 1)])!.draw(in: path, angle: 0)
            line("$2.99 · Link in bio", font: roundedFont(50 * scale, .bold), color: .white, y: pill.minY + 24 * scale)
        }
    }
}
