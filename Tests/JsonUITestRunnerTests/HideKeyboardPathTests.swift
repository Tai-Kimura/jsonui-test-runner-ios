import XCTest
@testable import JsonUITestRunner

/// The line each of `hideKeyboard`'s four exits prints.
///
/// These exist because a consumer run of 3/3 passing could not say whether
/// the risky drag had run at all (2026-09-04, driver 1.9.13). The texts are
/// asserted verbatim: they are what a reader greps for, so changing one is a
/// change to an interface, not to a string.
final class HideKeyboardPathTests: XCTestCase {
    func testTheNoOpExitSaysNothingWasDone() {
        XCTAssertEqual(
            HideKeyboardPath.notVisible.note,
            "hideKeyboard: keyboard not visible — nothing to do"
        )
    }

    func testTheDismissKeyExitNamesItself() {
        XCTAssertEqual(
            HideKeyboardPath.dismissKey.note,
            "hideKeyboard: dismissed via dismiss key"
        )
    }

    func testTheAccessoryDoneExitNamesItself() {
        XCTAssertEqual(
            HideKeyboardPath.accessoryDone.note,
            "hideKeyboard: dismissed via accessory Done"
        )
    }

    func testTheDragExitReportsWhatSurvivedIt() {
        // The counts are the reading taken after the drag. They are in the
        // line so a passing run still shows whether a sheet was up while the
        // drag ran — which is the whole question this note was added for.
        XCTAssertEqual(
            HideKeyboardPath.drag(sheets: 1, fields: 2).note,
            "hideKeyboard: dismissed via drag (context intact: sheets=1, fields=2)"
        )
        XCTAssertEqual(
            HideKeyboardPath.drag(sheets: 0, fields: 0).note,
            "hideKeyboard: dismissed via drag (context intact: sheets=0, fields=0)"
        )
    }

    // MARK: the controls

    func testEveryPathIsDistinguishableFromEveryOther() {
        // A note that does not separate the exits is the same defect with
        // more output: the reason for the 3/3 would still be unreadable.
        let notes = [
            HideKeyboardPath.notVisible.note,
            HideKeyboardPath.dismissKey.note,
            HideKeyboardPath.accessoryDone.note,
            HideKeyboardPath.drag(sheets: 0, fields: 0).note
        ]
        XCTAssertEqual(Set(notes).count, notes.count, "two exits print the same line")
    }

    func testEveryNoteIsGreppableAsThisAction() {
        for note in [
            HideKeyboardPath.notVisible.note,
            HideKeyboardPath.dismissKey.note,
            HideKeyboardPath.accessoryDone.note,
            HideKeyboardPath.drag(sheets: 3, fields: 4).note
        ] {
            XCTAssertTrue(
                note.hasPrefix("hideKeyboard: "),
                "a line without the action prefix cannot be grepped out of a run: \(note)"
            )
            XCTAssertFalse(note.isEmpty)
        }
    }

    func testTheDragNoteCarriesTheCountsItClaimsToCarry() {
        // Guards the format, not just the presence: a reader parses these.
        let note = HideKeyboardPath.drag(sheets: 2, fields: 7).note
        XCTAssertTrue(note.contains("sheets=2"), note)
        XCTAssertTrue(note.contains("fields=7"), note)
    }

    // The coverage control — "no exit is missing a note" — is NOT a test
    // here, deliberately. Any test of it would iterate a list of paths
    // written by the same hand that would forget the fifth one. `note` is a
    // non-optional String over a switch with no `default:`, so a new case
    // fails to compile until it says which exit it is. The compiler holds
    // the denominator; a hand-written array would only appear to.
}
