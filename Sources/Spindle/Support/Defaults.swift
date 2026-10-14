import Foundation

/// Tiny typed wrapper over `UserDefaults`.
enum Defaults {
    enum Key: String {
        case openOnHover
        case showVisualizer
        case pinnedProvider
    }

    static func bool(_ key: Key, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key.rawValue) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }

    static func set(_ key: Key, _ value: Bool) {
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
