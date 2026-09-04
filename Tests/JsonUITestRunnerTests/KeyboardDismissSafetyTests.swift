import XCTest
@testable import JsonUITestRunner

/// The four-site incident, as the verdict function sees it.
///
/// Each case below is a reading pair taken from the measured shapes, not an
/// invented one: an edit sheet over a detail screen (2026-09-04) and two
/// picker sheets over a registration form (2026-09-02). Identifiers are
/// neutral fixtures — the real ones stay in the gitignored report.
final class KeyboardDismissSafetyTests: XCTestCase {
    private func context(
        sheets: Int,
        sheetId: String? = nil,
        fields: [String]
    ) -> PresentedContext {
        PresentedContext(sheetCount: sheets, sheetIdentifier: sheetId, editableIdentifiers: fields)
    }

    // MARK: the defect

    func testSheetDismissedByTheDragIsNotASuccess() {
        // The keyboard IS gone — that is the whole trap. Before 1.9.13 this
        // returned success and the next step failed on a control inside the
        // sheet that no longer existed.
        let before = context(sheets: 1, sheetId: "item_edit_sheet", fields: ["note_field"])
        let after = context(sheets: 0, fields: [])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .contextLost("hideKeyboard dismissed the presented sheet 'item_edit_sheet'")
        )
    }

    func testSheetWithNoIdentifierIsStillNamedAsASheet() {
        let before = context(sheets: 1, sheetId: nil, fields: ["note_field"])
        let after = context(sheets: 0, fields: [])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .contextLost("hideKeyboard dismissed the presented sheet '(no identifier)'")
        )
    }

    func testEmptyIdentifierReadsAsNoIdentifierRatherThanEmptyQuotes() {
        // XCUITest hands back "" for an element with no identifier set, which
        // would print as `the presented sheet ''`.
        let before = context(sheets: 1, sheetId: "", fields: ["note_field"])
        let after = context(sheets: 0, fields: [])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .contextLost("hideKeyboard dismissed the presented sheet '(no identifier)'")
        )
    }

    func testContextLossIsCaughtEvenWhenTheSheetCountNeverMoved() {
        // The reading that does not depend on XCTest classifying a SwiftUI
        // sheet as `.sheet`. If sheetCount is blind to the presentation, the
        // field being edited is not: it is gone.
        let before = context(sheets: 0, fields: ["note_field", "rating_field"])
        let after = context(sheets: 0, fields: [])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .contextLost(
                "hideKeyboard dismissed the presented context — "
                    + "the field(s) being edited no longer exist: 'note_field', 'rating_field'"
            )
        )
    }

    func testOnlyTheVanishedFieldsAreNamed() {
        let before = context(sheets: 0, fields: ["kept_field", "lost_field"])
        let after = context(sheets: 0, fields: ["kept_field"])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .contextLost(
                "hideKeyboard dismissed the presented context — "
                    + "the field(s) being edited no longer exist: 'lost_field'"
            )
        )
    }

    // MARK: the controls — the ordinary dismiss must stay a success

    func testKeyboardGoneWithEverythingStillThereIsASuccess() {
        let steady = context(sheets: 1, sheetId: "item_edit_sheet", fields: ["note_field"])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: steady, after: steady),
            .dismissed
        )
    }

    func testTheCommonNoSheetScreenIsUntouched() {
        // Strategies 1-3 on a plain screen: no presentation at all, the field
        // survives, nothing new fires. This is the path every existing test
        // takes, and it must keep reading `.dismissed`.
        let before = context(sheets: 0, fields: ["search_field"])
        let after = context(sheets: 0, fields: ["search_field"])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .dismissed
        )
    }

    func testFieldsAppearingIsNotContextLoss() {
        // Retracting the keyboard uncovers what was behind it, so the set
        // GROWS. Only removals are the signal.
        let before = context(sheets: 0, fields: ["note_field"])
        let after = context(sheets: 0, fields: ["note_field", "was_behind_the_keyboard"])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .dismissed
        )
    }

    func testASheetOpeningDuringTheActionIsNotContextLoss() {
        // Count rising is not the shape being watched for.
        let before = context(sheets: 0, fields: ["note_field"])
        let after = context(sheets: 1, sheetId: "something_else", fields: ["note_field"])

        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: true, before: before, after: after),
            .dismissed
        )
    }

    // MARK: the keyboard reading still comes first

    func testKeyboardStillUpIsNotDismissedRegardlessOfContext() {
        let before = context(sheets: 1, sheetId: "s", fields: ["note_field"])
        let after = context(sheets: 0, fields: [])

        // Even with the context destroyed, the honest report is that the
        // action did not do its job; the existing message covers that case.
        XCTAssertEqual(
            KeyboardDismissSafety.verdict(keyboardGone: false, before: before, after: after),
            .notDismissed
        )
    }
}
