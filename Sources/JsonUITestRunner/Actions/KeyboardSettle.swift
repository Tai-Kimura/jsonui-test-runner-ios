import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Wait for the keyboard to stop moving after typing before reading it.
///
/// Measured 2026-10-15 on iPhone 17 / iOS 27.0 (a SwiftUI login form, read
/// every ~0.1s from just after the password `input`): the keyboard's frame
/// sat below the 874pt window at y=918 — not visible — until 0.8s, was back
/// at y=590 from 0.9s, and the layout scrolled again with it until 1.5s,
/// moving the sign-in button from y=683 (hittable) to y=567 (under it). A
/// step reading the keyboard inside that gap got the wrong answer twice
/// over: `hideKeyboard` saw no keyboard and did nothing (2/2), and a
/// `scrollUntilVisible` read its target as clear just before the keyboard
/// came back over it.
///
/// A still reading is not enough by itself, because the gap is a still
/// reading too: "no keyboard" holds steadily for most of it. So "no
/// keyboard" is accepted only once `absentAfter` has passed since typing
/// ended, while a keyboard that is up is accepted as soon as it has held its
/// frame for `still`. `absentAfter` is 2s against a measured gap that ended
/// by 0.9s, so a slower machine has more than twice the room; what it costs
/// is up to 2s on a `hideKeyboard` that follows typing and finds no keyboard.
/// `budget` caps the wait whatever happens, so a keyboard that never
/// settles costs a bounded delay, not a hang — the step then reads whatever
/// is there, as it did before.
///
/// Only after typing: the wait is keyed to the last `input` / `typeText` /
/// `clear`, so a step that follows no typing reads the keyboard at once.
public struct KeyboardSettle {
    public struct Reading: Equatable {
        public var visible: Bool
        public var frame: CGRect
        public init(visible: Bool, frame: CGRect) {
            self.visible = visible
            self.frame = visible ? frame : .zero
        }
    }

    public enum Outcome: Equatable {
        /// No typing recent enough to wait for.
        case notAfterTyping
        /// The reading held: `visible` is what the caller should act on.
        case settled(visible: Bool, waited: TimeInterval)
        /// The budget ran out with the keyboard still moving.
        case budgetSpent(visible: Bool)
    }

    public var still: TimeInterval
    public var absentAfter: TimeInterval
    public var budget: TimeInterval
    public var pollInterval: TimeInterval

    public init(still: TimeInterval = 0.5, absentAfter: TimeInterval = 2.0,
                budget: TimeInterval = 4.0, pollInterval: TimeInterval = 0.1) {
        self.still = still
        self.absentAfter = absentAfter
        self.budget = budget
        self.pollInterval = pollInterval
    }

    public func run(
        typedAt: Date?,
        read: () -> Reading,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Outcome {
        guard let typedAt else { return .notAfterTyping }
        let start = now()
        // Typing long enough ago that the gap is over and a keyboard that is
        // up has had its `still` too.
        if start.timeIntervalSince(typedAt) >= absentAfter + budget { return .notAfterTyping }

        var last = read()
        var stableSince = now()
        while true {
            let t = now()
            let held = t.timeIntervalSince(stableSince)
            let sinceTyping = t.timeIntervalSince(typedAt)
            if held >= still, last.visible || sinceTyping >= absentAfter {
                return .settled(visible: last.visible, waited: t.timeIntervalSince(start))
            }
            if t.timeIntervalSince(start) >= budget {
                return .budgetSpent(visible: last.visible)
            }
            sleep(pollInterval)
            let next = read()
            if next != last {
                last = next
                stableSince = now()
            }
        }
    }
}
