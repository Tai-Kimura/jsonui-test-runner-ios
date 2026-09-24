import Foundation

/// How `selectOption` waits for the picker sheet a SelectBox presents.
///
/// It used to wait for the list picker for the whole step timeout, then for
/// the date picker for the whole step timeout again. So a list picker that
/// appeared after the first half was never seen — the second half watched
/// only the date picker — and every list selection also spent the date
/// picker's full timeout waiting for a sheet that was never coming (measured:
/// tap to Done 8.1s, the sheet itself up in 1.1s). conformance-mobile run
/// 36018309896 failed with "Picker sheet did not appear within 5000ms" on a
/// sheet that took 1.8s locally — in one of its two attempts; the other
/// passed on the same input.
///
/// Now both kinds are watched together for one budget, and the sheet that
/// appeared must also become hittable before anything is selected: a sheet
/// still animating in used to have its selection silently skipped.
///
/// Pure over its closures, so the policy is tested without a simulator.
struct PickerSheetWait {
    var poll: TimeInterval = 0.1

    enum Outcome: Equatable {
        /// The candidate at this index appeared and is hittable.
        case ready(Int)
        /// The candidate at this index appeared but never became hittable.
        case neverHittable(Int)
        /// No candidate appeared.
        case notAppeared
    }

    /// `exists` in preference order: when two appear together, the first wins.
    func run(exists: [() -> Bool], hittable: (Int) -> Bool, budget: TimeInterval,
             sleep: (TimeInterval) -> Void, now: () -> Date) -> Outcome {
        let deadline = now().addingTimeInterval(budget)
        var found: Int?
        while found == nil {
            found = exists.indices.first { exists[$0]() }
            if found != nil || now() >= deadline { break }
            sleep(poll)
        }
        guard let index = found else { return .notAppeared }
        while !hittable(index) {
            if now() >= deadline { return .neverHittable(index) }
            sleep(poll)
        }
        return .ready(index)
    }

    /// Why the step stops, or nil when it may go on.
    func failureReason(_ outcome: Outcome, budget: TimeInterval) -> String? {
        switch outcome {
        case .ready:
            return nil
        case .neverHittable:
            return "Picker sheet appeared but never became hittable within \(Int(budget * 1000))ms"
        case .notAppeared:
            return "Picker sheet did not appear within \(Int(budget * 1000))ms"
        }
    }
}
