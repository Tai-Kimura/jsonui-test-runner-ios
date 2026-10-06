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
}
