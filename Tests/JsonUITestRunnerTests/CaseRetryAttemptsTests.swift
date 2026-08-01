import XCTest
@testable import JsonUITestRunner

/// attempts/flaky accounting (results.schema.json): the CaseRetry loop is
/// the runner's retry unit (the runner itself needs the XCUITest runtime,
/// the loop does not), and ResultsWriter is the emission point.
final class CaseRetryAttemptsTests: XCTestCase {

    // MARK: CaseRetry loop

    func testPassesOnSecondAttempt() {
        var calls = 0
        let (result, attempts) = CaseRetry.run(retries: 2, isPass: { $0 }) { () -> Bool in
            calls += 1
            return calls >= 2
        }
        XCTAssertTrue(result)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(calls, 2)
    }

    func testExhaustsRetries() {
        var calls = 0
        let (result, attempts) = CaseRetry.run(retries: 2, isPass: { $0 }) { () -> Bool in
            calls += 1
            return false
        }
        XCTAssertFalse(result)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(calls, 3)
    }

    func testZeroRetriesRunsExactlyOnce() {
        var calls = 0
        let (_, attempts) = CaseRetry.run(retries: 0, isPass: { $0 }) { () -> Bool in
            calls += 1
            return false
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(calls, 1)
    }

    func testNegativeRetriesClampToSingleRun() {
        var calls = 0
        let (_, attempts) = CaseRetry.run(retries: -5, isPass: { $0 }) { () -> Bool in
            calls += 1
            return false
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(calls, 1)
    }

    func testOnRetryReportsTheAttemptAboutToRun() {
        var seen: [[Int]] = []
        _ = CaseRetry.run(
            retries: 2,
            isPass: { $0 },
            onRetry: { n, max in seen.append([n, max]) }
        ) { false }
        XCTAssertEqual(seen, [[2, 3], [3, 3]])
    }

    // MARK: ResultsWriter emission

    private func firstRow(_ caseResult: TestCaseResult) throws -> [String: Any] {
        let run = TestRunResult(testName: "T", caseResults: [caseResult], totalDuration: 0.1)
        let payload = ResultsWriter.resultsJSON([run], platform: "ios")
        let suites = try XCTUnwrap(payload["suites"] as? [[String: Any]])
        let results = try XCTUnwrap(suites[0]["results"] as? [[String: Any]])
        return results[0]
    }

    func testFirstRunPassEmitsAttemptsOneAndNoFlaky() throws {
        let row = try firstRow(TestCaseResult(name: "c", passed: true, duration: 0.1, attempts: 1))
        XCTAssertEqual(row["attempts"] as? Int, 1)
        XCTAssertNil(row["flaky"])
    }

    func testRetriedPassEmitsFlaky() throws {
        let row = try firstRow(TestCaseResult(name: "c", passed: true, duration: 0.1, attempts: 2))
        XCTAssertEqual(row["attempts"] as? Int, 2)
        XCTAssertEqual(row["flaky"] as? Bool, true)
    }

    func testExhaustedFailureEmitsAttemptsButNeverFlaky() throws {
        let row = try firstRow(TestCaseResult(
            name: "c",
            passed: false,
            duration: 0.1,
            error: TestRunnerError.setupFailed(reason: "x"),
            attempts: 3
        ))
        XCTAssertEqual(row["attempts"] as? Int, 3)
        XCTAssertNil(row["flaky"])
        XCTAssertEqual(row["status"] as? String, "failed")
    }

    func testSkippedRowsCarryNeitherAttemptsNorFlaky() throws {
        let row = try firstRow(TestCaseResult(name: "c", passed: true, duration: 0, skipped: true))
        XCTAssertNil(row["attempts"])
        XCTAssertNil(row["flaky"])
    }
}
