import XCTest
@testable import JsonUITestRunner

/// A failed case does not stop the file: every case after it runs, in both the
/// shared loop and the reopen loop, as on Android and Web. The specimen is the
/// one the three drivers were compared on — [pass, fail, A, B] — and every
/// face records it as passed 3 / failed 1 / skipped 0.
///
/// Until 2.0.0 iOS stopped a file at its first failed case unless
/// `continueOnFailure` was set, and recorded the rest as skipped rows (iOS
/// 1 / 1 / 2 against Android and Web 3 / 1 / 0 on the same file). The setting
/// and the stop are gone.
final class EveryCaseRunsTests: XCTestCase {

    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    /// [pass, fail, A, B], optionally with a gated case after the failure.
    private func cases(withGatedAfterFailure: Bool = false) throws -> [TestCase] {
        let gated = withGatedAfterFailure
            ? #"{ "name": "gated", "skip": true, "steps": [{ "action": "wait", "ms": 1 }] },"#
            : ""
        let json = """
        {
          "type": "screen",
          "source": { "layout": "layouts/x.json" },
          "metadata": { "name": "EveryCase" },
          "cases": [
            { "name": "pass", "steps": [{ "action": "wait", "ms": 1 }] },
            { "name": "fail", "steps": [{ "action": "wait", "ms": 1 }] },
            \(gated)
            { "name": "A", "steps": [{ "action": "wait", "ms": 1 }] },
            { "name": "B", "steps": [{ "action": "wait", "ms": 1 }] }
          ]
        }
        """
        return try JSONDecoder().decode(ScreenTest.self, from: Data(json.utf8)).cases
    }

    private func gate(_ testCase: TestCase) -> TestCaseResult? {
        testCase.skip == true ? TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true) : nil
    }

    private func bodyRow(_ testCase: TestCase) -> TestCaseResult {
        testCase.name == "fail"
            ? TestCaseResult(name: testCase.name, passed: false, duration: 0.1, error: Boom())
            : TestCaseResult(name: testCase.name, passed: true, duration: 0.1)
    }

    private func shared(_ cases: [TestCase]) -> (rows: [TestCaseResult], ran: [String]) {
        var ran: [String] = []
        let rows = SharedCases.run(
            cases: cases,
            hooks: SharedCases.Hooks(
                gate: gate,
                unrunnable: { _ in nil },
                body: { ran.append($0.name); return self.bodyRow($0) }
            )
        )
        return (rows, ran)
    }

    private func reopened(_ cases: [TestCase]) -> (rows: [TestCaseResult], ran: [String]) {
        var ran: [String] = []
        let rows = ReopenedCases.run(
            cases: cases,
            retries: 0,
            hooks: ReopenedCases.Hooks(
                gate: gate,
                reopen: { ran.append("reopen:\($0.name)") },
                setup: {},
                body: { ran.append($0.name); return self.bodyRow($0) },
                teardown: {},
                setupFailed: { testCase, error in
                    TestCaseResult(name: testCase.name, passed: false, duration: 0, error: error)
                },
                teardownFailed: { _, error in
                    TestCaseResult(name: "teardown", passed: false, duration: 0, error: error)
                },
                isPass: { $0.passed },
                stampAttempts: { $0.stamping(attempts: $1) }
            )
        )
        return (rows, ran)
    }

    private func written(_ rows: [TestCaseResult]) -> [[String: Any]] {
        let run = TestRunResult(testName: "EveryCase", caseResults: rows, totalDuration: 0)
        let suites = ResultsWriter.resultsJSON([run], platform: "ios")["suites"] as? [[String: Any]]
        return suites?.first?["results"] as? [[String: Any]] ?? []
    }

    /// The counts Android and Web record for this file.
    private func assertEveryCaseRan(_ rows: [TestCaseResult], caseCount: Int,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let results = written(rows)
        XCTAssertEqual(results.count, caseCount, "one results row per case in the file", file: file, line: line)
        XCTAssertEqual(results.map { $0["caseName"] as? String }, ["pass", "fail", "A", "B"], file: file, line: line)
        XCTAssertEqual(results.map { $0["status"] as? String }, ["passed", "failed", "passed", "passed"],
                       file: file, line: line)
        let statuses = results.compactMap { $0["status"] as? String }
        let counts = ["passed", "failed", "skipped"].map { s in statuses.filter { $0 == s }.count }
        XCTAssertEqual(counts.reduce(0, +), caseCount, file: file, line: line)
        XCTAssertEqual(counts, [3, 1, 0], file: file, line: line)
    }

    // MARK: shared

    func testSharedRunsTheCasesAfterAFailure() throws {
        let cases = try cases()
        let (rows, ran) = shared(cases)
        XCTAssertEqual(ran, ["pass", "fail", "A", "B"])
        assertEveryCaseRan(rows, caseCount: cases.count)
    }

    func testSharedGatedCaseAfterAFailureKeepsItsOwnRow() throws {
        let (rows, ran) = shared(try cases(withGatedAfterFailure: true))
        XCTAssertEqual(ran, ["pass", "fail", "A", "B"], "the gated case runs nothing, the rest run")
        XCTAssertEqual(rows.map(\.name), ["pass", "fail", "gated", "A", "B"])
        XCTAssertEqual(rows.map(\.skipped), [false, false, true, false, false])
    }

    // MARK: reopen

    func testReopenRunsTheCasesAfterAFailure() throws {
        let cases = try cases()
        let (rows, ran) = reopened(cases)
        XCTAssertEqual(ran, ["reopen:pass", "pass", "reopen:fail", "fail", "reopen:A", "A", "reopen:B", "B"])
        assertEveryCaseRan(rows, caseCount: cases.count)
    }

    func testReopenGatedCaseAfterAFailureKeepsItsOwnRow() throws {
        let (rows, ran) = reopened(try cases(withGatedAfterFailure: true))
        XCTAssertEqual(ran, ["reopen:pass", "pass", "reopen:fail", "fail", "reopen:A", "A", "reopen:B", "B"],
                       "a gated case reopens nothing")
        XCTAssertEqual(rows.map(\.name), ["pass", "fail", "gated", "A", "B"])
        XCTAssertEqual(rows.map(\.skipped), [false, false, true, false, false])
    }
}
