import XCTest
@testable import JsonUITestRunner

/// `assert: screen` asks its two questions in an order that cannot fail.
///
/// `assertScreen` had a fallback for the covered case — "still displayed
/// unless something else claims to be" — and could not reach it. It asked
/// `element.isHittable` first, and XCUITest does not return `false` when it
/// cannot COMPUTE hittability: it records a test failure ("Activation point
/// invalid and no suggested hit points based on element frame"). So the most
/// thoroughly covered marker, the one the fallback was written for, failed on
/// its way to the rescue.
///
/// Reported from a consumer face: reproduced on a tablet lane in two
/// consecutive runs 0.3s apart, while the same 75 cases passed on phone.
///
/// ⚠️ What these arms prove and what they do not. They prove the reordered
/// predicate returns the SAME verdict in all four combinations, and that the
/// failing call is not made in the shape that was failing. They do NOT prove
/// the consumer's red disappears — reproducing it needs that face's app on a
/// tablet, which is not available here. The claim shipped is the equivalence
/// and the removed evaluation.
final class ScreenDisplayedOrderTests: XCTestCase {

    // MARK: - Equivalence with the order this replaced

    /// The predicate as it was written before: hittable wins, else fall back.
    private func oldOrder(markerHittable: Bool, noOtherHittable: Bool) -> Bool {
        if markerHittable { return true }
        return noOtherHittable
    }

    func testTheReorderChangesNoVerdict() {
        for markerHittable in [true, false] {
            for noOtherHittable in [true, false] {
                let now = ScreenMarker.screenIsDisplayed(
                    noOtherScreenIsHittable: noOtherHittable,
                    markerIsHittable: markerHittable)
                let before = oldOrder(markerHittable: markerHittable,
                                      noOtherHittable: noOtherHittable)
                XCTAssertEqual(
                    now, before,
                    "marker=\(markerHittable) noOther=\(noOtherHittable): the "
                    + "reorder must not change any verdict")
            }
        }
    }

    // MARK: - The four rows, stated individually

    func testAHittableMarkerIsDisplayed() {
        XCTAssertTrue(ScreenMarker.screenIsDisplayed(
            noOtherScreenIsHittable: false, markerIsHittable: true))
    }

    func testACoveredMarkerWithNoRivalIsStillDisplayed() {
        // The app's own overlay covers the marker; nothing else claims to be
        // a screen. This is the case the fallback exists for.
        XCTAssertTrue(ScreenMarker.screenIsDisplayed(
            noOtherScreenIsHittable: true, markerIsHittable: false))
    }

    func testACoveredMarkerWithARivalIsNotDisplayed() {
        // A sheet or cover is another SCREEN and brings its own marker.
        XCTAssertFalse(ScreenMarker.screenIsDisplayed(
            noOtherScreenIsHittable: false, markerIsHittable: false))
    }

    func testAHittableMarkerWinsEvenWithARival() {
        XCTAssertTrue(ScreenMarker.screenIsDisplayed(
            noOtherScreenIsHittable: false, markerIsHittable: true))
    }

    // MARK: - The arm the fix is actually about

    func testHittabilityIsNotEvaluatedWhenNoOtherScreenClaimsToBe() {
        // ⭐ The defect was not a wrong verdict — it was ASKING at all. In the
        // reported shape no other screen was hittable, so the answer was
        // already known; evaluating the marker could only fail. If this arm
        // goes green while the evaluation still happens, the fix is cosmetic.
        var asked = false
        let displayed = ScreenMarker.screenIsDisplayed(
            noOtherScreenIsHittable: true,
            markerIsHittable: { asked = true; return false }())
        XCTAssertTrue(displayed)
        XCTAssertFalse(
            asked,
            "the marker's hittability was computed even though no other "
            + "screen claimed to be displayed — that is the call that fails "
            + "when the activation point is invalid, and the whole reason "
            + "this predicate exists")
    }

    func testHittabilityIsStillConsultedWhenARivalExists() {
        // The complement, so the arm above cannot be satisfied by never
        // evaluating at all.
        var asked = false
        _ = ScreenMarker.screenIsDisplayed(
            noOtherScreenIsHittable: false,
            markerIsHittable: { asked = true; return true }())
        XCTAssertTrue(asked)
    }
}
