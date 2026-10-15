import Foundation

/// Tap a button that dismisses what it sits in, and check that it did.
///
/// `alertTap` used to tap the button the moment it existed and report
/// success. Measured 2026-10-15 on iPhone 17 / iOS 27.0 (the "Save
/// Password?" sheet after a sign-in, inside the app's own tree): the sheet's
/// "Not Now" existed at 3.2s and was tapped at once — the tap was lost while
/// the sheet was still being presented, and the sheet stayed. A second tap at
/// 4.2s, with the button hittable, closed it at 4.65s, and no other sheet
/// came in the next 20s. With one tap, `alertTap` returned OK and the next
/// step failed on the screen under the sheet.
///
/// So: wait for hittable, tap, and wait for the button to go. A button that
/// stays is tapped again while the step's budget lasts; a button that never
/// goes fails the step by name instead of passing it.
public struct DismissTapConfirm {
    public enum Outcome: Equatable {
        /// The button went away after this many taps (0: it went before a
        /// tap was made — something else dismissed it).
        case dismissed(taps: Int)
        /// Not hittable at all within the budget: no tap was made.
        case neverHittable
        /// Tapped this many times and it stayed.
        case stayed(taps: Int)
    }

    /// How long one tap is given to take the button away.
    public var settle: TimeInterval
    public var pollInterval: TimeInterval

    public init(settle: TimeInterval = 1.0, pollInterval: TimeInterval = 0.1) {
        self.settle = settle
        self.pollInterval = pollInterval
    }

    public func run(
        deadline: Date,
        exists: () -> Bool,
        hittable: () -> Bool,
        tap: () -> Void,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Outcome {
        var taps = 0
        while true {
            if !exists() { return .dismissed(taps: taps) }
            if hittable() {
                tap()
                taps += 1
                let until = now().addingTimeInterval(settle)
                while now() < until, exists() { sleep(pollInterval) }
                if !exists() { return .dismissed(taps: taps) }
            } else {
                sleep(pollInterval)
            }
            if now() >= deadline { return taps > 0 ? .stayed(taps: taps) : .neverHittable }
        }
    }
}
