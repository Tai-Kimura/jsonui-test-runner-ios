import XCTest
@testable import JsonUITestRunner

/// caseIsolation (screen-test.schema.json): absent / `shared` keeps the
/// once-per-file setup and teardown; `reopen` runs reopen → setup → case →
/// teardown for every case. The runner needs the XCUITest runtime, so the
/// sequence is pinned on `ReopenedCases`, the pure loop the runner delegates to.
final class CaseIsolationTests: XCTestCase {

    private struct Boom: Error, LocalizedError {
        let label: String
        var errorDescription: String? { label }
    }

    private func screenTest(_ extra: String = "") throws -> ScreenTest {
        let json = """
        {
          "type": "screen",
          "source": { "layout": "layouts/x.json" },
          "metadata": { "name": "Iso" },
          \(extra)
          "cases": [
            { "name": "one", "steps": [{ "action": "wait", "ms": 1 }] },
            { "name": "two", "steps": [{ "action": "wait", "ms": 1 }] },
            { "name": "three", "steps": [{ "action": "wait", "ms": 1 }], "skip": true },
            { "name": "four", "steps": [{ "action": "wait", "ms": 1 }] }
          ]
        }
        """
        return try JSONDecoder().decode(ScreenTest.self, from: Data(json.utf8))
    }

    // MARK: decoding

    func testAbsentMeansShared() throws {
        let test = try screenTest()
        XCTAssertNil(test.caseIsolation)
        XCTAssertEqual(test.caseIsolation ?? .shared, .shared)
    }

    func testDecodesBothValues() throws {
        XCTAssertEqual(try screenTest(#""caseIsolation": "shared","#).caseIsolation, .shared)
        XCTAssertEqual(try screenTest(#""caseIsolation": "reopen","#).caseIsolation, .reopen)
    }

    func testRejectsAMisspeltValue() {
        XCTAssertThrowsError(try screenTest(#""caseIsolation": "reOpen","#))
    }

    // MARK: reopen sequence

    private struct Row: Equatable {
        let name: String
        let passed: Bool
        var attempts: Int? = nil
        var skipped = false
        var error: String? = nil
    }

    private func run(
        _ cases: [TestCase],
        retries: Int = 0,
        failSetupOn: Set<Int> = [],
        failBody: @escaping (TestCase, Int) -> Bool = { _, _ in false },
        failTeardownOn: Set<Int> = []
    ) -> (rows: [Row], seq: [String]) {
        var seq: [String] = []
        var setups = 0
        var bodies = 0
        var teardowns = 0
        let rows = ReopenedCases.run(
            cases: cases,
            retries: retries,
            hooks: ReopenedCases.Hooks<Row>(
                gate: { $0.skip == true ? Row(name: $0.name, passed: true, skipped: true) : nil },
                reopen: { _ in seq.append("reopen") },
                setup: {
                    setups += 1
                    seq.append("setup")
                    if failSetupOn.contains(setups) { throw Boom(label: "setup boom \(setups)") }
                },
                body: { testCase in
                    bodies += 1
                    seq.append("case:\(testCase.name)")
                    return Row(name: testCase.name, passed: !failBody(testCase, bodies))
                },
                teardown: {
                    teardowns += 1
                    seq.append("teardown")
                    if failTeardownOn.contains(teardowns) { throw Boom(label: "teardown boom") }
                },
                setupFailed: { testCase, error in
                    Row(name: testCase.name, passed: false, error: error.localizedDescription)
                },
                teardownFailed: { _, error in
                    Row(name: "teardown", passed: false, error: error.localizedDescription)
                },
                isPass: { $0.passed },
                stampAttempts: { row, attempts in
                    var stamped = row
                    stamped.attempts = attempts
                    return stamped
                }
            )
        )
        return (rows, seq)
    }

    func testReopenRunsReopenSetupCaseTeardownOncePerCase() throws {
        let (rows, seq) = run(try screenTest().cases)
        XCTAssertEqual(seq, [
            "reopen", "setup", "case:one", "teardown",
            "reopen", "setup", "case:two", "teardown",
            "reopen", "setup", "case:four", "teardown",
        ])
        XCTAssertEqual(rows.map(\.name), ["one", "two", "three", "four"])
        XCTAssertEqual(rows[2].skipped, true, "a gated case reopens nothing")
        XCTAssertEqual(rows.filter { !$0.skipped }.map(\.attempts), [1, 1, 1])
    }

    func testSetupFailureFailsThatCaseOnlyAndTeardownStillRuns() throws {
        let (rows, seq) = run(try screenTest().cases, failSetupOn: [2])
        XCTAssertEqual(seq, [
            "reopen", "setup", "case:one", "teardown",
            "reopen", "setup", "teardown",
            "reopen", "setup", "case:four", "teardown",
        ])
        XCTAssertEqual(rows.map(\.passed), [true, false, true, true])
        XCTAssertEqual(rows[1].error, "setup boom 2")
    }

    func testAFailedCaseDoesNotStopTheFile() throws {
        let (rows, seq) = run(try screenTest().cases, failBody: { testCase, _ in testCase.name == "one" })
        // The cases after the failure are reopened and run, as on Android and
        // Web ("three" keeps its own skip row).
        XCTAssertEqual(seq, [
            "reopen", "setup", "case:one", "teardown",
            "reopen", "setup", "case:two", "teardown",
            "reopen", "setup", "case:four", "teardown",
        ])
        XCTAssertEqual(rows.map(\.name), ["one", "two", "three", "four"])
        XCTAssertEqual(rows.map(\.passed), [false, true, true, true])
        XCTAssertEqual(rows.map(\.skipped), [false, false, true, false])
    }

    func testEachRetryAttemptReopens() throws {
        let cases = [try screenTest().cases[0]]
        let (rows, seq) = run(cases, retries: 1, failBody: { _, n in n == 1 })
        XCTAssertEqual(seq, [
            "reopen", "setup", "case:one", "teardown",
            "reopen", "setup", "case:one", "teardown",
        ])
        XCTAssertEqual(rows, [Row(name: "one", passed: true, attempts: 2)])
    }

    func testATeardownFailureIsAnExtraRowAfterItsCase() throws {
        let cases = Array(try screenTest().cases.prefix(2))
        let (rows, _) = run(cases, failTeardownOn: [1])
        XCTAssertEqual(rows.map(\.name), ["one", "teardown", "two"])
        XCTAssertEqual(rows[1].error, "teardown boom")
    }
}
