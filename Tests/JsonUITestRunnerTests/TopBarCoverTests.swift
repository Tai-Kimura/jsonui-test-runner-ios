import XCTest
@testable import JsonUITestRunner

/// A target at rest under the navigation bar (TopBarCover). The frames are the
/// 2026-11-06 measurements: iPhone 17, iOS 27.2, keyboard up, bar at 62..116,
/// scroll view 0..482.
final class TopBarCoverTests: XCTestCase {
    private let bar = CGRect(x: 0, y: 62, width: 402, height: 54)
    private let scroller = CGRect(x: 0, y: 0, width: 402, height: 482)
    private let window = CGRect(x: 0, y: 0, width: 402, height: 874)
    private func box(_ y: CGFloat) -> CGRect { CGRect(x: 16, y: y, width: 370, height: 44) }

    func testABoxThatReportedHittableAndPressedNothingIsCovered() {
        for y: CGFloat in [18, 33, 36, 52, 53] {
            XCTAssertTrue(TopBarCover.covers(box(y), bar: bar, inScroller: true), "y \(y)")
        }
    }

    func testBelowTheBarIsNotCovered() {
        XCTAssertFalse(TopBarCover.covers(box(116), bar: bar, inScroller: true))
        XCTAssertFalse(TopBarCover.covers(box(306), bar: bar, inScroller: true))
    }

    func testTheCentreDecidesAtTheBarsBottomEdge() {
        // Centre 115.9 is in the band, centre 116 is not.
        XCTAssertTrue(TopBarCover.covers(CGRect(x: 16, y: 93.9, width: 370, height: 44), bar: bar, inScroller: true))
        XCTAssertFalse(TopBarCover.covers(CGRect(x: 16, y: 94, width: 370, height: 44), bar: bar, inScroller: true))
    }

    func testNoBarCoversNothing() {
        XCTAssertFalse(TopBarCover.covers(box(18), bar: nil, inScroller: true))
        XCTAssertFalse(TopBarCover.covers(box(18), bar: .zero, inScroller: true))
    }

    func testTheBarsOwnButtonIsNotCovered() {
        let back = CGRect(x: 16, y: 66, width: 44, height: 44)
        XCTAssertFalse(TopBarCover.covers(back, bar: bar, inScroller: false))
    }

    func testAColumnBesideTheBarIsNotCovered() {
        let detailBar = CGRect(x: 320, y: 24, width: 700, height: 50)
        XCTAssertFalse(TopBarCover.covers(CGRect(x: 0, y: 30, width: 300, height: 44), bar: detailBar, inScroller: true))
    }

    func testAnEmptyFrameIsNotCovered() {
        XCTAssertFalse(TopBarCover.covers(.zero, bar: bar, inScroller: true))
        XCTAssertFalse(TopBarCover.covers(.null, bar: bar, inScroller: true))
    }

    func testTheBandEndsAtTheScrollerWithoutAKeyboardOverIt() {
        XCTAssertEqual(TopBarCover.band(bar: bar, scroller: scroller, keyboard: nil, window: window),
                       CGRect(x: 0, y: 116, width: 402, height: 366))
    }

    func testTheBandEndsAtAKeyboardThatStartsFirst() {
        let keyboard = CGRect(x: 0, y: 400, width: 402, height: 474)
        XCTAssertEqual(TopBarCover.band(bar: bar, scroller: scroller, keyboard: keyboard, window: window).maxY, 400)
    }

    func testTheBandStartsAtTheScrollerWithNoBar() {
        XCTAssertEqual(TopBarCover.band(bar: nil, scroller: CGRect(x: 0, y: 40, width: 402, height: 400), keyboard: nil, window: window).minY, 40)
    }

    func testATargetUnderTheBarIsDraggedDownByTheWayToTheMiddle() throws {
        let band = TopBarCover.band(bar: bar, scroller: scroller, keyboard: nil, window: window)
        let drag = try XCTUnwrap(TopBarCover.drag(for: box(36), in: band))
        XCTAssertEqual(drag.to - drag.from, band.midY - box(36).midY, accuracy: 0.01)
        XCTAssertGreaterThan(drag.to, drag.from)
    }

    func testATargetFarBelowIsDraggedUpNoFurtherThanTheBandHolds() throws {
        let band = TopBarCover.band(bar: bar, scroller: scroller, keyboard: nil, window: window)
        let drag = try XCTUnwrap(TopBarCover.drag(for: box(1296), in: band))
        XCTAssertLessThan(drag.to, drag.from)
        XCTAssertGreaterThanOrEqual(drag.to, band.minY)
        XCTAssertLessThanOrEqual(drag.from, band.maxY)
    }

    func testATargetInTheBandIsNotDragged() {
        let band = TopBarCover.band(bar: bar, scroller: scroller, keyboard: nil, window: window)
        XCTAssertNil(TopBarCover.drag(for: box(306), in: band))
    }

    func testABandTooThinToDragInGivesNoDrag() {
        XCTAssertNil(TopBarCover.drag(for: box(36), in: CGRect(x: 0, y: 116, width: 402, height: 30)))
    }
}
