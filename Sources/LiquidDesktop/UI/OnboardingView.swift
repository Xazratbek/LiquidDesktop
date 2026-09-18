import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var state: ScreenPermission.State = .denied
    let hasSensor: Bool

    var onGranted: (() -> Void)?
    var onFinish: (() -> Void)?

    private var pollTimer: Timer?
    private var isChecking = false
    private var requestedOnce = false

    init(hasSensor: Bool) {
        self.hasSensor = hasSensor
    }

    func requestAccess() {
        if !requestedOnce {
            requestedOnce = true
            _ = ScreenPermission.requestFromSystemOnce()
        }
        ScreenPermission.openSystemSettings()
        startPolling()
    }

    func recheck() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let result = await ScreenPermission.check()
            let changed = result != self.state
            self.state = result
            self.isChecking = false
            if result == .granted && changed {
                self.stopPolling()
                self.onGranted?()
            }
        }
    }

    func startPolling() {
        recheck()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            LiquidPreview(theme: .lagoon, level: 0.46)
                .frame(height: 230)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your desktop, underwater.")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                        Text("Real liquid physics that moves with your MacBook’s lid.")
                            .font(.system(size: 13.5, weight: .medium))
                            .opacity(0.92)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .padding(24)
                }

            VStack(alignment: .leading, spacing: 18) {
                step(number: 1, icon: "record.circle", colors: [.orange, .red], title: "Let the water bend light",
                     detail: "Liquid Desktop refracts a live image of your screen through the water. macOS calls that Screen Recording. Nothing is recorded, saved or sent — frames go straight to the GPU and are thrown away.") {
                    permissionControl
                }
                step(number: 2, icon: "laptopcomputer", colors: [.purple, .indigo], title: model.hasSensor ? "Tilt your screen" : "No lid sensor on this Mac",
                     detail: model.hasSensor
                        ? "Lean the screen back and the water spreads up the glass. Bring it upright and it pools. Rock it and it splashes."
                        : "The water still flows, stirs under the pointer and splashes on command — it just won’t follow the lid.") {
                    EmptyView()
                }
                step(number: 3, icon: "command", colors: [Color(white: 0.55), Color(white: 0.35)], title: "Shortcuts",
                     detail: "Control the water from any app.") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(HotKeys.Action.allCases, id: \.rawValue) { action in
                            HStack(spacing: 10) {
                                KeyCaps(text: action.shortcut.display)
                                Text(action.title).font(.system(size: 12))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            HStack {
                Text("Lives in the menu bar — look for the drop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.state == .granted ? "Start Flowing" : "Continue Without Refraction") {
                    model.onFinish?()
                }
                .buttonStyle(GradientButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 560, height: 620)
        .ignoresSafeArea()
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    @ViewBuilder private var permissionControl: some View {
        switch model.state {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.semibold))
        case .denied:
            HStack {
                Button("Allow Screen Recording…") { model.requestAccess() }
                    .buttonStyle(GradientButtonStyle(colors: [.orange, .red]))
                Button("Relaunch") { ScreenPermission.relaunch() }
                    .help("macOS sometimes applies the permission only after a relaunch")
            }
        case .unavailable(let reason):
            Text(reason).font(.caption).foregroundStyle(.red)
        }
    }

    private func step<Accessory: View>(number: Int, icon: String, colors: [Color], title: String, detail: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: icon, colors: colors)
                .scaleEffect(1.15)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }
}
