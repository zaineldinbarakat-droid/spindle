import AppKit
import Carbon.HIToolbox

enum HotkeyAction: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable {
    case toggleHidden
    case showAll
    case search
    case zen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleHidden: return "Show / hide hidden items"
        case .showAll: return "Show everything (incl. Always Hidden)"
        case .search: return "Search menu bar items"
        case .zen: return "Zen mode"
        }
    }

    /// ⌃⌥⌘ chords: practically nothing else claims them, so the defaults can't
    /// silently steal a shortcut from another app.
    static let defaults: [HotkeyAction: KeyCombo] = [
        .toggleHidden: KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: KeyCombo.hyperish),
        .showAll: KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: KeyCombo.hyperish),
        .search: KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: KeyCombo.hyperish),
        .zen: KeyCombo(keyCode: UInt32(kVK_ANSI_Z), modifiers: KeyCombo.hyperish)
    ]
}

/// A key plus Carbon modifier flags.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let hyperish = UInt32(controlKey | optionKey | cmdKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From a key-down event in the recorder field.
    init?(event: NSEvent) {
        var mods: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        // A global shortcut with no modifier would eat that key everywhere.
        guard mods != 0 && mods != UInt32(shiftKey) else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = mods
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓"
        ]
        if let name = special[Int(code)] { return name }

        // Ask the current keyboard layout what this key types, so AZERTY users see "A"
        // where QWERTY users see "Q".
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "#\(code)"
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return "#\(code)"
            }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return "#\(code)" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

/// Registers system-wide shortcuts through Carbon's `RegisterEventHotKey`, which —
/// unlike a global key monitor — needs no Accessibility or Input Monitoring grant.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var handler: ((HotkeyAction) -> Void)?

    private var registered: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: HotkeyAction] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {}

    func register(_ combos: [HotkeyAction: KeyCombo]) {
        installHandlerOnce()
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        actionsByID.removeAll()

        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let combo = combos[action] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x534C5645), id: id)  // 'SLVE'
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
                actionsByID[id] = action
            }
        }
    }

    /// Suspends everything while the recorder field is listening, so pressing the
    /// current shortcut records it instead of firing it.
    func pause() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
    }

    private func installHandlerOnce() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in
                guard let action = HotkeyCenter.shared.actionsByID[id] else { return }
                HotkeyCenter.shared.handler?(action)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
