import Foundation
import simd

/// How the liquid looks and, to a lesser degree, how it moves.
struct LiquidTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let blurb: String

    /// Per-channel light that survives a trip through the liquid.
    var transmission: SIMD3<Float>
    /// Colour the liquid scatters back as it gets deeper.
    var deep: SIMD3<Float>
    /// Highlight colour for the surface line, caustics and splashes.
    var glow: SIMD3<Float>
    var absorption: Float
    /// Refraction offset at the surface, in simulation cells.
    var refraction: Float
    var depthBlur: Float
    var caustics: Float
    var specular: Float
    var metallic: Float
    var emissive: Float
    /// Coverage when no live screen image is available to refract.
    var fallbackOpacity: Float
    /// Lower values make the liquid feel thicker.
    var flipRatio: Float
    var gravityScale: Float

    static let clear = LiquidTheme(
        id: "clear", name: "Clear Water",
        blurb: "Crystal clear, soft caustics.",
        transmission: SIMD3(0.70, 0.90, 1.00), deep: SIMD3(0.03, 0.22, 0.34),
        glow: SIMD3(0.85, 0.97, 1.00),
        absorption: 1.6, refraction: 0.9, depthBlur: 0.3, caustics: 0.35, specular: 0.9,
        metallic: 0, emissive: 0, fallbackOpacity: 0.42, flipRatio: 0.92, gravityScale: 1
    )

    static let lagoon = LiquidTheme(
        id: "lagoon", name: "Lagoon",
        blurb: "Bright tropical turquoise.",
        transmission: SIMD3(0.40, 0.96, 0.90), deep: SIMD3(0.00, 0.40, 0.44),
        glow: SIMD3(0.80, 1.00, 0.95),
        absorption: 2.4, refraction: 1.0, depthBlur: 0.45, caustics: 0.4, specular: 1.0,
        metallic: 0, emissive: 0, fallbackOpacity: 0.55, flipRatio: 0.93, gravityScale: 1
    )

    static let mercury = LiquidTheme(
        id: "mercury", name: "Mercury",
        blurb: "Chrome that mirrors your screen.",
        transmission: SIMD3(0.92, 0.94, 0.97), deep: SIMD3(0.10, 0.11, 0.13),
        glow: SIMD3(1.00, 1.00, 1.00),
        absorption: 0, refraction: 1.2, depthBlur: 0, caustics: 0, specular: 1.4,
        metallic: 1, emissive: 0, fallbackOpacity: 1, flipRatio: 0.85, gravityScale: 1.25
    )

    static let lava = LiquidTheme(
        id: "lava", name: "Lava",
        blurb: "Slow glowing magma.",
        transmission: SIMD3(1.00, 0.45, 0.10), deep: SIMD3(0.16, 0.02, 0.01),
        glow: SIMD3(1.00, 0.55, 0.12),
        absorption: 0, refraction: 0.5, depthBlur: 0, caustics: 1, specular: 0.5,
        metallic: 0, emissive: 1, fallbackOpacity: 1, flipRatio: 0.7, gravityScale: 0.8
    )

    static let all: [LiquidTheme] = [.clear, .lagoon, .mercury, .lava]

    static func named(_ id: String) -> LiquidTheme {
        all.first { $0.id == id } ?? .clear
    }
}
