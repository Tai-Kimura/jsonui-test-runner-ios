import XCTest
@testable import JsonUITestRunner

/// The stop condition (`canStopScrolling`) and the failure-path diagnostic
/// (`onScreen`). The `onScreen` cases below are the 2026-09-04
/// consumer incident verbatim: a section at y=1155.67 on an 874pt-tall
/// window — 281pt below the last visible row — that the old rule
/// (`exists && !frame.isEmpty`) called visible, so the step returned without
/// swiping once.
final class ScrollVisibilityTests: XCTestCase {
    private let phone = CGRect(x: 0, y: 0, width: 402, height: 874)

    /// The bottom-fixed-bar incident (2026-09-04, measured on two runs): the
    /// bar covers 818..874, the scroll came to rest with the target at
    /// 818..850 exactly under it, and the frame-center tap opened the bar's
    /// own screen. The target intersects the window, so the 1.9.4 stop
    /// condition accepted it — this arm is what keeps intersection out of
    /// the stop condition.
    func testATargetUnderABottomFixedBarDoesNotStopTheScroll() {
        let underTheBar = CGRect(x: 88.67, y: 818, width: 97, height: 32)
        XCTAssertTrue(ScrollVisibility.onScreen(isHittable: false, frame: underTheBar, appFrame: phone),
                      "it is on screen — which is exactly why intersection is not enough")
        XCTAssertFalse(ScrollVisibility.canStopScrolling(isHittable: false),
                       "not hittable means covered or not there; keep scrolling")
    }

    func testHittabilityIsTheStopCondition() {
        XCTAssertTrue(ScrollVisibility.canStopScrolling(isHittable: true))
        XCTAssertFalse(ScrollVisibility.canStopScrolling(isHittable: false))
    }

    func testSectionBelowTheViewportIsNotVisible() {
        let below = CGRect(x: 0, y: 1155.6666666666665, width: 402, height: 78)
        XCTAssertFalse(ScrollVisibility.onScreen(isHittable: false, frame: below, appFrame: phone))
        // The old rule's answer, kept here as the thing that changed.
        XCTAssertFalse(below.isEmpty)
    }

    func testHittableIsVisibleWhateverTheFrame() {
        // Control: hittability is the strong answer and is not second-guessed.
        let below = CGRect(x: 0, y: 1155.67, width: 402, height: 78)
        XCTAssertTrue(ScrollVisibility.onScreen(isHittable: true, frame: below, appFrame: phone))
        XCTAssertTrue(ScrollVisibility.onScreen(isHittable: true, frame: .zero, appFrame: phone))
    }

    func testAnIntersectingFrameIsVisible() {
        // Partially scrolled in at the bottom edge: on screen, stop scrolling.
        let peeking = CGRect(x: 0, y: 840, width: 402, height: 78)
        XCTAssertTrue(ScrollVisibility.onScreen(isHittable: false, frame: peeking, appFrame: phone))
    }

    func testAnElementTallerThanTheViewportIsVisible() {
        // Why intersection and not "the center is inside": this section fills
        // the screen while its center sits below it. Requiring the center
        // would scroll it forever.
        // Spans -1000..600 on an 0..874 window: the top 600pt of it fill
        // the screen, and its center (y = -200) is above the window.
        let tall = CGRect(x: 0, y: -1000, width: 402, height: 1600)
        XCTAssertFalse(phone.contains(CGPoint(x: tall.midX, y: tall.midY)))
        XCTAssertTrue(ScrollVisibility.onScreen(isHittable: false, frame: tall, appFrame: phone))
    }

    func testTouchingEdgesAndEmptyFrames() {
        // Exactly above the viewport, sharing the y=0 edge only: not visible
        // (CGRect.intersects treats edge-only contact as no intersection).
        let above = CGRect(x: 0, y: -78, width: 402, height: 78)
        XCTAssertFalse(ScrollVisibility.onScreen(isHittable: false, frame: above, appFrame: phone))
        XCTAssertFalse(ScrollVisibility.onScreen(isHittable: false, frame: .zero, appFrame: phone))
        XCTAssertFalse(ScrollVisibility.onScreen(isHittable: false, frame: .null, appFrame: phone))
        XCTAssertFalse(ScrollVisibility.onScreen(isHittable: false, frame: CGRect(x: 10, y: 10, width: 0, height: 40), appFrame: phone))
    }
}
