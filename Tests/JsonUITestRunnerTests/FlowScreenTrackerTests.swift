import XCTest
@testable import JsonUITestRunner

/// The flow's screen, `state`'s screen and the receipts it still owes
/// (FlowScreenTracker), with the two XCUITest operations recorded.
final class FlowScreenTrackerTests: XCTestCase {
    private struct Boom: Error {}

    private var verified: [String] = []
    private var waited: [String] = []
    private var failReceipt: Set<String> = []

    private func step(_ tracker: inout FlowScreenTracker, _ screen: String?, verify: Bool = true) throws {
        try tracker.enterStep(
            screen: screen,
            verifyScreens: verify,
            verify: { self.verified.append($0) },
            waitForReceipt: { screen, _ in
                self.waited.append(screen)
                if self.failReceipt.contains(screen) { throw Boom() }
            })
    }

    func testWithScreenChecksOffTheReceiptIsStillWaitedForAndTheScreenTracked() throws {
        var tracker = FlowScreenTracker()
        tracker.startFlow(pendingReceipts: ["login": "L1"])
        try step(&tracker, "login", verify: false)
        XCTAssertEqual(verified, [], "the implicit screen check is what `false` turns off")
        XCTAssertEqual(waited, ["login"], "the receipt is not part of that switch")
        XCTAssertEqual(tracker.trackedScreen, "login")
        try step(&tracker, "login", verify: false)
        XCTAssertEqual(waited, ["login"], "the same screen again is not checked again")
    }

    func testAReceiptThatFailedIsCheckedAgainByTheNextAttempt() throws {
        var tracker = FlowScreenTracker()
        tracker.startFlow(pendingReceipts: ["login": "L1"])
        failReceipt = ["login"]
        XCTAssertThrowsError(try step(&tracker, "login"))
        XCTAssertEqual(tracker.pendingReceipts.keys.sorted(), ["login"], "removed before it was confirmed")

        failReceipt = []
        tracker.startAttempt()
        try step(&tracker, "login")
        XCTAssertEqual(waited, ["login", "login"], "the retried attempt must check the receipt again")
        XCTAssertEqual(verified, ["login", "login"], "and the screen")
        XCTAssertTrue(tracker.pendingReceipts.isEmpty)
    }

    func testAnAttemptStartsWithNoScreenForState() throws {
        var tracker = FlowScreenTracker()
        tracker.startFlow(pendingReceipts: [:])
        try step(&tracker, "home")
        XCTAssertEqual(tracker.stateScreen, "home")
        tracker.startAttempt()
        XCTAssertNil(tracker.stateScreen, "a retry's first `state` would read the failed attempt's screen")
    }

    func testTheNextFlowFileDoesNotInheritTheScreenTheLastOneEndedOn() throws {
        var tracker = FlowScreenTracker()
        tracker.startFlow(pendingReceipts: [:])
        try step(&tracker, "home")
        // The second flow file starts on the screen the first ended on.
        tracker.startFlow(pendingReceipts: ["home": "L2"])
        try step(&tracker, "home")
        XCTAssertEqual(verified, ["home", "home"], "the second flow's first step skipped its screen check")
        XCTAssertEqual(waited, ["home"], "and its receipt")
        XCTAssertNil(tracker.unreachedWarnings.first)
    }

    func testAReferencedCaseReadsItsFileScreenAndStateComesBack() throws {
        var tracker = FlowScreenTracker()
        tracker.startFlow(pendingReceipts: [:])
        try step(&tracker, "home")
        tracker.enterFileReference(screenOfFile: "login")
        XCTAssertEqual(tracker.stateScreen, "login")
        XCTAssertNil(tracker.trackedScreen, "after a file reference the screen is unknown")
        tracker.leaveFileReference()
        XCTAssertEqual(tracker.stateScreen, "home", "the flow's last named screen")
        try step(&tracker, "home")
        XCTAssertEqual(verified, ["home", "home"], "unknown means the next step is checked")
    }

    func testOnlyAScreenNeverReachedIsWarned() throws {
        var tracker = FlowScreenTracker()
        tracker.startFlow(pendingReceipts: ["login": "L1", "profile": "L1"])
        failReceipt = ["login"]
        XCTAssertThrowsError(try step(&tracker, "login"))
        XCTAssertEqual(tracker.unreachedWarnings, [
            "initialState for screen 'profile' was never checked: the flow never reached it (no step names that screen)"
        ], "a reached screen whose receipt failed is a failure, not 'never reached'")
    }
}
