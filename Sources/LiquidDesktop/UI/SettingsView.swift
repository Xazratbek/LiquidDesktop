import SwiftUI
import Combine

@MainActor
final class SettingsModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case liquid = "Liquid"
        case motion = "Motion"
        case general = "General"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .liquid: return "drop.fill"
            case .motion: return "water.waves"
            case .general: return "gearshape.fill"
            }
        }
    }

    let controller: LiquidController
    let openPermission: () -> Void
    @Published var tab: Tab = .liquid
    @Published var needsPermission = false
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    private var cancellables = Set<AnyCancellable>()

    init(controller: LiquidController, openPermission: @escaping () -> Void) {
        self.controller = controller
        self.openPermission = openPermission
        controller.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            hero
            tabBar
                .padding(.top, 14)
                .padding(.bottom, 12)
            Group {
                switch model.tab {
                case .liquid: liquidTab
                case .motion: motionTab
                case .general: generalTab
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(width: 620, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Brand.accent)
        .ignoresSafeArea()
    }

    // MARK: Hero

    private var mappedLevel: Double {
        let mapping = settings.lidMapping
        return settings.lidControl ? mapping.level(for: model.controller.liveAngle) : mapping.lowLevel
    }

    private var previewLevel: Double {
        settings.waterVisible ? mappedLevel : 0.1
    }

    private var hero: some View {
        LiquidPreview(theme: settings.theme, level: previewLevel, energy: settings.waterVisible ? settings.waveEnergy : 0.3)
            .frame(height: 216)
            .overlay(
                LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Liquid Desktop")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                        Text(statusText)
                            .font(.system(size: 12.5, weight: .medium))
                            .opacity(0.9)
                    }
                    Spacer()
                    fillSwitch
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 5, y: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            .overlay(alignment: .topTrailing) {
                if model.controller.hasSensor {
                    Label(String(format: "%.0f°", model.controller.liveAngle), systemImage: "laptopcomputer")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.28)))
                        .padding(14)
                }
            }
    }

    private var fillSwitch: some View {
        Button {
            settings.waterVisible.toggle()
        } label: {
            Label(settings.waterVisible ? "Drain" : "Fill", systemImage: settings.waterVisible ? "drop.fill" : "drop")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.22)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .help("Fill or drain the water (⌃⌥⌘L)")
    }

    private var statusText: String {
        switch model.controller.status {
        case .running: return "Flowing over your desktop"
        case .draining: return "Draining…"
        case .idle: return settings.waterVisible ? "Paused" : "Drained"
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsModel.Tab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .foregroundStyle(model.tab == tab ? Color.white : Color.primary.opacity(0.75))
                        .background(
                            Capsule().fill(model.tab == tab ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.clear))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: Tabs

    private var liquidTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.needsPermission { permissionBanner }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(LiquidTheme.all) { theme in themeCard(theme) }
            }
            SettingGroup {
                SettingRow(icon: "drop.halffull", colors: [.cyan, .blue], title: "Amount of water",
                           subtitle: "How much of the screen the water can cover") {
                    CaptionedSlider(value: $settings.waterAmount, range: 0.4...1.3, low: "Less", high: "More")
                }
            }
        }
    }

    private func themeCard(_ theme: LiquidTheme) -> some View {
        let selected = theme.id == settings.themeID
        return Button {
            settings.themeID = theme.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                LiquidPreview(theme: theme, level: 0.52, energy: selected ? 1 : 0.6)
                    .frame(height: 92)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Brand.accent)
                                .padding(8)
                                .shadow(radius: 2)
                        }
                    }
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name).font(.system(size: 13, weight: .semibold))
                        Text(theme.blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(Color.primary.opacity(selected ? 0.07 : 0.035))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)),
                                  lineWidth: selected ? 2.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var motionTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                LidGauge(angle: model.controller.liveAngle, level: mappedLevel, hasSensor: model.controller.hasSensor)
                    .frame(width: 190, height: 128)
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.controller.hasSensor ? "Tilt to pour" : "No lid sensor")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(model.controller.hasSensor
                         ? "Lean the screen back and the water climbs the glass. Bring it upright and it pools. Rock it quickly for waves and splashes."
                         : "This Mac can’t report its lid angle. The water still flows and splashes — press ⌃⌥⌘K.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Water follows the lid", isOn: $settings.lidControl)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!model.controller.hasSensor)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))

            SettingGroup {
                SettingRow(icon: "angle", colors: [.purple, .indigo], title: "Tilt response",
                           subtitle: "How far you tilt before the water spreads") {
                    CaptionedSlider(value: $settings.tiltSensitivity, range: 0...1, low: "Gentle", high: "Quick")
                }
                .disabled(!settings.lidControl || !model.controller.hasSensor)
                RowDivider()
                SettingRow(icon: "water.waves", colors: [.teal, .blue], title: "Waves",
                           subtitle: "Energy of waves and splashes") {
                    CaptionedSlider(value: $settings.waveEnergy, range: 0.3...2, low: "Calm", high: "Wild")
                }
                RowDivider()
                SettingRow(icon: "cursorarrow.motionlines", colors: [.pink, .red], title: "Pointer stirs the water",
                           subtitle: "Drag the pointer through the water to make ripples") {
                    Toggle("", isOn: $settings.cursorStirs).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingGroup {
                SettingRow(icon: "power", colors: [.green, .mint.opacity(0.9)], title: "Open at login") {
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { _ in model.toggleLaunchAtLogin() }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                RowDivider()
                SettingRow(icon: "record.circle", colors: [.orange, .red], title: "Screen Recording",
                           subtitle: model.needsPermission ? "Needed to bend your desktop through the water"
                                                           : "Allowed — frames never leave the GPU") {
                    if model.needsPermission {
                        Button("Allow…") { model.openPermission() }
                            .buttonStyle(GradientButtonStyle())
                    } else {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 17))
                    }
                }
                RowDivider()
                SettingRow(icon: "speedometer", colors: [.blue, .indigo], title: "Quality") {
                    Picker("", selection: $settings.quality) {
                        ForEach(Settings.Quality.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                RowDivider()
                SettingRow(icon: "battery.50", colors: [.yellow, .orange], title: "Drain on battery",
                           subtitle: "Hide the water automatically when unplugged") {
                    Toggle("", isOn: $settings.pauseOnBattery).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }

            SettingGroup {
                ForEach(Array(HotKeys.Action.allCases.enumerated()), id: \.offset) { index, action in
                    if index > 0 { RowDivider() }
                    SettingRow(icon: shortcutIcon(action), colors: [Color(white: 0.55), Color(white: 0.35)], title: action.title) {
                        KeyCaps(text: action.shortcut.display)
                    }
                }
            }

            HStack(spacing: 14) {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") · Everything stays on your Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Acknowledgements") {
                    if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                Button("Reset to Defaults") { settings.resetToDefaults() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 4)
        }
    }

    private func shortcutIcon(_ action: HotKeys.Action) -> String {
        switch action {
        case .toggleWater: return "drop"
        case .splash: return "sparkles"
        case .nextTheme: return "paintpalette"
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "exclamationmark", colors: [.orange, .red])
            VStack(alignment: .leading, spacing: 1) {
                Text("Allow Screen Recording for real refraction").font(.system(size: 13, weight: .semibold))
                Text("Until then the liquid can’t bend what’s underneath.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow…") { model.openPermission() }
                .buttonStyle(GradientButtonStyle(colors: [.orange, .red]))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

/// Side view of the laptop with the live lid angle and the water it produces.
struct LidGauge: View {
    let angle: Double
    let level: Double
    let hasSensor: Bool

    var body: some View {
        Canvas { context, size in
            let hinge = CGPoint(x: size.width * 0.34, y: size.height - 12)
            var base = Path()
            base.move(to: hinge)
            base.addLine(to: CGPoint(x: hinge.x + size.width * 0.58, y: hinge.y))
            context.stroke(base, with: .color(.secondary.opacity(0.8)), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            let lidLength = size.height * 0.88
            let radians = (180 - angle) * .pi / 180
            let direction = CGPoint(x: -cos(radians), y: -sin(radians))
            let tip = CGPoint(x: hinge.x + direction.x * lidLength, y: hinge.y + direction.y * lidLength)

            var arc = Path()
            arc.addArc(center: hinge, radius: 34, startAngle: .degrees(0), endAngle: .degrees(-angle), clockwise: true)
            context.stroke(arc, with: .color(Brand.accent.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))

            let fill = CGPoint(x: hinge.x + direction.x * lidLength * max(level, 0),
                               y: hinge.y + direction.y * lidLength * max(level, 0))
            var water = Path()
            water.move(to: hinge)
            water.addLine(to: fill)
            var glow = context
            glow.addFilter(.shadow(color: Brand.accent.opacity(0.8), radius: 6))
            glow.stroke(water, with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.4, blue: 0.95), .cyan]),
                                                    startPoint: hinge, endPoint: fill),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
            var lid = Path()
            lid.move(to: hinge)
            lid.addLine(to: tip)
            context.stroke(lid, with: .color(.primary.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            context.draw(Text(hasSensor ? String(format: "%.0f°", angle) : "—")
                            .font(.system(size: 30, weight: .heavy, design: .rounded)),
                         at: CGPoint(x: size.width - 38, y: 24))
            context.draw(Text(String(format: "%.0f%% full", max(level, 0) * 100))
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary),
                         at: CGPoint(x: size.width - 38, y: 52))
        }
    }
}
