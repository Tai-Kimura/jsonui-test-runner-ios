import XCTest
import JsonUITestRunner

/// moveItem on rows SwiftJsonUI reorders (LibraryReorderProbeView): SwiftUI's reorderable() from iOS 27 and the
/// library's own drag below it, and the library's drag on every iOS with a handle. Needs the project generated with
/// SWIFTJSONUI_PATH (a SwiftJsonUI checkout with CollectionReorder); without it the screen says so and these skip.
final class MoveItemLibraryOnDeviceTests: XCTestCase {
    private var app: XCUIApplication!
    private var actions: XCUITestActionExecutor!

    private func launch(_ probe: String) throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-probe", probe]
        app.launch()
        if app.descendants(matching: .any)["unavailable"].waitForExistence(timeout: 3) {
            throw XCTSkip("SwiftJsonUI is not linked into DeviceProbe (generate it with SWIFTJSONUI_PATH)")
        }
        actions = XCUITestActionExecutor(variables: VariableStore())
        XCTAssertTrue(app.descendants(matching: .any)["lib_item_0"].waitForExistence(timeout: 10))
    }

    private func label(_ id: String) -> String { app.descendants(matching: .any)[id].label }

    private func move(_ from: Int, _ to: Int, handle: String? = nil) throws {
        try actions.execute(step: TestStep(action: "moveItem", id: "lib", from: from, to: to, handle: handle), in: app)
    }

    func testRowsMoveDownAndUp() throws {
        try launch("libreorder")
        try move(0, 2)
        XCTAssertEqual(label("moves"), "0>2")
        XCTAssertTrue(label("order").hasPrefix("R1,R2,R0,R3"), label("order"))
        try move(3, 1)
        XCTAssertEqual(label("moves"), "0>2 3>1")
        XCTAssertTrue(label("order").hasPrefix("R1,R3,R2,R0"), label("order"))
    }

    func testWithAHandleTheGripMovesTheRowAndTheBodyDoesNot() throws {
        try launch("libreorderhandle")
        try move(0, 1)   // no handle given: the row's centre is pressed, which does not pick it up
        XCTAssertEqual(label("moves"), "")
        try move(0, 1, handle: "grip")
        XCTAssertEqual(label("moves"), "0>1")
        XCTAssertTrue(label("order").hasPrefix("R1,R0,R2"), label("order"))
    }

    /// The weak spot: the header above row 0 is cut off (scrolled a little), row 0 is wholly visible, so iOS takes the
    /// list as at its top and lets the press near it. Should the list scroll during the drag, the step must fail saying
    /// so; it must never leave the row somewhere else in silence.
    func testWithTheHeaderCutOffTheMoveLandsOrFailsSayingTheListScrolled() throws {
        try launch("libreorder")
        let scroll = app.scrollViews.firstMatch
        let middle = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -20)))
        Thread.sleep(forTimeInterval: 0.5)
        do {
            try move(0, 2)
            XCTAssertTrue(label("order").hasPrefix("R1,R2,R0"), "moved without failing, so it must have landed at 2: \(label("order"))")
        } catch {
            let said = error.localizedDescription
            XCTAssertTrue(said.contains("scrolled during the drag") || said.contains("too near the top or bottom"), said)
            if said.contains("scrolled during the drag") { print("HEADER-CUT: the list scrolled; the step said so: \(label("order"))") }
        }
    }

    func testALockedRowIsNotPassed() throws {
        try launch("libreorderhandle")
        // R2 is locked: R0 dragged onto R4 stops just before it
        try move(0, 4, handle: "grip")
        XCTAssertEqual(label("moves"), "0>1")
        XCTAssertTrue(label("order").hasPrefix("R1,R0,R2"), label("order"))
    }
}
