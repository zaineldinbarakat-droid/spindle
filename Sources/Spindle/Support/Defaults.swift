import Foundation

/// Tiny typed wrapper over `UserDefaults`.
enum Defaults {
    enum Key: String {
        case openOnHover
        case showVisualizer
        case pinnedProvider
        case notchStyle
        case tintNotch
        case collapsedShowsCover
        case indicatorStyle
        case indicatorColorMode
        case indicatorCustomColor
        case indicatorBrightness
        case indicatorGlow
        case glassClarity
        case glassTinted
        case panelScale
        case panelWidth
        case panelHeight
        case panelCornerRadius
        case coverScale
        case notchMotion
        case closeDelay
        case panelWaves
        case liveWaves
        case waveIntensity
        case askedForAudio
        case coverGlow

        // Focus timer
        case focusMinutes
        case shortBreakMinutes
        case longBreakMinutes
        case sessionsBeforeLongBreak
        case autoStartNextPhase
        case pauseMusicOnBreak
        case resumeMusicOnFocus
        case peekNotchOnPhaseEnd

        // Desktop
        case recordWidgetVisible
        case turntableWidgetVisible
        case desktopBackdropVisible
        case fullScreenTimer
    }

    static func bool(_ key: Key, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key.rawValue) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }

    static func set(_ key: Key, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func int(_ key: Key, default fallback: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key.rawValue) != nil else { return fallback }
        return UserDefaults.standard.integer(forKey: key.rawValue)
    }

    static func set(_ key: Key, _ value: Int) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func double(_ key: Key, default fallback: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key.rawValue) != nil else { return fallback }
        return UserDefaults.standard.double(forKey: key.rawValue)
    }

    static func set(_ key: Key, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func string(_ key: Key) -> String? {
        UserDefaults.standard.string(forKey: key.rawValue)
    }

    static func set(_ key: Key, _ value: String?) {
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: key.rawValue)
        } else {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }
}
