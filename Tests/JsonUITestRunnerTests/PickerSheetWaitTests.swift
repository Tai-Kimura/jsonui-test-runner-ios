import XCTest
@testable import JsonUITestRunner

/// The policy `selectOption` follows to wait for a SelectBox's picker sheet.
///
/// A fake clock stands in for the simulator: `sleep` advances it, and each
/// sheet "appears" or "becomes hittable" at a time the case chooses, so a case
/// says WHEN in seconds and the answer is deterministic.
final class PickerSheetWaitTests: XCTestCase {

    private final class Clock {
        var t: TimeInterval = 0
        var hittableReads = 0
        var now: Date { Date(timeIntervalSince1970: t) }
    }

    /// `appearAt[i]` / `hittableAt[i]`: seconds after the start, nil = never.
    private func run(_ wait: PickerSheetWait = PickerSheetWait(),
                     appearAt: [TimeInterval?], hittableAt: [TimeInterval?]? = nil,
                     budget: TimeInterval = 10, clock: Clock = Clock()) -> PickerSheetWait.Outcome {
        let hittable = hittableAt ?? appearAt
        return wait.run(
            exists: appearAt.map { at in { at.map { clock.t >= $0 } ?? false } },
            hittable: { i in
                clock.hittableReads += 1
                return hittable[i].map { clock.t >= $0 } ?? false
            },
            budget: budget,
            sleep: { clock.t += $0 },
            now: { clock.now })
    }

    func testAListPickerThatAppearsInTheSecondHalfIsTaken() {
        // The CI shape past 5s: the old waits had stopped looking at it by then.
        XCTAssertEqual(run(appearAt: [6, nil]), .ready(0))
    }

    func testTheDatePickerIsTakenWhenItIsTheOneThatAppears() {
        XCTAssertEqual(run(appearAt: [nil, 1]), .ready(1))
    }

    func testWhenBothAppearTheListPickerWins() {
        XCTAssertEqual(run(appearAt: [0, 0]), .ready(0))
    }

    func testASheetStillAnimatingInIsWaitedForNotSkipped() {
        let clock = Clock()
        XCTAssertEqual(run(appearAt: [0, nil], hittableAt: [0.5, nil], clock: clock), .ready(0))
        XCTAssertGreaterThan(clock.hittableReads, 1)
    }

    func testASheetThatNeverBecomesHittableStopsWithItsOwnReason() {
        let wait = PickerSheetWait()
        let outcome = run(wait, appearAt: [0, nil], hittableAt: [nil, nil])
        XCTAssertEqual(outcome, .neverHittable(0))
        XCTAssertEqual(wait.failureReason(outcome, budget: 10),
                       "Picker sheet appeared but never became hittable within 10000ms")
    }

    func testNothingAppearingStopsAtTheBudget() {
        let wait = PickerSheetWait()
        let clock = Clock()
        let outcome = run(wait, appearAt: [nil, nil], clock: clock)
        XCTAssertEqual(outcome, .notAppeared)
        XCTAssertEqual(wait.failureReason(outcome, budget: 10),
                       "Picker sheet did not appear within 10000ms")
        // A sum of 0.1s steps lands a hair under 10 (9.99999999999998); the
        // policy compares Dates, which round it to the deadline.
        XCTAssertGreaterThanOrEqual(clock.t, 10 - 1e-6)
        XCTAssertLessThanOrEqual(clock.t, 10 + wait.poll)
    }

    func testAReadySheetIsNoFailure() {
        XCTAssertNil(PickerSheetWait().failureReason(.ready(0), budget: 10))
    }

    // MARK: the control

    func testTheOldTwoWaitsMissTheSamePicker() {
        // The shape this replaced: the list picker for 5s, then the date
        // picker for 5s. The picker that appears at 6s lands in the second
        // wait, which is not looking at it — the same timeline the arm above
        // takes.
        let clock = Clock()
        let first = run(appearAt: [6], budget: 5, clock: clock)
        let second = run(appearAt: [nil], budget: 5, clock: clock)
        XCTAssertEqual(first, .notAppeared)
        XCTAssertEqual(second, .notAppeared)
        XCTAssertGreaterThanOrEqual(clock.t, 10 - 1e-6)   // the picker was up from 6s
    }
}
