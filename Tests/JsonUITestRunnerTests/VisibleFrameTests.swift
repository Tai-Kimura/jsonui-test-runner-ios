import XCTest
@testable import JsonUITestRunner

/// `VisibleFrame.hasArea`: a frame under 1pt on either side is not visible.
/// The measured shape is an empty accessibility container whose only frame is
/// SwiftJsonUI's 0.5pt anchor, read back as 0.667 x 0.667 on an iPhone 16 Pro
/// (and 0.640 x 0.640 inside a sheet, presented at about 0.96).
final class VisibleFrameTests: XCTestCase {

    func testAnEmptyContainersAnchorHasNoArea() {
        XCTAssertFalse(VisibleFrame.hasArea(CGRect(x: 16, y: 131, width: 0.667, height: 0.667)))
        XCTAssertFalse(VisibleFrame.hasArea(CGRect(x: 23.4, y: 457.9, width: 0.640, height: 0.640)))
    }

    /// The boundary, on both sides and on each axis alone.
    func testOnePointIsTheBoundary() {
        XCTAssertTrue(VisibleFrame.hasArea(CGRect(x: 0, y: 0, width: 1, height: 1)), "exactly 1pt is drawn")
        XCTAssertFalse(VisibleFrame.hasArea(CGRect(x: 0, y: 0, width: 0.999, height: 1)))
        XCTAssertFalse(VisibleFrame.hasArea(CGRect(x: 0, y: 0, width: 1, height: 0.999)))
        XCTAssertFalse(VisibleFrame.hasArea(CGRect(x: 0, y: 0, width: 370, height: 0.5)), "a wide frame with no height")
        XCTAssertFalse(VisibleFrame.hasArea(CGRect(x: 0, y: 0, width: 0.5, height: 314)), "a tall frame with no width")
    }

    /// Control: an ordinary element.
    func testAnOrdinaryFrameHasArea() {
        XCTAssertTrue(VisibleFrame.hasArea(CGRect(x: 16, y: 110.7, width: 33, height: 20.3)))
    }

    func testNoFrameHasNoArea() {
        XCTAssertFalse(VisibleFrame.hasArea(.zero))
        XCTAssertFalse(VisibleFrame.hasArea(.null))
        XCTAssertFalse(VisibleFrame.hasArea(.infinite))
    }

    // MARK: - In the viewport (visible / notVisible / when.visible)
    //
    // The measured shapes: a 200pt ScrollView at the top of a 402 x 874 app,
    // with Labels 20pt tall at y 0 (top), 195 (half: 5pt shown, its centre
    // at 205 outside) and 580 (tail). Android, the baseline, calls top and
    // half visible and tail not (2026-10-14).

    private let app = CGRect(x: 0, y: 0, width: 402, height: 874)
    private let scroll = CGRect(x: 0, y: 0, width: 200, height: 200)

    func testALabelInsideTheScrollViewIsInTheViewport() {
        XCTAssertTrue(VisibleFrame.inViewport(CGRect(x: 0, y: 0, width: 200, height: 20), clips: [app, scroll]))
    }

    func testALabelScrolledOutOfTheScrollViewIsNotInTheViewport() {
        // Inside the app's frame, outside its scroll container: the old
        // predicate (frame area alone) called this visible.
        let tail = CGRect(x: 0, y: 580, width: 200, height: 20)
        XCTAssertTrue(VisibleFrame.hasArea(tail), "control: the frame alone has area")
        XCTAssertTrue(app.intersects(tail), "control: inside the app's frame")
        XCTAssertFalse(VisibleFrame.inViewport(tail, clips: [app, scroll]))
    }

    func testAPartShownIsEnoughEvenWithTheCentreOutside() {
        let half = CGRect(x: 0, y: 195, width: 200, height: 20)
        XCTAssertFalse(scroll.contains(CGPoint(x: half.midX, y: half.midY)), "control: the centre is outside")
        XCTAssertTrue(VisibleFrame.inViewport(half, clips: [app, scroll]))
    }

    func testTheOnePointBoundaryHoldsForTheShownPart() {
        XCTAssertTrue(VisibleFrame.inViewport(CGRect(x: 0, y: 199, width: 200, height: 20), clips: [app, scroll]), "1pt shown")
        XCTAssertFalse(VisibleFrame.inViewport(CGRect(x: 0, y: 199.5, width: 200, height: 20), clips: [app, scroll]), "0.5pt shown")
        XCTAssertFalse(VisibleFrame.inViewport(CGRect(x: 0, y: 200, width: 200, height: 20), clips: [app, scroll]), "touching the edge")
    }

    func testEveryContainerClipsNotOnlyTheInnermost() {
        // An inner list scrolled into its own view, but its outer page
        // scrolled away.
        let outer = CGRect(x: 0, y: -400, width: 402, height: 300) // ends at y -100, off the app
        let inner = CGRect(x: 0, y: -300, width: 402, height: 100)
        let row = CGRect(x: 0, y: -280, width: 402, height: 40)
        XCTAssertFalse(VisibleFrame.inViewport(row, clips: [app, outer, inner]))
        XCTAssertTrue(VisibleFrame.inViewport(row, clips: [outer, inner]), "control: the app's frame is what cuts it")
    }

    func testOffTheAppSideways() {
        // A page of a horizontal pager, one page to the right.
        XCTAssertFalse(VisibleFrame.inViewport(CGRect(x: 402, y: 100, width: 402, height: 300), clips: [app]))
    }

    func testNoFrameIsNeverInTheViewport() {
        XCTAssertFalse(VisibleFrame.inViewport(.null, clips: [app]))
        XCTAssertFalse(VisibleFrame.inViewport(.infinite, clips: [app]))
        XCTAssertTrue(VisibleFrame.shownPart(of: CGRect(x: 0, y: 900, width: 10, height: 10), clips: [app]).isNull)
    }
}
