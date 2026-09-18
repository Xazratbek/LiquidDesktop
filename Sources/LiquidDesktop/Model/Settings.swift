import Foundation
import Combine

/// UserDefaults-backed preferences; the single source of truth for both the
/// live effect and the Settings window.
final class Settings: ObservableObject {
    static let shared = Settings()

    enum Quality: String, CaseIterable, Identifiable {
        case automatic, high, efficient
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .high: return "High"
            case .efficient: return "Battery Saver"
            }
        }
    }

    private enum Key {
        static let waterVisible = "waterVisible"
        static let themeID = "themeID"
        static let waterAmount = "waterAmount"
        static let tiltSensitivity = "tiltSensitivity"
        static let waveEnergy = "waveEnergy"
        static let cursorStirs = "cursorStirs"
        static let lidControl = "lidControl"
        static let quality = "quality"
        static let pauseOnBattery = "pauseOnBattery"
        static let hasOnboarded = "hasOnboarded"
    }

    private let defaults = UserDefaults.standard

    @Published var waterVisible: Bool { didSet { defaults.set(waterVisible, forKey: Key.waterVisible) } }
    @Published var themeID: String { didSet { defaults.set(themeID, forKey: Key.themeID) } }
    /// 0.4…1.6, scales how much water there is.
    @Published var waterAmount: Double { didSet { defaults.set(waterAmount, forKey: Key.waterAmount) } }
    /// 0…1: how far the screen must tilt back for the water to spread fully.
    @Published var tiltSensitivity: Double { didSet { defaults.set(tiltSensitivity, forKey: Key.tiltSensitivity) } }
    /// 0.3…2, how lively waves and splashes are.
    @Published var waveEnergy: Double { didSet { defaults.set(waveEnergy, forKey: Key.waveEnergy) } }
    @Published var cursorStirs: Bool { didSet { defaults.set(cursorStirs, forKey: Key.cursorStirs) } }
    @Published var lidControl: Bool { didSet { defaults.set(lidControl, forKey: Key.lidControl) } }
    @Published var quality: Quality { didSet { defaults.set(quality.rawValue, forKey: Key.quality) } }
    @Published var pauseOnBattery: Bool { didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) } }
    @Published var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }

    var theme: LiquidTheme { LiquidTheme.named(themeID) }

    var lidMapping: LidMapping {
        var mapping = LidMapping()
        mapping.reclinedAngle = 165 - tiltSensitivity * 50
        mapping.lowLevel = min(0.14 * waterAmount, 0.3)
        mapping.highLevel = min(0.46 * waterAmount, Tank.maxLevel - 0.02)
        return mapping
    }

    func resetToDefaults() {
        for key in [Key.themeID, Key.waterAmount, Key.tiltSensitivity, Key.waveEnergy,
                    Key.cursorStirs, Key.lidControl, Key.quality, Key.pauseOnBattery] {
            defaults.removeObject(forKey: key)
        }
        load()
    }

    private init() {
        defaults.register(defaults: [
            Key.waterVisible: true,
            Key.themeID: LiquidTheme.clear.id,
            Key.waterAmount: 1.0,
            Key.tiltSensitivity: 0.5,
            Key.waveEnergy: 1.0,
            Key.cursorStirs: true,
            Key.lidControl: true,
            Key.quality: Quality.automatic.rawValue,
            Key.pauseOnBattery: false,
            Key.hasOnboarded: false,
        ])
        waterVisible = true
        themeID = LiquidTheme.clear.id
        waterAmount = 1
        tiltSensitivity = 0.5
        waveEnergy = 1
        cursorStirs = true
        lidControl = true
        quality = .automatic
        pauseOnBattery = false
        hasOnboarded = false
        load()
    }

    private func load() {
        waterVisible = defaults.bool(forKey: Key.waterVisible)
        themeID = defaults.string(forKey: Key.themeID) ?? LiquidTheme.clear.id
        waterAmount = defaults.double(forKey: Key.waterAmount)
        tiltSensitivity = defaults.double(forKey: Key.tiltSensitivity)
        waveEnergy = defaults.double(forKey: Key.waveEnergy)
        cursorStirs = defaults.bool(forKey: Key.cursorStirs)
        lidControl = defaults.bool(forKey: Key.lidControl)
        quality = Quality(rawValue: defaults.string(forKey: Key.quality) ?? "") ?? .automatic
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
    }
}
