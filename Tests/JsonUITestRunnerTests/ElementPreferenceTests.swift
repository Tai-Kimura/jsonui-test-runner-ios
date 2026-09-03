import XCTest
@testable import JsonUITestRunner

/// The tap target among several elements sharing an identifier. These pin
/// the rule the per-type loop implemented, so the single-query rewrite that
/// replaced it cannot quietly change which element gets tapped.
final class ElementPreferenceTests: XCTestCase {

    func testAnInteractiveTypeBeatsAPlainOne() {
        // The mirror StaticText of a control carries the same id.
        XCTAssertEqual(ElementPreference.interactiveWinner([.staticText, .button]), 1)
        XCTAssertEqual(ElementPreference.interactiveWinner([.button, .staticText]), 0)
    }

    func testTheOrderOfPreferenceIsKeptWhateverTheTreeOrder() {
        // The old loop probed button before switch, so a tree that lists the
        // switch first must still resolve to the button.
        XCTAssertEqual(ElementPreference.interactiveWinner([.switch, .button]), 1)
        XCTAssertEqual(ElementPreference.interactiveWinner([.cell, .link, .slider]), 2)
        XCTAssertEqual(ElementPreference.interactiveWinner([.cell, .button]), 1)
    }

    func testEqualTypesGoToTheEarlierCandidate() {
        XCTAssertEqual(ElementPreference.interactiveWinner([.button, .button]), 0)
    }

    func testNoInteractiveCandidateIsNoWinner() {
        // The caller then falls back to hittability, and finally to the
        // first match — neither of which this decides.
        XCTAssertNil(ElementPreference.interactiveWinner([.staticText, .image, .other]))
        XCTAssertNil(ElementPreference.interactiveWinner([]))
    }

    func testEveryTypeTheOldLoopProbedIsStillPreferred() {
        // The list IS the contract: dropping one silently changes which
        // element a consumer's tap lands on.
        XCTAssertEqual(ElementPreference.interactive, [
            .button, .switch, .toggle, .checkBox, .segmentedControl,
            .slider, .stepper, .link, .cell,
        ])
        for type in ElementPreference.interactive {
            XCTAssertEqual(ElementPreference.interactiveWinner([.staticText, type]), 1,
                           "\(type.rawValue) must beat a plain match")
        }
    }

    // MARK: - reach, not just preference
    //
    // 1.9.6 replaced nine per-type queries — each unbounded in POSITION —
    // with one query whose scan stopped at eight candidates, and applied
    // that cap to the interactive search as well. With nine or more
    // elements sharing an id and the interactive one late, the resolver
    // stopped finding it and fell through to hittability: it could tap the
    // label instead of the control. These arms pin the reach; the priority
    // arms above never could, because reach is not a property of the pure
    // ordering function they exercise.

    func testACapMissWithMoreCandidatesFallsBackToTheTypedSearch() {
        XCTAssertTrue(ElementPreference.needsTypedSearch(totalMatches: 9, firstPassWinner: nil))
        XCTAssertTrue(ElementPreference.needsTypedSearch(totalMatches: 40, firstPassWinner: nil))
    }

    func testTheFastPathIsNotPaidForWhenEverythingFitsInTheFirstPass() {
        // Eight or fewer: the single query already saw every candidate, so
        // asking nine more times would be the cost 1.9.6 removed.
        XCTAssertFalse(ElementPreference.needsTypedSearch(totalMatches: 8, firstPassWinner: nil))
        XCTAssertFalse(ElementPreference.needsTypedSearch(totalMatches: 1, firstPassWinner: nil))
        XCTAssertFalse(ElementPreference.needsTypedSearch(totalMatches: 0, firstPassWinner: nil))
    }

    func testAWinnerInTheFirstPassEndsIt() {
        // However many candidates there are, a found control is the answer.
        XCTAssertFalse(ElementPreference.needsTypedSearch(totalMatches: 40, firstPassWinner: 3))
        XCTAssertFalse(ElementPreference.needsTypedSearch(totalMatches: 9, firstPassWinner: 0))
    }

    func testTheCapIsTheOneTheResolverUses() {
        // The boundary is stated once and read from there: a resolver that
        // scans a different number than this would re-open the same gap.
        XCTAssertEqual(ElementPreference.firstPassCap, 8)
        XCTAssertFalse(ElementPreference.needsTypedSearch(
            totalMatches: ElementPreference.firstPassCap, firstPassWinner: nil))
        XCTAssertTrue(ElementPreference.needsTypedSearch(
            totalMatches: ElementPreference.firstPassCap + 1, firstPassWinner: nil))
    }

    /// The typed search is the only thing restoring the pre-1.9.6 reach, and
    /// nothing in the pure arms above would notice its removal — the same
    /// blind spot that let the cap ship. Hold it at the source.
    func testTheResolverStillHasATypedSearchForCandidatesPastTheCap() throws {
        let source = try Self.actionExecutorSource()
        XCTAssertTrue(source.contains("ElementPreference.needsTypedSearch("),
                      "the resolver must still consult the reach policy")
        XCTAssertTrue(source.contains("for type in ElementPreference.interactive"),
                      "the typed search past the cap must still exist")
    }

    /// On a query that matches nothing, `allElementsBoundByIndex` and
    /// `firstMatch.elementType` do not return empty or zero — they RAISE
    /// ("Failed to get matching snapshot: No matches found"), measured
    /// 2026-09-04 while building the replacement. An element that is not
    /// there is the most common path in the driver, so reaching for either
    /// of those without a count guard turns a miss into an exception. No
    /// unit test can construct an empty query without an app, so the guard
    /// is held here: the source must not call them.
    func testTheResolverNeverCallsAnApiThatRaisesOnAnEmptyQuery() throws {
        let source = try Self.actionExecutorSource()
        let offenders = source.split(separator: "\n").enumerated().filter { _, line in
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//") && !code.hasPrefix("///") && !code.hasPrefix("*") else { return false }
            // The one guarded use is the helper that makes it safe.
            if code.contains("query.count > 0 ? query.allElementsBoundByIndex : []") { return false }
            return code.contains("allElementsBoundByIndex") || code.contains("firstMatch.elementType")
        }.map { "\($0.offset + 1): \($0.element)" }
        XCTAssertEqual(offenders, [],
                       "these raise on an empty query; use allElements(_:) or index into matches.count")
    }

    private static func actionExecutorSource() throws -> String {
        // Tests run from the package, so walk up to Sources/.
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("Sources/JsonUITestRunner/Actions/ActionExecutor.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw XCTSkip("ActionExecutor.swift not reachable from \(#filePath)")
    }
}
