import XCTest
@testable import JsonUITestRunner

/// selectOption selector precedence (actions.schema.json, 169ad16): index,
/// then value, then label; a lower selector is ignored when a higher one is
/// present. The executor used to read `label` first, so the consumer step
/// that carried `index` plus a note in `label` selected the note on iOS and
/// the indexed option on android — the shape the first test pins.
final class SelectOptionSelectorTests: XCTestCase {

    func testAllThreePresentIndexWins() {
        // The consumer's shape: an index, a value, and a free-text note in
        // `label` that was never meant to be selected.
        XCTAssertEqual(
            SelectOptionSelector.resolve(index: 2, value: "tokyo", label: "pick the third one"),
            .index(2)
        )
    }

    func testIndexZeroIsPresentNotAbsent() {
        // 0 is a selector, not "no selector" — the falsy-zero trap other
        // drivers' languages invite.
        XCTAssertEqual(
            SelectOptionSelector.resolve(index: 0, value: "tokyo", label: "Tokyo"),
            .index(0)
        )
    }

    func testValueBeatsLabel() {
        XCTAssertEqual(
            SelectOptionSelector.resolve(index: nil, value: "tokyo", label: "Tokyo"),
            .value("tokyo")
        )
    }

    func testLabelAloneSelectsByLabel() {
        // For selectOption, `label` keeps its option-text meaning: a note
        // placed here IS the option to select, and this is where it lands.
        XCTAssertEqual(
            SelectOptionSelector.resolve(index: nil, value: nil, label: "Tokyo"),
            .label("Tokyo")
        )
    }

    func testNoSelectorIsNil() {
        XCTAssertNil(SelectOptionSelector.resolve(index: nil, value: nil, label: nil))
    }
}
