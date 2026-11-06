import XCTest
@testable import JsonUITestRunner

/// `assert: "screen"` fails with one sentence from one read of the markers. The
/// Android driver read "'x' is not displayed; displayed screens are [x]" at load
/// 70, and this diagnosis asked the same two questions apart. Given one read, the
/// wanted screen in it can never land in the sentence that says it is missing.
final class ScreenVerdictOneReadTests: XCTestCase {
    func testTheWantedScreenInTheReadIsNeverCalledMissing() {
        let sentence = ScreenMarker.diagnosis(screenId: "detail", present: ["detail"], covering: [])
        XCTAssertFalse(sentence.contains("is not present"), sentence)
        XCTAssertTrue(sentence.hasPrefix("marker-not-displayed: 'detail' exists but is not hittable"), sentence)
    }

    func testAScreenOnTopOfTheWantedOneIsNamed() {
        let sentence = ScreenMarker.diagnosis(screenId: "detail", present: ["detail", "sheet"], covering: ["sheet"])
        XCTAssertTrue(sentence.hasPrefix("covered-by-screen: 'detail' is present but [\"sheet\"] is on top"), sentence)
    }

    func testAnotherScreenStaysPreviousScreenOnly() {
        let sentence = ScreenMarker.diagnosis(screenId: "detail", present: ["list"], covering: ["list"])
        XCTAssertTrue(sentence.hasPrefix("previous-screen-only: 'detail' is not present; displayed screens are [\"list\"]"), sentence)
    }

    func testNoMarkersStaysMarkerAbsent() {
        let sentence = ScreenMarker.diagnosis(screenId: "detail", present: [], covering: [])
        XCTAssertTrue(sentence.hasPrefix("marker-absent: no screen marker anywhere"), sentence)
    }

    func testCoveringIsNotAskedWhenTheWantedScreenIsNotInTheRead() {
        var asked = false
        func covering() -> [String] { asked = true; return [] }
        _ = ScreenMarker.diagnosis(screenId: "detail", present: ["list"], covering: covering())
        XCTAssertFalse(asked)
    }
}
