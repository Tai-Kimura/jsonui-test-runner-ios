import XCTest
import JsonUITestRunner

/// moveItem on a SwiftUI List that reorders with onMove (ReorderProbeView), through the public executor: the press,
/// the slow drag, the hold and the release over the to row (MoveItemPlan, by jsonui-test-runner
/// specs/vectors/move-item.json) move the row to `to`, counted after the move; a step the plan refuses moves nothing.
final class MoveItemOnDeviceTests: XCTestCase {
    private var app: XCUIApplication!
    private var actions: XCUITestActionExecutor!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-probe", "reorder"]
        app.launch()
        actions = XCUITestActionExecutor(variables: VariableStore())
        XCTAssertTrue(app.descendants(matching: .any)["list_item_0"].waitForExistence(timeout: 10))
    }

    private func label(_ id: String) -> String { app.descendants(matching: .any)[id].label }

    private func move(_ from: Int, _ to: Int, timeout: Int? = nil) throws {
        try actions.execute(step: TestStep(action: "moveItem", id: "list", timeout: timeout, from: from, to: to), in: app)
    }

    func testDownAndUpMoveTheRowToItsIndexAfterTheMove() throws {
        try move(0, 2)
        XCTAssertEqual(label("moves"), "0>2")
        XCTAssertTrue(label("order").hasPrefix("R1,R2,R0,R3"), label("order"))
        try move(3, 0)
        XCTAssertEqual(label("moves"), "0>2 3>0")
        XCTAssertTrue(label("order").hasPrefix("R3,R1,R2,R0"), label("order"))
    }

    /// A row near the bottom: a release there would let the List scroll by itself under the held finger and land the
    /// row further (measured: 55 pt above the window's bottom moved 0 to 11 instead of 9) — refused, nothing moves.
    /// The furthest row clear of the edge is reached exactly.
    func testARowNearTheBottomIsRefusedAndTheLastClearRowIsReached() throws {
        let window = app.windows.firstMatch.frame
        let element = { (n: Int) in self.app.descendants(matching: .any)["list_item_\(n)"] }
        let row = { (n: Int) in element(n).frame }
        let onScreen = (0..<12).filter { element($0).exists && window.contains(row($0)) }   // a List draws lazily
        let near = try XCTUnwrap(onScreen.last)
        XCTAssertThrowsError(try move(1, near)) { error in
            XCTAssertTrue(error.localizedDescription.contains("is too near the top or bottom of the screen"), error.localizedDescription)
        }
        XCTAssertEqual(label("moves"), "")
        let clear = try XCTUnwrap(onScreen.last { window.maxY - (row($0).minY + row($0).height * 0.75) >= MoveItemPlan.edgeMargin })
        try move(1, clear)
        XCTAssertEqual(label("moves"), "1>\(clear)")
    }

    /// Row 0 of a list at its top, and the last row of a list at its end, move: nothing scrolls that way, so their
    /// nearness to the edges does not count (only a side the list can still scroll towards does).
    func testTheFirstAndTheLastRowOfAListAtItsEndsMove() throws {
        app.terminate()
        app.launchArguments = ["-probe", "reorder", "-rows", "6"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["list_item_5"].waitForExistence(timeout: 10))
        try move(0, 2)
        XCTAssertEqual(label("moves"), "0>2")
        try move(3, 5)
        XCTAssertEqual(label("moves"), "0>2 3>5")
        XCTAssertEqual(label("order"), "R1,R2,R0,R4,R5,R3")
    }

    func testARefusedStepMovesNothing() {
        for (from, to, said) in [(2, 2, "are the same row"), (0, 40, "was not found")] {
            XCTAssertThrowsError(try move(from, to, timeout: 500)) { error in
                XCTAssertTrue(error.localizedDescription.contains(said), error.localizedDescription)
            }
        }
        XCTAssertEqual(label("moves"), "")
    }
}
