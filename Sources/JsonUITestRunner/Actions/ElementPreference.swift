import XCTest

/// Which of several elements sharing an identifier a tap should go to.
///
/// The rule has not changed: an interactive type wins, in a fixed order of
/// preference, and only then a plain match. What changed is how the
/// candidates are gathered. Resolving one query per type meant nine full
/// query resolutions before the fallback, measured at 54–287ms per lookup
/// depending on the size of the hierarchy, against 4–13ms for a single
/// query (2026-09-04, iOS 26.4 simulator). A suite pays that once per tap,
/// doubleTap and longPress — 237 of them in one consumer's corpus, so
/// 13–68s across a run, while a single step never notices.
///
/// The order is kept explicitly rather than taken from tree order: with a
/// `.button` and a `.switch` both carrying the id, the per-type loop
/// returned the button because button was probed first, and that must stay
/// true however the tree is laid out.
public enum ElementPreference {

    /// Preferred first. A control is a better tap target than the label
    /// that mirrors it.
    public static let interactive: [XCUIElement.ElementType] = [
        .button, .switch, .toggle, .checkBox, .segmentedControl,
        .slider, .stepper, .link, .cell,
    ]

    /// Index into `types` of the candidate a tap should use, or nil when
    /// none of them is an interactive type. Ties on type go to the earlier
    /// candidate; different types go by the order above.
    public static func interactiveWinner(_ types: [XCUIElement.ElementType]) -> Int? {
        var best: (rank: Int, index: Int)?
        for (index, type) in types.enumerated() {
            guard let rank = interactive.firstIndex(of: type) else { continue }
            if best == nil || rank < best!.rank {
                best = (rank, index)
            }
        }
        return best?.index
    }
}
