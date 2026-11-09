import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What setSliderValue and the `value` assertion decide from numbers alone:
/// refusals before anything moves (the same sentences as the Android and web
/// drivers), how a slider's accessibility value reads, the tolerance, and
/// where each drag starts and ends.
///
/// XCUITest has no way to set a slider's value; a SwiftUI Slider moves only
/// under a finger. Measured 2026-11-09 (Xcode 27.2, iOS 27.2, iPhone 17,
/// `Slider(value:in:)` as sjui and the Dynamic converter emit it):
/// - `adjust(toNormalizedSliderPosition:)` lands up to 0.73 off on 1...10 and
///   5.5 off on 0...100, the error changes sign with the direction of the
///   move, and correcting by the error diverges. Outside 0...1 it raises.
/// - A drag moves the thumb only when it starts on the thumb, and then by the
///   drag's length less about 10pt, over the frame's whole width:
///   value change = (|dx| - 10) / frame.width * (max - min).
/// - With those 10pt added, one drag lands within 0.006 on 1...10 (0.06% of
///   the range), 0.048 on 0...100, 0.0009 on 0...1 — every time once a move
///   shorter than 60pt first steps 60pt away (short drags land anywhere).
/// - The accessibility value is "37%" when the range is 0...1 or 0...100 and
///   the number with three decimals and grouping otherwise ("9.003",
///   "1,000"). The bounds are not exposed.
public enum SliderPlan {
    /// Relative slack for two numbers that should be the same one.
    static let eps = 1e-6
    /// What a drag loses before the thumb follows (measured: 10pt).
    public static let slop: CGFloat = 10
    /// Moves shorter than this first step away (measured: shorter drags miss).
    public static let away: CGFloat = 60

    public static func same(_ a: Double, _ b: Double, scale: Double = 1) -> Bool {
        abs(a - b) <= eps * Swift.max(1, abs(scale))
    }

    // MARK: - Refusals (shared wording with Android and web)

    /// Why `value` cannot be put on a slider whose bounds are `min`...`max`,
    /// or nil. A declared range that is not the slider's is refused first.
    public static func refusal(id: String, value: Double, min: Double, max: Double,
                               declaredRange: [Double]? = nil, step: Double? = nil) -> String? {
        let span = max - min
        if let range = declaredRange {
            guard range.count == 2 else {
                return "setSliderValue '\(id)': range must be [minimum, maximum], got \(range.map(format))"
            }
            if !same(range[0], min, scale: span) || !same(range[1], max, scale: span) {
                return "setSliderValue '\(id)': the step declares range [\(format(range[0])), \(format(range[1]))]"
                    + " but the slider's own is [\(format(min)), \(format(max))]"
            }
        }
        if value < min && !same(value, min, scale: span) {
            return "setSliderValue '\(id)': \(format(value)) is below the slider's range [\(format(min)), \(format(max))];"
                + " the nearest value it can take is \(format(min))"
        }
        if value > max && !same(value, max, scale: span) {
            return "setSliderValue '\(id)': \(format(value)) is above the slider's range [\(format(min)), \(format(max))];"
                + " the nearest value it can take is \(format(max))"
        }
        if let step {
            guard step > 0 else { return "setSliderValue '\(id)': step must be greater than 0, got \(format(step))" }
            let k = (value - min) / step
            if !same(k, k.rounded()) {
                let below = min + (k + eps).rounded(.down) * step
                let above = Swift.min(below + step, max)
                return "setSliderValue '\(id)': \(format(value)) is not on the slider's steps"
                    + " (\(format(min)) + k * \(format(step))); the nearest values are \(format(below)) and \(format(above))"
            }
        }
        return nil
    }

    /// The tolerance a landed value is judged with: half the step, else 0.5%
    /// of the range.
    public static func tolerance(min: Double, max: Double, step: Double?) -> Double {
        if let step, step > 0 { return step / 2 }
        return (max - min) * 0.005
    }

    /// A number as a test author writes it: 9, 9.5, 0.123456, -2.5.
    public static func format(_ v: Double) -> String {
        guard v.isFinite else { return String(v) }
        if abs(v - v.rounded()) < 1e-9 { return String(Int64(v.rounded())) }
        var text = String(format: "%.12g", v)
        if text.contains("e") { text = String(v) }
        return text
    }

    // MARK: - Reading the accessibility value

    public enum Reading: Equatable {
        case number(Double)
        /// 0...100, as a percentage of the range
        case percent(Double)
    }

    /// "9.003", "-2.001", "1,000", "37%" (and the typographic minus).
    public static func parse(_ text: String) -> Reading? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        var percent = false
        if t.hasSuffix("%") { percent = true; t.removeLast(); t = t.trimmingCharacters(in: .whitespaces) }
        // Grouping commas ("1,000", "12,345.5"); a decimal point is a point.
        if t.range(of: #"^-?\d{1,3}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        guard let n = Double(t), n.isFinite else { return nil }
        return percent ? .percent(n) : .number(n)
    }

    /// The reading in the slider's units; a percentage needs the bounds.
    public static func value(of reading: Reading, min: Double?, max: Double?) -> Double? {
        switch reading {
        case .number(let n): return n
        case .percent(let p):
            guard let min, let max else { return nil }
            return min + p / 100 * (max - min)
        }
    }

    // MARK: - Drags

    public struct Drag: Equatable {
        public let from: CGFloat
        public let to: CGFloat
        /// A step away before a short move, not the move to the value.
        public let isStepAway: Bool
    }

    /// Where the thumb of a slider at `value` sits on its frame (the drag maps
    /// the frame's whole width to the range).
    public static func x(of value: Double, min: Double, max: Double, minX: CGFloat, width: CGFloat) -> CGFloat {
        minX + CGFloat((value - min) / (max - min)) * width
    }

    /// The next drag from `current` towards `target`. A move shorter than
    /// `away` steps away first, to the side with room; otherwise the drag
    /// starts on the thumb and ends `slop` past the target — past the frame's
    /// edge when the target is a bound, so the slider clamps there. Points
    /// stay inside `screenWidth`.
    public static func nextDrag(current: Double, target: Double, min: Double, max: Double,
                                minX: CGFloat, width: CGFloat, screenWidth: CGFloat) -> Drag {
        let maxX = minX + width
        let start = Swift.min(Swift.max(x(of: current, min: min, max: max, minX: minX, width: width), minX + 2), maxX - 2)
        let goal = x(of: target, min: min, max: max, minX: minX, width: width)
        let onScreen = { (v: CGFloat) in Swift.min(Swift.max(v, 1), screenWidth - 1) }
        if abs(goal - start) < away {
            let aside = goal - minX > width / 2 ? goal - away : goal + away
            let dir: CGFloat = aside >= start ? 1 : -1
            return Drag(from: start, to: onScreen(aside + dir * slop), isStepAway: true)
        }
        let dir: CGFloat = goal >= start ? 1 : -1
        if same(target, min, scale: max - min) { return Drag(from: start, to: onScreen(minX - slop - 4), isStepAway: false) }
        if same(target, max, scale: max - min) { return Drag(from: start, to: onScreen(maxX + slop + 4), isStepAway: false) }
        return Drag(from: start, to: onScreen(goal + dir * slop), isStepAway: false)
    }
}
