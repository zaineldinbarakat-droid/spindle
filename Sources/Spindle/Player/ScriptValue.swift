import Foundation

extension String {
    /// Parses a number that AppleScript produced by coercing a real to text.
    ///
    /// That coercion uses the *system* decimal separator, so on a machine formatting
    /// numbers the German/French way a position of 42.5 seconds arrives as "42,5" and
    /// plain `Double(_:)` returns nil — which silently pins the playhead at zero.
    ///
    /// The reverse direction needs no such care: AppleScript source literals are always
    /// written with a period (`set player position to 42,5` is a syntax error), and
    /// Swift's interpolation of a `Double` always emits one.
    var appleScriptDouble: Double? {
        if let value = Double(self) { return value }

        // Coercion never inserts grouping separators, so the only separator present is
        // the decimal one. Normalising it to a period is enough.
        let normalized = replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized) { return value }

        // "missing value" and friends.
        return nil
    }
}
