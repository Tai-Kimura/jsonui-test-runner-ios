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

    func testOffscreenAndNoFrameStillReachTheElementTap() {
        // Not a routing assertion but the contract the executor implements on
        // top of it: neither refusal is final. ActionExecutor maps both to
        // element.tap(), because XCTest resolves an element by scrolling it
        // into view and that recovery carried every tap up to 1.9.2.
        let below = CGRect(x: 0, y: 1155.67, width: 402, height: 78)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: below, appFrame: phone), .offscreen)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: .zero, appFrame: phone), .noFrame)
    }

    func testCenterInsideTheWindowIsEnough() {
        // A frame that overlaps the edge but whose center is inside is
        // reachable (x 360..420 on a 402pt window: center 390).
        let edge = CGRect(x: 360, y: 100, width: 60, height: 44)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: edge, appFrame: phone), .frameCenter)
    }

    // MARK: the keyboard (2026-10-15)

    /// The incident's shape: a sign-in button at {{24, 567}, {354, 56}} on an
    /// iPhone 17 window, not hittable because the keyboard came back over it
    /// after typeText. Its center (201, 595) is inside the keyboard frame,
    /// read in the same run: {{0, 590}, {402, 226}}.
    private let button = CGRect(x: 24, y: 567, width: 354, height: 56)
    private let keyboard = CGRect(x: 0, y: 590, width: 402, height: 226)

    func testACenterInsideTheKeyboardIsNotACoordinateToTap() {
        XCTAssertEqual(
            TapRouting.route(isHittable: false, frame: button, appFrame: phone, keyboard: keyboard),
            .underKeyboard
        )
    }

    func testTheSameFrameWithNoKeyboardStillGoesToItsCenter() {
        // Control: the route the incident took, and still takes when no
        // keyboard is up — the remote-UI shapes this branch exists for.
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: button, appFrame: phone, keyboard: nil), .frameCenter)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: button, appFrame: phone), .frameCenter)
    }

    func testAFrameThatOnlyOverlapsTheKeyboardIsTappedAtItsCenter() {
        // Boundary: the keyboard's top edge. The tap lands on the center, so
        // the center decides — a frame reaching into the keyboard with its
        // center above it is still a coordinate a finger can use.
        let top = keyboard.minY
        let above = CGRect(x: 24, y: top - 40, width: 354, height: 56)   // center top-12
        let below = CGRect(x: 24, y: top - 16, width: 354, height: 56)   // center top+12
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: above, appFrame: phone, keyboard: keyboard), .frameCenter)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: below, appFrame: phone, keyboard: keyboard), .underKeyboard)
    }

    func testAHittableElementIsTappedEvenWithAKeyboardUp() {
        // Hittable means nothing is in front of it, the keyboard included.
        XCTAssertEqual(TapRouting.route(isHittable: true, frame: button, appFrame: phone, keyboard: keyboard), .element)
    }

    func testAnEmptyKeyboardFrameCoversNothing() {
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: button, appFrame: phone, keyboard: .zero), .frameCenter)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: button, appFrame: phone, keyboard: .null), .frameCenter)
    }

    func testOffscreenIsDecidedBeforeTheKeyboard() {
        // A frame below the window keeps its element tap (XCTest scrolls it
        // into view), keyboard or not.
        let below = CGRect(x: 0, y: 1155.67, width: 402, height: 78)
        XCTAssertEqual(TapRouting.route(isHittable: false, frame: below, appFrame: phone, keyboard: keyboard), .offscreen)
    }
}
