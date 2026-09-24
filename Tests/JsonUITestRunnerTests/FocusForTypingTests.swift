import XCTest
@testable import JsonUITestRunner

/// The policy `input` and `clear` follow before they type.
///
/// A fake clock and a scripted focus reading stand in for the simulator:
/// `sleep` advances the clock, and the reading is either a fixed sequence
/// (taken in order, the last one repeating) or a rule over what has happened
/// so far — so a case says when focus arrives in terms of taps and reads,
/// not in terms of how many 0.05s steps add up to 1.5s.
final class FocusForTypingTests: XCTestCase {

    private final class Script {
        var readings: [Bool?]
        var rule: ((Script) -> Bool?)?
        var taps = 0
        var reads = 0
        var clock = Date(timeIntervalSince1970: 0)
        init(_ readings: [Bool?]) { self.readings = readings }
        init(rule: @escaping (Script) -> Bool?) { self.readings = []; self.rule = rule }

        func run(_ policy: FocusForTyping) -> FocusForTyping.Outcome {
            policy.run(
                isFocused: {
                    reads += 1
                    if let rule = rule { return rule(self) }
                    return readings.count > 1 ? readings.removeFirst() : readings[0]
                },
                tap: { taps += 1 },
                sleep: { clock = clock.addingTimeInterval($0) },
                now: { clock })
        }
    }

    private let policy = FocusForTyping()

    func testFocusFromTheCallersTapNeedsNothingMoreAndPrintsNothing() {
        let script = Script([true])
        let outcome = script.run(policy)
        XCTAssertEqual(outcome, .focused(retaps: 0))
        XCTAssertEqual(script.taps, 0)
        XCTAssertNil(policy.note(outcome, action: "input", id: "target"))
    }

    func testFocusThatArrivesLateIsWaitedForNotReTapped() {
        // The CI shape: the tap has returned, focus has not arrived yet.
        let script = Script([false, false, false, true])
        let outcome = script.run(policy)
        XCTAssertEqual(outcome, .focused(retaps: 0))
        XCTAssertEqual(script.taps, 0)
    }

    func testFocusThatNeverComesFromTheFirstTapGetsOneMore() {
        // Focus only once the policy has tapped again.
        let script = Script(rule: { $0.taps >= 1 })
        let outcome = script.run(policy)
        XCTAssertEqual(outcome, .focused(retaps: 1))
        XCTAssertEqual(script.taps, 1)
        XCTAssertEqual(
            policy.note(outcome, action: "input", id: "target"),
            "input(target): keyboard focus arrived after 1 re-tap")
    }

    func testFocusThatNeverComesStopsWithTheDriversReason() {
        let script = Script([false])
        let outcome = script.run(policy)
        XCTAssertEqual(outcome, .failed(taps: 3))
        XCTAssertEqual(script.taps, 2)
        let reason = policy.failureReason(outcome, id: "target")
        XCTAssertEqual(
            reason,
            "'target' did not take keyboard focus after 3 taps (1.5s each); "
                + "typing now would fail with \"Neither element nor any "
                + "descendant has keyboard focus\"")
        // Bounded: three waits of 1.5s, not a spin.
        XCTAssertLessThanOrEqual(script.clock.timeIntervalSince1970, 4.5 + 0.05 * 3)
    }

    func testAnUnreadableFocusTypesAsBeforeAndSaysSo() {
        let script = Script([nil])
        let outcome = script.run(policy)
        XCTAssertEqual(outcome, .unreadable)
        XCTAssertEqual(script.taps, 0)
        XCTAssertNil(policy.failureReason(outcome, id: "target"))
        XCTAssertEqual(
            policy.note(outcome, action: "clear", id: "target"),
            "clear(target): keyboard focus cannot be read on this XCTest — typing without checking")
    }

    func testAFocusThatLeavesRightAfterItIsReadIsNotTaken() {
        // The injected-return shape: one reading of "focused" on the way out,
        // then none until the field is tapped again.
        let script = Script(rule: { s in s.taps >= 1 ? true : (s.reads == 1) })
        let outcome = script.run(policy)
        XCTAssertEqual(outcome, .focused(retaps: 1))
        XCTAssertEqual(script.taps, 1)
    }

    // MARK: the controls

    func testASingleReadingWouldHaveTakenTheLeavingFocus() {
        // The same script under a policy that takes one reading: it types into
        // a field that is losing focus — the shape that went red 1 run in 4.
        var single = FocusForTyping()
        single.stableReadings = 1
        let script = Script(rule: { s in s.taps >= 1 ? true : (s.reads == 1) })
        XCTAssertEqual(script.run(single), .focused(retaps: 0))
        XCTAssertEqual(script.taps, 0)
    }

    func testWithoutTheWaitALateFocusCostsARetap() {
        // The same late-focus script under a policy that does not wait: it
        // re-taps where the real policy did not. So the arm above is green
        // because of the wait, not because the script happened to be kind.
        var noWait = FocusForTyping()
        noWait.waitPerTap = 0
        let script = Script([false, false, false, true])
        let outcome = script.run(noWait)
        XCTAssertNotEqual(outcome, .focused(retaps: 0))
        XCTAssertGreaterThan(script.taps, 0)
    }
}
