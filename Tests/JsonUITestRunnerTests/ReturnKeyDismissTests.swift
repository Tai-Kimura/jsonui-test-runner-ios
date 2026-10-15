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

    // MARK: - Which element is the Return key (returnKeyIndex)

    /// The measured kana layout: a top-left key labelled 完了 comes first in
    /// index order; Return is the bottom-right button.
    func testOnTheKanaLayoutTheBottomMostOfTheTwoIsReturn() {
        let topLeftKey = CGRect(x: 4.7, y: 590, width: 78.3, height: 54)
        let returnButton = CGRect(x: 319, y: 698, width: 78.7, height: 108)
        XCTAssertEqual(ReturnKeyDismiss.returnKeyIndex(frames: [topLeftKey, returnButton]), 1)
        XCTAssertEqual(ReturnKeyDismiss.returnKeyIndex(frames: [returnButton, topLeftKey]), 0, "order does not decide it")
    }

    /// One element carrying the label (the English layout): that one, as before.
    func testASingleMatchIsTakenAsItIs() {
        XCTAssertEqual(ReturnKeyDismiss.returnKeyIndex(frames: [CGRect(x: 300, y: 760, width: 90, height: 42)]), 0)
    }

    func testEqualBottomsKeepTheFirst() {
        let a = CGRect(x: 0, y: 700, width: 50, height: 40), b = CGRect(x: 60, y: 700, width: 50, height: 40)
        XCTAssertEqual(ReturnKeyDismiss.returnKeyIndex(frames: [a, b]), 0)
    }

    func testNoMatchIsNil() {
        XCTAssertNil(ReturnKeyDismiss.returnKeyIndex(frames: []))
    }
}
