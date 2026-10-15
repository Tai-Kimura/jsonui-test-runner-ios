import XCTest
@testable import JsonUITestRunner

/// The wait after typing (KeyboardSettle), on a fake clock. The timeline in
/// the first test is the incident's shape: the keyboard is up as typing
/// ends, leaves, and comes back about a second later.
final class KeyboardSettleTests: XCTestCase {
    private let keyboard = CGRect(x: 0, y: 590, width: 402, height: 226)

    /// Drives `run` against a scripted timeline: (from seconds after typing, reading).
    private func run(
        _ timeline: [(TimeInterval, KeyboardSettle.Reading)],
        startAfterTyping: TimeInterval = 0,
        typed: Bool = true,
        policy: KeyboardSettle = KeyboardSettle()
    ) -> KeyboardSettle.Outcome {
        let typedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        var clock = typedAt.addingTimeInterval(startAfterTyping)
        return policy.run(
            typedAt: typed ? typedAt : nil,
            read: {
                let t = clock.timeIntervalSince(typedAt)
                return timeline.last(where: { $0.0 <= t })!.1
            },
            sleep: { clock = clock.addingTimeInterval($0) },
            now: { clock }
        )
    }

    private var up: KeyboardSettle.Reading { .init(visible: true, frame: keyboard) }
    private var gone: KeyboardSettle.Reading { .init(visible: false, frame: .zero) }

    func testTheGapIsNotReadAsNoKeyboard() {
        // Up as typing ends, gone 0.3s later, back at 1.3s. Read at once,
        // the old step saw "gone" and did nothing.
        let outcome = run([(0, up), (0.3, gone), (1.3, up)])
        guard case .settled(let visible, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(visible, "the keyboard came back; the gap was taken for its absence")
    }

    func testAKeyboardThatReallyLeftIsReadAsGoneOnceTheGapIsOver() {
        let outcome = run([(0, up), (0.3, gone)])
        guard case .settled(false, let waited) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(waited, KeyboardSettle().absentAfter, accuracy: 0.001)
    }

    func testAKeyboardThatStaysUpIsAcceptedOnceItHoldsItsFrame() {
        let policy = KeyboardSettle()
        let outcome = run([(0, up)], startAfterTyping: 0, policy: policy)
        guard case .settled(true, let waited) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(waited, policy.still, accuracy: 0.001)
    }

    func testNoTypingMeansNoWait() {
        XCTAssertEqual(run([(0, gone)], typed: false), .notAfterTyping)
    }

    func testTypingLongAgoMeansNoWait() {
        let policy = KeyboardSettle()
        XCTAssertEqual(run([(0, gone)], startAfterTyping: policy.absentAfter + policy.budget, policy: policy),
                       .notAfterTyping)
    }

    func testAKeyboardThatNeverStopsMovingCostsTheBudgetNotAHang() {
        // Alternates every 0.2s — never still for 0.5s. Indexed, not built
        // from an accumulated float, which repeats readings.
        let timeline: [(TimeInterval, KeyboardSettle.Reading)] = (0..<100).map {
            (Double($0) * 0.2, $0 % 2 == 0 ? up : gone)
        }
        guard case .budgetSpent = run(timeline) else { return XCTFail("did not stop at the budget") }
    }

    func testAMovingFrameIsNotStill() {
        // The keyboard sliding in: up throughout, a different frame on every
        // reading until 0.6s, then at rest.
        var timeline: [(TimeInterval, KeyboardSettle.Reading)] = (0..<6).map {
            (Double($0) * 0.1, KeyboardSettle.Reading(visible: true, frame: keyboard.offsetBy(dx: 0, dy: CGFloat(120 - $0 * 20))))
        }
        timeline.append((0.6, up))
        let outcome = run(timeline)
        guard case .settled(true, let waited) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertGreaterThanOrEqual(waited, 0.6 + KeyboardSettle().still - 0.0001)
    }
}
