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
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: viewport), .beyondViewport)
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
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: viewport), .withinViewport)
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
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: nil), .noViewport)
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
        XCTAssertEqual(ScrollDiagnosis.placement(element: element, viewport: .zero), .noViewport)
        XCTAssertEqual(ScrollDiagnosis.placement(element: .null, viewport: viewport), .noViewport)
    }
}
