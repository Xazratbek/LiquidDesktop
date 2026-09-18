import SwiftUI

enum Brand {
    static let accent = Color(red: 0.20, green: 0.56, blue: 1.0)
    static let accentDeep = Color(red: 0.36, green: 0.30, blue: 0.95)
    static let gradient = LinearGradient(colors: [Color(red: 0.25, green: 0.72, blue: 1.0), Color(red: 0.42, green: 0.33, blue: 0.98)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension SIMD3 where Scalar == Float {
    var color: Color { Color(red: Double(x), green: Double(y), blue: Double(z)) }
}

/// A painted, animated impression of the liquid over a little desktop. Used
/// as the hero in the panel, Settings and onboarding, and in theme cards.
struct LiquidPreview: View {
    let theme: LiquidTheme
    var level: Double = 0.42
    var showsDesktop = true
    var energy: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time t: Double) {
        let bounds = CGRect(origin: .zero, size: size)
        let scale = max(size.width / 320, 0.35)

        // Wallpaper and a couple of windows to refract.
        context.fill(Path(bounds), with: .linearGradient(
            Gradient(colors: [Color(red: 0.30, green: 0.27, blue: 0.78), Color(red: 0.72, green: 0.38, blue: 0.80),
                              Color(red: 1.0, green: 0.62, blue: 0.52)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        let windows = [CGRect(x: size.width * 0.08, y: size.height * 0.16, width: size.width * 0.46, height: size.height * 0.62),
                       CGRect(x: size.width * 0.50, y: size.height * 0.30, width: size.width * 0.42, height: size.height * 0.56)]
        if showsDesktop {
            drawWindows(windows, in: &context, scale: scale, offset: .zero)
        }

        let surface = liquidPath(size: size, time: t)
        var liquid = context
        liquid.clip(to: surface.fill)

        if theme.metallic > 0 {
            drawMercury(in: &liquid, size: size, time: t, scale: scale)
        } else if theme.emissive > 0 {
            drawLava(in: &liquid, size: size, time: t, scale: scale)
        } else {
            drawWater(in: &liquid, size: size, time: t, scale: scale, windows: windows)
        }

        var crest = context
        crest.addFilter(.shadow(color: theme.glow.color.opacity(0.9), radius: 6 * scale))
        crest.stroke(surface.line, with: .color(theme.glow.color.opacity(0.95)),
                     style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
    }

    private func liquidPath(size: CGSize, time t: Double) -> (fill: Path, line: Path) {
        let base = size.height * (1 - min(max(level, 0.02), 0.98))
        let amplitude = size.height * 0.022 * energy
        var line = Path()
        var fill = Path()
        fill.move(to: CGPoint(x: 0, y: size.height))
        let step = max(size.width / 90, 1.5)
        for x in stride(from: 0.0, through: Double(size.width) + step, by: Double(step)) {
            let u = x / Double(size.width)
            let y = Double(base) + sin(u * 9.0 + t * 2.2) * Double(amplitude)
                + sin(u * 23.0 - t * 3.1) * Double(amplitude) * 0.35
                + sin(u * 4.0 - t * 0.9) * Double(amplitude) * 0.8
            let point = CGPoint(x: x, y: y)
            if x == 0 { line.move(to: point) } else { line.addLine(to: point) }
            fill.addLine(to: point)
        }
        fill.addLine(to: CGPoint(x: size.width + step, y: size.height))
        fill.closeSubpath()
        return (fill, line)
    }

    private func drawWindows(_ windows: [CGRect], in context: inout GraphicsContext, scale: CGFloat, offset: CGSize) {
        for (index, frame) in windows.enumerated() {
            let rect = frame.offsetBy(dx: offset.width, dy: offset.height)
            let shape = Path(roundedRect: rect, cornerRadius: 7 * scale)
            context.fill(shape, with: .color(.white.opacity(0.92)))
            for (i, color) in [Color.red, .yellow, .green].enumerated() {
                context.fill(Path(ellipseIn: CGRect(x: rect.minX + (7 + CGFloat(i) * 8) * scale, y: rect.minY + 6 * scale,
                                                    width: 5 * scale, height: 5 * scale)), with: .color(color.opacity(0.85)))
            }
            var y = rect.minY + 20 * scale
            var line = 0
            while y < rect.maxY - 8 * scale {
                let width = rect.width * (0.45 + 0.4 * abs(sin(Double(line * 7 + index * 3))))
                context.fill(Path(roundedRect: CGRect(x: rect.minX + 9 * scale, y: y, width: width - 18 * scale, height: 3.2 * scale),
                                  cornerRadius: 1.6 * scale),
                             with: .color(line % 4 == 0 ? Brand.accent.opacity(0.7) : Color.black.opacity(0.22)))
                y += 8.5 * scale
                line += 1
            }
        }
    }

    private func drawWater(in context: inout GraphicsContext, size: CGSize, time t: Double, scale: CGFloat, windows: [CGRect]) {
        let base = size.height * (1 - level)
        if showsDesktop {
            var refracted = context
            refracted.addFilter(.blur(radius: 0.8 * scale))
            drawWindows(windows, in: &refracted, scale: scale,
                        offset: CGSize(width: sin(t * 1.3) * 3 * scale, height: -4 * scale))
        }
        let body = theme.transmission * 0.55 + theme.deep * 0.45
        let vivid = Color(red: Double(body.x) * 0.55, green: Double(body.y) * 0.85, blue: min(Double(body.z) * 1.1, 1))
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: theme.transmission.color.opacity(0.45), location: 0),
                             .init(color: vivid.opacity(0.72), location: 0.35),
                             .init(color: theme.deep.color.opacity(0.95), location: 1)]),
            startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: size.height)))
        context.fill(Path(CGRect(x: 0, y: base, width: size.width, height: size.height * 0.08)),
                     with: .linearGradient(Gradient(colors: [theme.glow.color.opacity(0.35), .clear]),
                                           startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: base + size.height * 0.08)))

        for i in 0..<6 {
            var ribbon = Path()
            let y0 = base + CGFloat(i + 1) * size.height * 0.07
            for x in stride(from: 0.0, through: Double(size.width), by: 4) {
                let y = Double(y0) + sin(x / Double(28 * scale) + t * (0.8 + Double(i) * 0.15) + Double(i)) * Double(5 * scale)
                if x == 0 { ribbon.move(to: CGPoint(x: x, y: y)) } else { ribbon.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(ribbon, with: .color(theme.glow.color.opacity(0.16 - Double(i) * 0.02)), lineWidth: 2 * scale)
        }
        drawBubbles(in: &context, size: size, time: t, scale: scale, top: base, color: .white)
    }

    private func drawMercury(in context: inout GraphicsContext, size: CGSize, time t: Double, scale: CGFloat) {
        let base = size.height * (1 - level)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: Color(white: 0.96), location: 0),
                             .init(color: Color(white: 0.55), location: 0.18),
                             .init(color: Color(white: 0.86), location: 0.34),
                             .init(color: Color(white: 0.22), location: 0.62),
                             .init(color: Color(white: 0.45), location: 0.8),
                             .init(color: Color(white: 0.08), location: 1)]),
            startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: size.height)))
        for i in 0..<4 {
            var band = Path()
            let y0 = base + size.height * (0.08 + Double(i) * 0.1)
            for x in stride(from: 0.0, through: Double(size.width), by: 4) {
                let y = Double(y0) + sin(x / Double(40 * scale) + t * 1.1 + Double(i) * 2) * Double(4 * scale)
                if x == 0 { band.move(to: CGPoint(x: x, y: y)) } else { band.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(band, with: .color(.white.opacity(0.35)), lineWidth: 3 * scale)
        }
    }

    private func drawLava(in context: inout GraphicsContext, size: CGSize, time t: Double, scale: CGFloat) {
        let base = size.height * (1 - level)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: Color(red: 1, green: 0.62, blue: 0.16), location: 0),
                             .init(color: Color(red: 0.72, green: 0.10, blue: 0.02), location: 0.25),
                             .init(color: Color(red: 0.18, green: 0.02, blue: 0.01), location: 1)]),
            startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: size.height)))
        // Slowly drifting hot spots under the crust.
        for i in 0..<6 {
            let seed = Double(i) * 7.31
            let x = (sin(seed + t * 0.12) * 0.5 + 0.5) * Double(size.width)
            let y = Double(base) + (cos(seed * 1.7 + t * 0.09) * 0.5 + 0.5) * Double(size.height - base)
            let radius = Double(size.height) * (0.18 + 0.06 * sin(t * 0.8 + seed))
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.12).opacity(0.55), .clear]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }
        // Glowing veins in the crust.
        var veins = context
        veins.addFilter(.shadow(color: Color(red: 1, green: 0.45, blue: 0.08), radius: 3 * scale))
        for i in 0..<5 {
            var path = Path()
            let y0 = Double(base) + Double(size.height - base) * (0.2 + Double(i) * 0.17)
            let frequency = 0.018 + Double(i % 3) * 0.009
            for x in stride(from: 0.0, through: Double(size.width), by: 3) {
                let y = y0 + sin(x * frequency / Double(scale) + Double(i) * 2.1 + t * 0.25) * Double(9 * scale)
                    + sin(x * frequency * 2.7 / Double(scale) - t * 0.4) * Double(3 * scale)
                if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            let pulse = 0.45 + 0.35 * sin(t * 1.1 + Double(i) * 1.3)
            veins.stroke(path, with: .color(Color(red: 1, green: 0.72, blue: 0.3).opacity(pulse)), lineWidth: 1.3 * scale)
        }
        drawBubbles(in: &context, size: size, time: t, scale: scale, top: base, color: Color(red: 1, green: 0.8, blue: 0.4))
    }

    private func drawBubbles(in context: inout GraphicsContext, size: CGSize, time t: Double, scale: CGFloat, top: CGFloat, color: Color) {
        let depth = Double(size.height - top)
        guard depth > 10 else { return }
        for i in 0..<9 {
            let seed = Double(i) * 12.9898
            let x = (sin(seed) * 0.5 + 0.5) * Double(size.width)
            let rise = (t * (10 + Double(i % 4) * 6) * Double(scale) + seed * 37).truncatingRemainder(dividingBy: depth)
            let y = Double(size.height) - rise
            let r = Double(scale) * (1.4 + Double(i % 3))
            context.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                           with: .color(color.opacity(0.6)), lineWidth: 0.9 * scale)
        }
    }
}

/// Rounded, softly lit icon tile in the style of System Settings.
struct IconBadge: View {
    let systemName: String
    let colors: [Color]

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: colors.last?.opacity(0.35) ?? .clear, radius: 3, y: 1)
    }
}

/// One settings row: badge, title, optional subtitle, trailing control.
struct SettingRow<Trailing: View>: View {
    let icon: String
    let colors: [Color]
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, colors: colors)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
    }
}

/// A grouped card of rows with hairline separators.
struct SettingGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 52)
    }
}

/// Slider with captions on either end.
struct CaptionedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let low: String
    let high: String

    var body: some View {
        HStack(spacing: 8) {
            Text(low).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Slider(value: $value, in: range).controlSize(.small)
            Text(high).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(width: 230)
    }
}

/// Keyboard shortcut rendered as keycaps.
struct KeyCaps: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(text), id: \.self) { character in
                Text(String(character))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            }
        }
    }
}

/// Large pill button with a gradient fill.
struct GradientButtonStyle: ButtonStyle {
    var colors: [Color] = [Color(red: 0.25, green: 0.72, blue: 1.0), Color(red: 0.42, green: 0.33, blue: 0.98)]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
            .shadow(color: colors.last!.opacity(0.35), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Soft translucent tile button used in the menu bar panel.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
