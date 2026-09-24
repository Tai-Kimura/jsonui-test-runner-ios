import Foundation

/// How a text action gets keyboard focus onto a field before it types.
///
/// `XCUIElement.typeText` FAILS THE TEST — it does not throw — when neither
/// the element nor a descendant holds keyboard focus, and a tap that has
/// returned has not always delivered it. Measured on CI (conformance-mobile
/// run 35984839148, attempt 1): `input` on a TextField the driver had just
/// tapped failed with "Neither element nor any descendant has keyboard
/// focus", and the same inputs passed on the re-run. So focus is read before
/// typing instead of being assumed from the tap.
///
/// ⚠️ AND ONE READING IS NOT ENOUGH. Focus that is LEAVING reads as present
/// until it has left: with a return injected after the tap (it ends
/// editing), a reading taken 0.23s later said focused, and `typeText` 30ms
/// after that found none — 1 run of 4. So focus is taken only when it reads
/// present `stableReadings` times in a row, `poll` apart.
///
/// Pure over its four closures, so the policy is tested without a simulator.
struct FocusForTyping {
    /// How long one tap is given to deliver focus.
    var waitPerTap: TimeInterval = 1.5
    /// Taps after the caller's own tap, before giving up.
    var retaps: Int = 2
    var poll: TimeInterval = 0.05
    /// Consecutive readings of "focused" before typing.
    var stableReadings: Int = 2

    enum Outcome: Equatable {
        /// Focus is there; `retaps` extra taps were needed to get it.
        case focused(retaps: Int)
        /// This XCTest does not answer the question. The caller types as it
        /// always did, which is what happened before focus was read at all.
        case unreadable
        /// Never focused, after the caller's tap and `taps - 1` more.
        case failed(taps: Int)
    }

    /// `isFocused` returns nil when focus cannot be read.
    func run(isFocused: () -> Bool?, tap: () -> Void,
             sleep: (TimeInterval) -> Void, now: () -> Date) -> Outcome {
        for attempt in 0...retaps {
            if attempt > 0 { tap() }
            let deadline = now().addingTimeInterval(waitPerTap)
            var streak = 0
            while true {
                guard let focused = isFocused() else { return .unreadable }
                streak = focused ? streak + 1 : 0
                if streak >= stableReadings { return .focused(retaps: attempt) }
                if now() >= deadline { break }
                sleep(poll)
            }
        }
        return .failed(taps: retaps + 1)
    }

    /// The line a run prints for an outcome worth reading, or nil for the
    /// common case (focused by the caller's own tap), which prints nothing.
    func note(_ outcome: Outcome, action: String, id: String) -> String? {
        switch outcome {
        case .focused(retaps: 0):
            return nil
        case .focused(let retaps):
            return "\(action)(\(id)): keyboard focus arrived after \(retaps) re-tap\(retaps == 1 ? "" : "s")"
        case .unreadable:
            return "\(action)(\(id)): keyboard focus cannot be read on this XCTest — typing without checking"
        case .failed:
            return nil
        }
    }

    /// Why the action stops, for `.failed`. Names the field and what was
    /// tried, so the run says what XCTest's message would not: that the
    /// driver saw the missing focus and tapped again before giving up.
    func failureReason(_ outcome: Outcome, id: String) -> String? {
        guard case .failed(let taps) = outcome else { return nil }
        return "'\(id)' did not take keyboard focus after \(taps) taps "
            + "(\(waitPerTap)s each); typing now would fail with "
            + "\"Neither element nor any descendant has keyboard focus\""
    }
}
