import AppKit
import Carbon

/// System-wide keyboard shortcuts through Carbon hot keys, which need no
/// Accessibility or Input Monitoring permission.
final class HotKeys {
    struct Shortcut {
        let keyCode: Int
        let display: String
    }

    enum Action: UInt32, CaseIterable {
        case toggleWater = 1
        case splash = 2
        case nextTheme = 3

        var shortcut: Shortcut {
            switch self {
            case .toggleWater: return Shortcut(keyCode: kVK_ANSI_L, display: "⌃⌥⌘L")
            case .splash: return Shortcut(keyCode: kVK_ANSI_K, display: "⌃⌥⌘K")
            case .nextTheme: return Shortcut(keyCode: kVK_ANSI_T, display: "⌃⌥⌘T")
            }
        }

        var title: String {
            switch self {
            case .toggleWater: return "Show or drain the water"
            case .splash: return "Make a splash"
            case .nextTheme: return "Next liquid"
            }
        }
    }

    private static let signature = OSType(0x4C514454) // "LQDT"
    private static var active: HotKeys?

    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var onPress: ((Action) -> Void)?

    func arm(onPress: @escaping (Action) -> Void) {
        guard handler == nil else { return }
        self.onPress = onPress
        Self.active = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HotKeys.signature, let action = Action(rawValue: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { HotKeys.active?.onPress?(action) }
            return noErr
        }, 1, &spec, nil, &handler)

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for action in Action.allCases {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(UInt32(action.shortcut.keyCode), modifiers, id,
                                   GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                references.append(reference)
            }
        }
    }

    func disarm() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
        if Self.active === self { Self.active = nil }
    }

    deinit { disarm() }
}
