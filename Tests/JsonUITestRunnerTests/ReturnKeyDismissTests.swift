import XCTest
@testable import JsonUITestRunner

/// When `hideKeyboard` may press Return (ReturnKeyDismiss.verdict).
final class ReturnKeyDismissTests: XCTestCase {
    func testAQuietReturnOnASingleLineFieldIsPressed() {
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .singleLine, fieldId: "password_field", keyLabels: ["Done"]),
            .press(label: "Done")
        )
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .singleLine, fieldId: "email_field", keyLabels: ["return"]),
            .press(label: "return")
        )
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .singleLine, fieldId: "name_field", keyLabels: ["改行"]),
            .press(label: "改行")
        )
    }

    func testAMultiLineFieldIsRefusedWhateverTheKeySays() {
        // Return inserts a newline there: the value the test typed changes.
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .multiLine, fieldId: "note_field", keyLabels: ["return"]),
            .refuse("the focused field 'note_field' is multi-line, where Return inserts a newline")
        )
    }

    func testAnUnreadableFocusIsRefused() {
        guard case .refuse = ReturnKeyDismiss.verdict(field: .unknown, fieldId: nil, keyLabels: ["return"]) else {
            return XCTFail("a field that could be multi-line was pressed")
        }
    }

    func testAKeyThatNamesAnActionIsRefusedAndNamed() {
        for label in ["Go", "Send", "Search", "Join", "Next", "送信", "検索"] {
            XCTAssertEqual(
                ReturnKeyDismiss.verdict(field: .singleLine, fieldId: "query_field", keyLabels: [label]),
                .refuse("the Return key reads '\(label)', which names an action of its own — "
                    + "press it as a step if that is what the test means"),
                label
            )
        }
    }

    func testTheGlobeKeyIsNotTakenForANextKey() {
        // Boundary of the exact match: "Next keyboard" starts with "next".
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .singleLine, fieldId: "f", keyLabels: ["Next keyboard"]),
            .refuse("no Return key was found on the keyboard")
        )
    }

    func testNoKeyAtAllIsRefused() {
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .singleLine, fieldId: "f", keyLabels: []),
            .refuse("no Return key was found on the keyboard")
        )
    }

    func testAnEmptyIdentifierIsNamedAsNone() {
        XCTAssertEqual(
            ReturnKeyDismiss.verdict(field: .multiLine, fieldId: "", keyLabels: []),
            .refuse("the focused field '(no identifier)' is multi-line, where Return inserts a newline")
        )
    }
}
