import XCTest
@testable import JsonUITestRunner

/// The runner's FlowScreens, the way a consumer's run crashed with it
/// (jsonui-cli ticket 2026-10-23-test-ios-runner-segv-in-verify-screen-transition):
/// one test is stopped by XCTest inside a step's screen check, and the next
/// test goes through the same object. The runner outlives its tests the same
/// way — one object, the main thread, test after test.
///
/// XCTest runs these in name order. `test1…` is stopped inside `verify`: a
/// failure recorded with continueAfterFailure false unwinds the test from
/// there, as XCUITest's unanswered read does, and XCTExpectFailure keeps that
/// failure from failing the run. `test2…` then overwrites the stack the
/// stopped test used and checks screens again, and the test after it makes
/// a FlowScreens of its own. With the screen check run in place on the
/// stored tracker (a mutating call on the property), the access that call
/// opened stays registered after the stop, and a later access walks into
/// the overwritten stack: the test process died with "Restarting after
/// unexpected exit, crash" in the test after `test2…`, three runs of three
/// (iOS 26.3 simulator, Xcode 27.2). Without the overwrite it died in one
/// run of two, which is why it is there. Run alone, these tests have
/// nothing to walk into and pass either way.
final class FlowScreensInterruptionTests: XCTestCase {
    private static let screens = FlowScreens()

    func test1AStepStoppedInsideItsScreenCheck() throws {
        continueAfterFailure = false
        XCTExpectFailure("the stop is the point: XCTest unwinds the test from inside verify")
        Self.screens.startFlow(pendingReceipts: [:])
        try Self.screens.enterStep(
            screen: "stopped",
            verifyScreens: true,
            verify: { _ in XCTFail("stopped inside the screen check") },
            waitForReceipt: { _, _ in })
        XCTFail("not reached: the failure above stops the test")
    }

    func test2TheNextTestChecksScreensAgain() throws {
        overwriteTheStack(depth: 3000)
        Self.screens.startFlow(pendingReceipts: [:])
        var verified: [String] = []
        for index in 0..<20 {
            try Self.screens.enterStep(
                screen: "next_\(index)",
                verifyScreens: true,
                verify: { verified.append($0) },
                waitForReceipt: { _, _ in })
        }
        XCTAssertEqual(verified.count, 20)
        XCTAssertEqual(Self.screens.stateScreen, "next_19")
    }

    /// A check that throws (a Swift error, not a stop) keeps what the step
    /// set before it — `state` reads the screen the failed step named, as it
    /// did when the check ran on the stored tracker.
    func testAThrownCheckKeepsTheScreenTheStepNamed() {
        struct Boom: Error {}
        let screens = FlowScreens()
        screens.startFlow(pendingReceipts: [:])
        XCTAssertThrowsError(try screens.enterStep(
            screen: "failed",
            verifyScreens: true,
            verify: { _ in throw Boom() },
            waitForReceipt: { _, _ in }))
        XCTAssertEqual(screens.stateScreen, "failed")
    }

    /// Fills `depth` frames of stack with a value that is not a pointer.
    @inline(never)
    private func overwriteTheStack(depth: Int) {
        var words: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                    UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) =
            (0x4280900073006510, 0x4280900073006510, 0x4280900073006510, 0x4280900073006510,
             0x4280900073006510, 0x4280900073006510, 0x4280900073006510, 0x4280900073006510,
             0x4280900073006510, 0x4280900073006510, 0x4280900073006510, 0x4280900073006510,
             0x4280900073006510, 0x4280900073006510, 0x4280900073006510, 0x4280900073006510)
        withUnsafeMutableBytes(of: &words) { Self.keep($0) }
        if depth > 0 { overwriteTheStack(depth: depth - 1) }
    }

    @inline(never)
    private static func keep(_ bytes: UnsafeMutableRawBufferPointer) {
        if bytes.count == 7 { print(bytes) }
    }
}
