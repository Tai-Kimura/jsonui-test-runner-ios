import XCTest
@testable import JsonUITestRunner

/// `continueOnFailure: false` (the default) stops a file at its first failed
/// case. The cases after the stop used to appear nowhere in results.json; now
/// each gets a skipped row with no skipReason, in both the shared loop and the
/// reopen loop, so the row count equals the file's case count.
final class CaseStopTests: XCTestCase {

    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    /// [pass, fail, A, B], optionally with a gated case after the failure.
    private func cases(withGatedAfterStop: Bool = false) throws -> [TestCase] {
        let gated = withGatedAfterStop
            ? #"{ "name": "gated", "skip": true, "steps": [{ "action": "wait", "ms": 1 }] },"#
            : ""
        let json = """
        {
          "type": "screen",
          "source": { "layout": "layouts/x.json" },
          "metadata": { "name": "Stop" },
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

    private func shared(_ cases: [TestCase], continueOnFailure: Bool) -> (rows: [TestCaseResult], ran: [String]) {
        var ran: [String] = []
        let rows = SharedCases.run(
            cases: cases,
            continueOnFailure: continueOnFailure,
            hooks: SharedCases.Hooks(
                gate: gate,
                unrunnable: { _ in nil },
                body: { ran.append($0.name); return self.bodyRow($0) },
                stoppedAfterFailure: { CaseStop.skippedRow($0) },
                isPass: { $0.passed }
            )
        )
        return (rows, ran)
    }

    private func reopened(_ cases: [TestCase], continueOnFailure: Bool) -> (rows: [TestCaseResult], ran: [String]) {
        var ran: [String] = []
        let rows = ReopenedCases.run(
            cases: cases,
            retries: 0,
            continueOnFailure: continueOnFailure,
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
                stoppedAfterFailure: { CaseStop.skippedRow($0) },
                isPass: { $0.passed },
                stampAttempts: { $0.stamping(attempts: $1) }
            )
        )
        return (rows, ran)
    }

    private func written(_ rows: [TestCaseResult]) -> [[String: Any]] {
        let run = TestRunResult(testName: "Stop", caseResults: rows, totalDuration: 0)
        let suites = ResultsWriter.resultsJSON([run], platform: "ios")["suites"] as? [[String: Any]]
        return suites?.first?["results"] as? [[String: Any]] ?? []
    }

    private func assertStopped(_ rows: [TestCaseResult], caseCount: Int, file: StaticString = #filePath, line: UInt = #line) {
        let results = written(rows)
        XCTAssertEqual(results.count, caseCount, "one results row per case in the file", file: file, line: line)
        XCTAssertEqual(results.map { $0["caseName"] as? String }, ["pass", "fail", "A", "B"], file: file, line: line)
        XCTAssertEqual(results.map { $0["status"] as? String }, ["passed", "failed", "skipped", "skipped"],
                       file: file, line: line)
        for row in results[2...] {
            XCTAssertNil(row["skipReason"], "a stop is not a gate: no skipReason", file: file, line: line)
            XCTAssertEqual(row["durationMs"] as? Int, 0, file: file, line: line)
            XCTAssertNil(row["attempts"], file: file, line: line)
            XCTAssertNil(row["failureReason"], file: file, line: line)
        }
        let statuses = results.compactMap { $0["status"] as? String }
        let passed = statuses.filter { $0 == "passed" }.count
        let failed = statuses.filter { $0 == "failed" }.count
        let skipped = statuses.filter { $0 == "skipped" }.count
        XCTAssertEqual(passed + failed + skipped, caseCount, file: file, line: line)
        XCTAssertEqual([passed, failed, skipped], [1, 1, 2], file: file, line: line)
    }

    // MARK: shared

    func testSharedRecordsTheCasesAfterTheStopAsSkipped() throws {
        let cases = try cases()
        let (rows, ran) = shared(cases, continueOnFailure: false)
        XCTAssertEqual(ran, ["pass", "fail"], "nothing runs after the stop")
        assertStopped(rows, caseCount: cases.count)
    }

    func testSharedWithContinueOnFailureMarksNothingSkipped() throws {
        let (rows, ran) = shared(try cases(), continueOnFailure: true)
        XCTAssertEqual(ran, ["pass", "fail", "A", "B"])
        XCTAssertEqual(written(rows).map { $0["status"] as? String }, ["passed", "failed", "passed", "passed"])
    }

    func testSharedGatedCaseAfterTheStopKeepsItsOwnRow() throws {
        let cases = try cases(withGatedAfterStop: true)
        let (rows, _) = shared(cases, continueOnFailure: false)
        XCTAssertEqual(rows.map(\.name), ["pass", "fail", "gated", "A", "B"])
        XCTAssertEqual(rows.count, cases.count)
        guard rows.count >= 3 else { return }
        XCTAssertEqual(rows[2].skipped, true)
        XCTAssertNil(rows[2].skipReason)
    }

    // MARK: reopen

    func testReopenRecordsTheCasesAfterTheStopAsSkipped() throws {
        let cases = try cases()
        let (rows, ran) = reopened(cases, continueOnFailure: false)
        XCTAssertEqual(ran, ["reopen:pass", "pass", "reopen:fail", "fail"], "nothing reopens after the stop")
        assertStopped(rows, caseCount: cases.count)
    }

    func testReopenWithContinueOnFailureMarksNothingSkipped() throws {
        let (rows, _) = reopened(try cases(), continueOnFailure: true)
        XCTAssertEqual(written(rows).map { $0["status"] as? String }, ["passed", "failed", "passed", "passed"])
    }

    func testReopenGatedCaseAfterTheStopKeepsItsOwnRow() throws {
        let cases = try cases(withGatedAfterStop: true)
        let platformGate: (TestCase) -> TestCaseResult? = {
            $0.skip == true
                ? TestCaseResult(name: $0.name, passed: true, duration: 0, skipped: true, skipReason: .platform)
                : nil
        }
        let rows = ReopenedCases.run(
            cases: cases, retries: 0, continueOnFailure: false,
            hooks: ReopenedCases.Hooks(
                gate: platformGate,
                reopen: { _ in }, setup: {}, body: bodyRow, teardown: {},
                setupFailed: { t, e in TestCaseResult(name: t.name, passed: false, duration: 0, error: e) },
                teardownFailed: { _, e in TestCaseResult(name: "teardown", passed: false, duration: 0, error: e) },
                stoppedAfterFailure: { CaseStop.skippedRow($0) },
                isPass: { $0.passed },
                stampAttempts: { $0.stamping(attempts: $1) }
            )
        )
        XCTAssertEqual(rows.map(\.name), ["pass", "fail", "gated", "A", "B"])
        guard rows.count == 5 else { return }
        XCTAssertEqual(rows[2].skipReason, .platform, "a gate keeps its own reason after the stop")
        XCTAssertEqual(rows[3].skipReason, nil)
    }

    // MARK: the row itself

    func testTheStopRowIsSkippedWithNoReason() throws {
        let row = CaseStop.skippedRow(try cases()[2])
        XCTAssertEqual(row.name, "A")
        XCTAssertTrue(row.skipped)
        XCTAssertTrue(row.passed)
        XCTAssertNil(row.skipReason)
        XCTAssertNil(row.attempts)
        XCTAssertEqual(row.duration, 0)
    }
}
