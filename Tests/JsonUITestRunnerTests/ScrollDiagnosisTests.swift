import XCTest
@testable import JsonUITestRunner

/// The message a scroll leaves when the target is still not hittable.
///
/// Its first version stated a guess as the finding — "something is probably
/// covering it (a bottom fixed bar, a tab bar, the keyboard)". An app that
/// read it did have such a bar, so a wrong cause was carried across two runs
/// and reported twice; the bar turned out to be a sibling of the scroll
/// view, and the element was simply below what the container could show.
final class ScrollDiagnosisTests: XCTestCase {

    private let window = CGRect(x: 0, y: 0, width: 402, height: 874)
    /// A scroll view above a bottom bar: it shows 0..818, the bar owns the rest.
    private let viewport = CGRect(x: 0, y: 0, width: 402, height: 818)

    func testAnElementBelowWhatTheContainerShowsIsNotCalledCovered() {
        // The misdiagnosed shape: inside the window, outside the viewport.
        let element = CGRect(x: 88, y: 830, width: 97, height: 32)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: viewport, window: window), .beyondViewport)
        let text = ScrollDiagnosis.message(id: "chip", element: element, viewport: viewport,
                                           viewportLabel: "container 'content_scroll'", appWindow: window)
        XCTAssertTrue(text.contains("OUTSIDE"), text)
        XCTAssertTrue(text.contains("nothing needs to be covering it"), text)
        XCTAssertFalse(text.contains("drawn in front"), text)
    }

    func testAnElementTheContainerIsShowingIsTheCoveredCase() {
        // The keyboard shape: the viewport is showing that point, so the
        // reason it is not hittable is in front of it.
        let element = CGRect(x: 40, y: 700, width: 300, height: 44)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: viewport, window: window), .withinViewport)
        let text = ScrollDiagnosis.message(id: "password_field", element: element, viewport: viewport,
                                           viewportLabel: "container 'form_scroll'", appWindow: window)
        XCTAssertTrue(text.contains("drawn in front of it"), text)
        XCTAssertTrue(text.contains("not a scrolling problem"), text)
        XCTAssertFalse(text.contains("nothing needs to be covering it"), text)
    }

    func testTheTwoCasesActuallyProduceDifferentText() {
        // A discriminator that cannot say two things is not one. This is the
        // property the previous message lacked: it printed the covering
        // guesses whatever the geometry was.
        let inside = ScrollDiagnosis.message(id: "x", element: CGRect(x: 0, y: 100, width: 100, height: 40),
                                             viewport: viewport, viewportLabel: "c", appWindow: window)
        let outside = ScrollDiagnosis.message(id: "x", element: CGRect(x: 0, y: 830, width: 100, height: 40),
                                              viewport: viewport, viewportLabel: "c", appWindow: window)
        XCTAssertNotEqual(inside, outside)
    }

    func testWithoutAContainerTheBitIsAbsentAndSaysSo() {
        // The whole app was the swipe surface: the question cannot be asked,
        // and the message must not imply an answer either way.
        let element = CGRect(x: 0, y: 830, width: 100, height: 40)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: nil, window: window), .noViewport)
        let text = ScrollDiagnosis.message(id: "x", element: element, viewport: nil,
                                           viewportLabel: "no container", appWindow: window)
        XCTAssertTrue(text.contains("cannot be told apart"), text)
        XCTAssertFalse(text.contains("drawn in front"), text)
        XCTAssertFalse(text.contains("nothing needs to be covering it"), text)
    }

    func testObservationAndGuessesAreLabelledApart() {
        let text = ScrollDiagnosis.message(id: "x", element: CGRect(x: 0, y: 100, width: 10, height: 10),
                                           viewport: viewport, viewportLabel: "c", appWindow: window)
        XCTAssertTrue(text.contains("observed:"), text)
        XCTAssertTrue(text.contains("candidates:"), text)
        // Every measured rect is in the observation, so a reader can redo
        // the reasoning instead of trusting the label.
        XCTAssertTrue(text.contains("\(window)"), text)
        XCTAssertTrue(text.contains("\(viewport)"), text)
    }

    func testADegenerateViewportIsTreatedAsNoViewport() {
        let element = CGRect(x: 0, y: 10, width: 10, height: 10)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: .zero, window: window), .noViewport)
        XCTAssertEqual(ScrollDiagnosis.placement(element: .null, viewport: viewport, window: window), .noViewport)
    }

    // MARK: - A container whose frame runs past the window
    //
    // Every fixture above nests the viewport INSIDE the window, so clamping
    // the viewport to the window is a no-op for all of them: they cannot
    // see a discriminator that asks the frame instead of the visible area.
    // A probe on the conformance host found that shape and measured the
    // wrong verdict. These are the fixtures the corpus was missing.

    /// Taller than the window: a scroller nested in another scroller, sized
    /// to its content, or scrolled partly off screen.
    private let tallWindow = CGRect(x: 0, y: 0, width: 320, height: 568)
    private let tallViewport = CGRect(x: 0, y: 0, width: 320, height: 1462)

    func testAPointPastTheWindowIsNotCoveredEvenThoughTheFrameContainsIt() {
        // Measured shape: hit point (160, 1387) is inside a 1462-tall frame
        // and off the bottom of the screen. Nothing is in front of it.
        let element = CGRect(x: 20, y: 1362, width: 280, height: 50)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: tallViewport, window: tallWindow),
                       .beyondViewport)
        let text = ScrollDiagnosis.message(id: "item_26", element: element, viewport: tallViewport,
                                           viewportLabel: "container 'scroller'", appWindow: tallWindow)
        XCTAssertTrue(text.contains("OUTSIDE"), text)
        XCTAssertTrue(text.contains("nothing needs to be covering it"), text)
        XCTAssertFalse(text.contains("drawn in front"), text)
        XCTAssertFalse(text.contains("not a scrolling problem"), text)
    }

    func testInTheSameOversizedContainerAPointOnScreenIsStillTheCoveredCase() {
        // Positive control for the arm above: clamping to the window must
        // not turn every verdict into "beyond". Same container, a hit point
        // the screen is showing.
        let element = CGRect(x: 20, y: 112, width: 280, height: 50)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: tallViewport, window: tallWindow),
                       .withinViewport)
        let text = ScrollDiagnosis.message(id: "item_1", element: element, viewport: tallViewport,
                                           viewportLabel: "container 'scroller'", appWindow: tallWindow)
        XCTAssertTrue(text.contains("drawn in front of it"), text)
    }

    func testAContainerWithNoPartOnScreenIsNotCovered() {
        // Resolved, but scrolled entirely away. Nothing here is visible, so
        // nothing here can be in front of the element.
        let offscreen = CGRect(x: 0, y: 900, width: 320, height: 400)
        let element = CGRect(x: 20, y: 1000, width: 280, height: 50)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: offscreen, window: tallWindow),
                       .beyondViewport)
        let text = ScrollDiagnosis.message(id: "row", element: element, viewport: offscreen,
                                           viewportLabel: "container 'carousel'", appWindow: tallWindow)
        XCTAssertTrue(text.contains("none of it on screen"), text)
        XCTAssertFalse(text.contains("drawn in front"), text)
    }

    func testTheVisiblePartIsPrintedBesideTheFrame() {
        // When the two rects differ, the difference is the finding — so a
        // reader must be able to redo the arithmetic from the message.
        //
        // The viewport is OFFSET as well as oversized, so the intersection
        // (0, 100, 320, 468) equals neither the frame nor the window. With
        // the frame flush to the top, the intersection and the window are
        // the same string and this assertion would pass without the clamp.
        let offsetViewport = CGRect(x: 0, y: 100, width: 320, height: 1462)
        let visible = offsetViewport.intersection(tallWindow)
        XCTAssertNotEqual(visible, offsetViewport)
        XCTAssertNotEqual(visible, tallWindow)
        let element = CGRect(x: 20, y: 1362, width: 280, height: 50)
        let text = ScrollDiagnosis.message(id: "item_26", element: element, viewport: offsetViewport,
                                           viewportLabel: "container 'scroller'", appWindow: tallWindow)
        XCTAssertTrue(text.contains("\(offsetViewport)"), text)
        XCTAssertTrue(text.contains("\(visible)"), text)
        XCTAssertTrue(text.contains("\(tallWindow)"), text)
    }

    func testWithoutAUsableWindowTheRawFrameIsUsedRatherThanNothing() {
        // A clamp needs something to clamp to. With no window rect the bit
        // falls back to the frame instead of calling everything off screen.
        let element = CGRect(x: 20, y: 1362, width: 280, height: 50)
        XCTAssertEqual(ScrollDiagnosis.visibleArea(of: tallViewport, in: .zero), tallViewport)
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: tallViewport, window: .zero),
                       .withinViewport)
    }
}
