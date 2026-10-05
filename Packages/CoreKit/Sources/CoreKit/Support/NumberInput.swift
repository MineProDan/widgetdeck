import Foundation

/// Parses a number typed or pasted into a text field. `Double("nan")`, `Double("inf")` and
/// `Double("1e308")` all succeed, and one NaN poisons every average and progress bar it touches, so
/// every field goes through this instead: finite, within `range`, comma or point as the separator.
public enum NumberInput {
    public static func parse(_ text: String, in range: ClosedRange<Double> = 0...1_000_000) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }),
              let value = Double(cleaned), value.isFinite, range.contains(value) else { return nil }
        return value
    }
}
