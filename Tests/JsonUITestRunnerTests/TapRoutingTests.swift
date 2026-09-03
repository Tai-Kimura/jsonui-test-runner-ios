import XCTest
@testable import JsonUITestRunner

/// The route a tap takes from what XCTest reports (TapRouting.route). The
/// first case is the 2026-09-03 consumer incident verbatim: a PHPicker
/// thumbnail that exists with an on-screen frame and isHittable == false,
/// which `XCUIElement.tap()` refused as "not hittable".
final class TapRoutingTests: XCTestCase {
    private let phone = CGRect(x: 0, y: 0, width: 402, height: 874)

    func testPickerThumbnailNotHittableOnScreenGoesToFrameCenter() {
        let thumbnail = CGRect(x: 0, y: 312, width: 132.9, height: 133)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: thumbnail, appFrame: phone), .frameCenter)
    }

    func testHittableElementIsTappedAsAnElement() {
        // Control: hittability intact keeps the old path, whatever the frame.
        let thumbnail = CGRect(x: 0, y: 312, width: 132.9, height: 133)
        XCTAssertEqual(TapRouting.route(isHittable: true, frame: thumbnail, appFrame: phone), .element)
        XCTAssertEqual(TapRouting.route(isHittable: true, frame: .zero, appFrame: phone), .element)
    }

    func testNoFrameIsRefused() {
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: .zero, appFrame: phone), .noFrame)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: .null, appFrame: phone), .noFrame)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: CGRect(x: 10, y: 10, width: 0, height: 40), appFrame: phone), .noFrame)
    }

    func testOffscreenFrameIsRefused() {
        // The iPad keyboard shape: a key whose frame sits ~350pt below the
        // visible screen; the keyboard path then taps its invariant corner.
        let belowScreen = CGRect(x: 300, y: 874 + 350, width: 60, height: 44)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: belowScreen, appFrame: phone), .offscreen)
        // Straddling the edge with its center outside is also off-screen.
        let straddling = CGRect(x: 380, y: 100, width: 60, height: 44)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: straddling, appFrame: phone), .offscreen)
    }

    func testCenterInsideTheWindowIsEnough() {
        // A frame that overlaps the edge but whose center is inside is
        // reachable (x 360..420 on a 402pt window: center 390).
        let edge = CGRect(x: 360, y: 100, width: 60, height: 44)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: edge, appFrame: phone), .frameCenter)
    }
}
