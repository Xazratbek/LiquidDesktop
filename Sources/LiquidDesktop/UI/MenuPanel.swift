import SwiftUI
import Combine

@MainActor
final class PanelModel: ObservableObject {
    let controller: LiquidController
    @Published var needsPermission = false
    /// Replaces the live status line; used when rendering marketing images.
    var statusOverride: String?
    var openSettings: () -> Void = {}
    var openPermission: () -> Void = {}
    var quit: () -> Void = {}
    private var cancellables = Set<AnyCancellable>()

    init(controller: LiquidController) {
        self.controller = controller
        controller.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

/// The popover shown from the menu bar drop.
struct MenuPanel: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var settings = Settings.shared

    private var level: Double {
        guard settings.waterVisible || model.statusOverride != nil else { return 0.1 }
        let mapping = settings.lidMapping
        return settings.lidControl ? mapping.level(for: model.controller.liveAngle) : mapping.lowLevel
    }

    var body: some View {
        VStack(spacing: 12) {
            hero
            if model.needsPermission { permissionRow }
            themes
            actions
        }
        .padding(12)
        .frame(width: 330)
        .tint(Brand.accent)
    }

    private var hero: some View {
        LiquidPreview(theme: settings.theme, level: level, energy: settings.waveEnergy)
            .frame(height: 158)
            .overlay(LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.4)],
                                    startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Liquid Desktop").font(.system(size: 16, weight: .heavy, design: .rounded))
                    Text(statusText).font(.system(size: 11, weight: .medium)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4)
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if model.controller.hasSensor {
                    Text(String(format: "%.0f°", model.controller.liveAngle))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.3)))
                        .padding(12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    settings.waterVisible.toggle()
                } label: {
                    Image(systemName: settings.waterVisible ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.25)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .help(settings.waterVisible ? "Drain the water" : "Fill with water")
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusText: String {
        if let override = model.statusOverride { return override }
        switch model.controller.status {
        case .running: return "Flowing · tilt your screen"
        case .draining: return "Draining…"
        case .idle: return settings.waterVisible ? "Paused" : "Drained"
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 10) {
            IconBadge(systemName: "exclamationmark", colors: [.orange, .red])
            Text("Allow Screen Recording so the water can bend your desktop.")
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Allow") { model.openPermission() }
                .buttonStyle(GradientButtonStyle(colors: [.orange, .red]))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    private var themes: some View {
        HStack(spacing: 8) {
            ForEach(LiquidTheme.all) { theme in
                let selected = theme.id == settings.themeID
                Button {
                    settings.themeID = theme.id
                } label: {
                    VStack(spacing: 5) {
                        LiquidPreview(theme: theme, level: 0.55, showsDesktop: false, energy: selected ? 1.2 : 0.5)
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(selected ? AnyShapeStyle(Brand.gradient)
                                                                    : AnyShapeStyle(Color.primary.opacity(0.1)),
                                                           lineWidth: selected ? 3 : 1))
                            .shadow(color: selected ? Brand.accent.opacity(0.35) : .clear, radius: 6, y: 2)
                        Text(theme.name)
                            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.controller.splash() } label: {
                    Label("Splash", systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TileButtonStyle())
                Button { model.openSettings() } label: {
                    Label("Settings", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TileButtonStyle())
                Button { model.quit() } label: {
                    Label("Quit", systemImage: "power").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TileButtonStyle())
            }
            HStack(spacing: 10) {
                shortcutHint("⌃⌥⌘L", "fill")
                shortcutHint("⌃⌥⌘K", "splash")
                shortcutHint("⌃⌥⌘T", "liquid")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func shortcutHint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(keys).font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
    }
}
