import XCTest
@testable import JsonUITestRunner

/// The reasons an auto-waiting assertion gave while it waited (ReasonHistory),
/// and the failure pollUntil throws from them.
final class ReasonHistoryTests: XCTestCase {

    private let visibleFailure = AssertionError.assertionFailed(
        assertion: "visible", expected: "visible", actual: "does not exist for 'stand'")

    /// One reason, however many looks: no block, so the failure is the
    /// assertion's own message and nothing else.
    func testOneReasonAddsNoBlock() {
        var h = ReasonHistory()
        for i in 0...50 { h.observe("does not exist", at: Double(i) * 0.1) }
        XCTAssertNil(h.block(end: 5.0))
        XCTAssertEqual(
            visibleFailure.errorDescription,
            "Assertion 'visible' failed - Expected: visible, Actual: does not exist for 'stand'")
    }

    /// The reported sequence: below the fold, then removed.
    func testAChangedReasonListsBothInOrderUnderTheFirstLine() throws {
        var h = ReasonHistory()
        for i in 0..<21 { h.observe("not in the viewport", at: Double(i) * 0.1) }
        for i in 21...50 { h.observe("does not exist", at: Double(i) * 0.1) }
        let block = try XCTUnwrap(h.block(end: 5.0))
        XCTAssertEqual(
            AssertionError.timedOut(visibleFailure, history: block).errorDescription,
            [
                "Assertion 'visible' failed - Expected: visible, Actual: does not exist for 'stand'",
                "  waited 5.0s; the reason changed while waiting:",
                "    0.0–2.1s  not in the viewport",
                "    2.1–5.0s  does not exist",
            ].joined(separator: "\n"))
    }

    /// The wrapper is still an AssertionError, so FailureReason still files it
    /// as an assertion.
    func testTheWrappedFailureIsStillAnAssertion() {
        let error: Error = AssertionError.timedOut(visibleFailure, history: "x")
        XCTAssertTrue(error is AssertionError)
    }

    func testARoundTripIsNotFoldedAway() {
        var h = ReasonHistory()
        for (i, r) in ["A", "B", "B", "A"].enumerated() { h.observe(r, at: Double(i)) }
        XCTAssertEqual(h.segments.map(\.reason), ["A", "B", "A"])
    }

    func testFoldsOnTheFirstLine() {
        var h = ReasonHistory()
        h.observe("not found\n  probe 1", at: 0)
        h.observe("not found\n  probe 2", at: 0.1)
        XCTAssertEqual(h.segments, [ReasonHistory.Segment(reason: "not found", start: 0)])
    }

    func testAboveTheCapTheFirstThreeAndTheLastFourAreKept() {
        func at(_ n: Int) -> [ReasonHistory.Segment] {
            (0..<n).map { ReasonHistory.Segment(reason: "r\($0)", start: Double($0) * 0.1) }
        }
        // control: at the cap nothing is elided
        XCTAssertEqual(
            ReasonHistory.render(at(ReasonHistory.maxSegments), end: 1.0).split(separator: "\n").count,
            1 + ReasonHistory.maxSegments)
        XCTAssertEqual(
            ReasonHistory.render(at(ReasonHistory.maxSegments + 1), end: 1.0).split(separator: "\n").map(String.init),
            [
                "  waited 1.0s; the reason changed while waiting:",
                "    0.0–0.1s  r0",
                "    0.1–0.2s  r1",
                "    0.2–0.3s  r2",
                "    … 2 more",
                "    0.5–0.6s  r5",
                "    0.6–0.7s  r6",
                "    0.7–0.8s  r7",
                "    0.8–1.0s  r8",
            ])
    }
}
