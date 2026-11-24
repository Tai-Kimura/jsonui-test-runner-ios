import XCTest
@testable import JsonUITestRunner

/// Where `tap {id, text}` presses (TextTapRouting.route).
final class TextTapRoutingTests: XCTestCase {
    private let header = CGRect(x: 40, y: 300, width: 140, height: 24)

    /// The shape of ticket 2026-11-24-conformance-android-tap-untagged-material-child-and-pinned-locale: the
    /// element found by id has no label of its own; a child that takes no press carries the words.
    func testAChildNamedByTheTextIsPressedThoughTheElementHasNoLabel() {
        XCTAssertEqual(TextTapRouting.route(fullText: "", targetText: "November 2025", hittableLink: false,
                                            namedChildFrame: header), .namedChild)
    }

    func testAHittableLinkStillComesFirst() {
        XCTAssertEqual(TextTapRouting.route(fullText: "利用規約に同意する", targetText: "利用規約", hittableLink: true,
                                            namedChildFrame: header), .link)
    }

    func testAPartOfTheOwnLabelIsStillPressedByItsShare() {
        // Control: no named child keeps the old path.
        XCTAssertEqual(TextTapRouting.route(fullText: "利用規約に同意する", targetText: "利用規約", hittableLink: false,
                                            namedChildFrame: nil), .proportional)
    }

    func testANamedChildWithNoAreaIsNotPressed() {
        // SwiftJsonUI's 0.5pt anchor children read as a frame under 1pt (VisibleFrame).
        let anchor = CGRect(x: 16, y: 131, width: 0.667, height: 0.667)
        XCTAssertEqual(TextTapRouting.route(fullText: "", targetText: "November 2025", hittableLink: false,
                                            namedChildFrame: anchor), .notFound)
        XCTAssertEqual(TextTapRouting.route(fullText: "", targetText: "November 2025", hittableLink: false,
                                            namedChildFrame: nil), .notFound)
    }
}
