import XCTest
@testable import JsonUITestRunner

/// Progress records (progress.schema.json). The runner itself needs the
/// XCUITest runtime; the record builder, the per-attempt pairs around
/// CaseRetry, the reopen sequence's lines and the run_end counts do not, so
/// they are pinned here.
///
/// Every line any test here produces is printed at the end, prefixed
/// `PROGRESS_RECORD `, so a script can validate them against the canonical
/// schema — the keys this file asserts are a transcription, the schema is the
/// authority.
final class ProgressReporterTests: XCTestCase {

    private static var produced: [String] = []

    override class func tearDown() {
        for line in produced { print("PROGRESS_RECORD \(line)") }
        super.tearDown()
    }

    private final class RecordingSink: ProgressSink {
        var lines: [String] = []
        func write(_ line: String) throws {
            lines.append(line)
            ProgressReporterTests.produced.append(line)
        }
        var records: [[String: Any]] {
            lines.map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        }
        var events: [String] { records.map { $0["event"] as! String } }
    }

    private struct SinkFailure: Error {}

    private final class ThrowingSink: ProgressSink {
        var calls = 0
        func write(_ line: String) throws {
            calls += 1
            throw SinkFailure()
        }
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000.123)
    private let fixedRun = UUID(uuidString: "6F9619FF-8B86-4D01-B42D-00C04FC964FF")!

    private func reporter(_ sink: ProgressSink?) -> TestProgressReporter {
        let date = fixedDate, run = fixedRun
        return TestProgressReporter(sink: sink, now: { date }, makeRunId: { run })
    }

    private let aCase = ProgressRecord.Case(file: "screens/login/login.test.json", test: "login", name: "shows the form")

    private func keys(_ record: [String: Any]) -> Set<String> { Set(record.keys) }

    // MARK: Each event's exact keys

    func testRunStartKeysWithDeviceAndUDID() {
        let sink = RecordingSink()
        reporter(sink).runStarted(files: 1, environment: [
            "SIMULATOR_DEVICE_NAME": "iPhone 16 Pro",
            "SIMULATOR_UDID": "A2B58AAF-7CF3-431E-897E-AB0209F96B9F",
        ])
        let record = sink.records[0]
        XCTAssertEqual(keys(record), ["v", "t", "platform", "run", "event", "files", "device", "deviceId"])
        XCTAssertEqual(record["v"] as? Int, 1)
        XCTAssertEqual(record["t"] as? Int64, 1_760_000_000_123)
        XCTAssertEqual(record["platform"] as? String, "ios")
        XCTAssertEqual(record["run"] as? String, "6f9619ff-8b86-4d01-b42d-00c04fc964ff")
        XCTAssertEqual(record["event"] as? String, "run_start")
        XCTAssertEqual(record["files"] as? Int, 1)
        XCTAssertEqual(record["device"] as? String, "iPhone 16 Pro")
        XCTAssertEqual(record["deviceId"] as? String, "A2B58AAF-7CF3-431E-897E-AB0209F96B9F")
    }

    func testRunStartWithoutTheSimulatorEnvironmentHasNoDeviceId() {
        let sink = RecordingSink()
        reporter(sink).runStarted(files: 1, environment: [:])
        let record = sink.records[0]
        XCTAssertNil(record["deviceId"])
        // The device falls back to UIDevice's name on iOS; nothing on macOS.
        #if canImport(UIKit) && !os(macOS)
        XCTAssertEqual(record["device"] as? String, UIDevice.current.name)
        XCTAssertEqual(keys(record), ["v", "t", "platform", "run", "event", "files", "device"])
        #else
        XCTAssertEqual(keys(record), ["v", "t", "platform", "run", "event", "files"])
        #endif
    }

    func testCaseStartKeys() {
        let sink = RecordingSink()
        reporter(sink).caseStarted(aCase, attempt: 1)
        let record = sink.records[0]
        XCTAssertEqual(keys(record), ["v", "t", "platform", "run", "event", "file", "test", "case", "attempt"])
        XCTAssertEqual(record["event"] as? String, "case_start")
        XCTAssertEqual(record["file"] as? String, "screens/login/login.test.json")
        XCTAssertEqual(record["test"] as? String, "login")
        XCTAssertEqual(record["case"] as? String, "shows the form")
        XCTAssertEqual(record["attempt"] as? Int, 1)
    }

    func testCaseEndKeys() {
        let sink = RecordingSink()
        reporter(sink).caseEnded(aCase, attempt: 2, passed: false, duration: 1.2345)
        let record = sink.records[0]
        XCTAssertEqual(keys(record), ["v", "t", "platform", "run", "event", "file", "test", "case", "attempt", "status", "durationMs"])
        XCTAssertEqual(record["event"] as? String, "case_end")
        XCTAssertEqual(record["attempt"] as? Int, 2)
        XCTAssertEqual(record["status"] as? String, "failed")
        XCTAssertEqual(record["durationMs"] as? Int, 1234)
    }

    func testRunEndKeys() {
        let sink = RecordingSink()
        reporter(sink).runEnded(rows: [])
        XCTAssertEqual(keys(sink.records[0]), ["v", "t", "platform", "run", "event", "passed", "failed", "skipped"])
        XCTAssertEqual(sink.records[0]["event"] as? String, "run_end")
    }

    /// The slash in a path is written as is (`.withoutEscapingSlashes`): the
    /// same JSON either way, but a reader grepping for the path finds it.
    func testLineIsOneLineOfJSON() {
        let sink = RecordingSink()
        reporter(sink).caseStarted(aCase, attempt: 1)
        XCTAssertFalse(sink.lines[0].contains("\n"))
        XCTAssertTrue(sink.lines[0].contains("\"screens/login/login.test.json\""))
    }

    // MARK: Skipped

    func testSkippedIsOneCaseEndWithAttemptZero() {
        let sink = RecordingSink()
        reporter(sink).caseSkipped(aCase)
        XCTAssertEqual(sink.events, ["case_end"])
        let record = sink.records[0]
        XCTAssertEqual(keys(record), ["v", "t", "platform", "run", "event", "file", "test", "case", "attempt", "status", "durationMs"])
        XCTAssertEqual(record["attempt"] as? Int, 0)
        XCTAssertEqual(record["status"] as? String, "skipped")
        XCTAssertEqual(record["durationMs"] as? Int, 0)
    }

    // MARK: Truncation

    func testTwoHundredCharactersAreNotCut() {
        let sink = RecordingSink()
        let name = String(repeating: "a", count: 200)
        reporter(sink).caseStarted(.init(file: "f.test.json", test: "t", name: name), attempt: 1)
        XCTAssertEqual(sink.records[0]["case"] as? String, name)
        XCTAssertNil(sink.records[0]["truncated"])
    }

    func testTwoHundredAndOneCharactersAreCutWithAnEllipsis() {
        let sink = RecordingSink()
        let name = String(repeating: "a", count: 201)
        reporter(sink).caseEnded(.init(file: "f.test.json", test: "t", name: name), attempt: 1, passed: true, duration: 0)
        let cut = sink.records[0]["case"] as? String
        XCTAssertEqual(cut, String(repeating: "a", count: 200) + "\u{2026}")
        XCTAssertEqual(cut?.unicodeScalars.count, 201)
        XCTAssertEqual(sink.records[0]["truncated"] as? Bool, true)
    }

    /// Non-ASCII: counted in characters, not bytes ("あ" is 3 bytes in UTF-8).
    func testNonASCIIIsCountedInCharactersNotBytes() {
        let sink = RecordingSink()
        let r = reporter(sink)
        r.caseStarted(.init(file: "f.test.json", test: String(repeating: "あ", count: 200), name: "c"), attempt: 1)
        r.caseStarted(.init(file: "f.test.json", test: String(repeating: "あ", count: 201), name: "c"), attempt: 1)
        XCTAssertEqual(sink.records[0]["test"] as? String, String(repeating: "あ", count: 200))
        XCTAssertNil(sink.records[0]["truncated"])
        XCTAssertEqual(sink.records[1]["test"] as? String, String(repeating: "あ", count: 200) + "…")
        XCTAssertEqual(sink.records[1]["truncated"] as? Bool, true)
    }

    /// Code points, not UTF-16 units: 200 emoji outside the BMP are 400
    /// UTF-16 units and must not be cut.
    func testAstralCharactersAreCountedAsOneEach() {
        let sink = RecordingSink()
        let name = String(repeating: "😀", count: 200)
        reporter(sink).caseStarted(.init(file: "f.test.json", test: "t", name: name), attempt: 1)
        XCTAssertEqual(sink.records[0]["case"] as? String, name)
        XCTAssertNil(sink.records[0]["truncated"])
    }

    func testALongFileAloneMarksTheLineTruncated() {
        let sink = RecordingSink()
        let file = String(repeating: "d/", count: 120) + "x.test.json"
        reporter(sink).caseSkipped(.init(file: file, test: "t", name: "c"))
        XCTAssertEqual((sink.records[0]["file"] as? String)?.unicodeScalars.count, 201)
        XCTAssertEqual(sink.records[0]["truncated"] as? Bool, true)
        XCTAssertEqual(sink.records[0]["test"] as? String, "t")
    }

    // MARK: Per-attempt pairs (CaseRetry)

    func testOnePairPerAttemptAndTheLastIsTheCases() {
        let sink = RecordingSink()
        var calls = 0
        let (result, attempts) = reporter(sink).retrying(aCase, retries: 2, isPass: { $0 }) { () -> Bool in
            calls += 1
            return calls == 3
        }
        XCTAssertTrue(result)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(sink.events, ["case_start", "case_end", "case_start", "case_end", "case_start", "case_end"])
        XCTAssertEqual(sink.records.map { $0["attempt"] as? Int }, [1, 1, 2, 2, 3, 3])
        let ends = sink.records.filter { $0["event"] as? String == "case_end" }
        XCTAssertEqual(ends.map { $0["status"] as? String }, ["failed", "failed", "passed"])
    }

    func testNoRetriesIsOnePair() {
        let sink = RecordingSink()
        _ = reporter(sink).retrying(aCase, retries: 0, isPass: { $0 }) { false }
        XCTAssertEqual(sink.events, ["case_start", "case_end"])
        XCTAssertEqual(sink.records[1]["status"] as? String, "failed")
    }

    func testAFailedRowThatNeverRanIsOneFailedPair() {
        let sink = RecordingSink()
        reporter(sink).caseFailedWithoutRunning(aCase)
        XCTAssertEqual(sink.events, ["case_start", "case_end"])
        XCTAssertEqual(sink.records[1]["attempt"] as? Int, 1)
        XCTAssertEqual(sink.records[1]["status"] as? String, "failed")
    }

    // MARK: run / run_end

    func testEveryLineOfARunCarriesTheSameLowerCaseRunAndANewRunGetsANewOne() {
        let sink = RecordingSink()
        let r = TestProgressReporter(sink: sink)
        r.runStarted(files: 1, environment: [:])
        r.caseSkipped(aCase)
        r.runEnded(rows: [])
        r.runStarted(files: 1, environment: [:])
        let runs = sink.records.map { $0["run"] as! String }
        XCTAssertEqual(Set(runs.prefix(3)).count, 1)
        XCTAssertNotEqual(runs[0], runs[3])
        let pattern = try! NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
        for run in runs {
            XCTAssertNotNil(pattern.firstMatch(in: run, range: NSRange(run.startIndex..., in: run)), run)
        }
    }

    /// Counted as results.json counts: a skipped row is skipped although its
    /// `passed` is true, a teardown row is a failure, one per row.
    func testRunEndCountsAsResultsJSONDoes() {
        let rows = [
            TestCaseResult(name: "a", passed: true, duration: 1, attempts: 1),
            TestCaseResult(name: "b", passed: true, duration: 1, attempts: 2),
            TestCaseResult(name: "c", passed: false, duration: 1, attempts: 3),
            TestCaseResult(name: "d", passed: true, duration: 0, skipped: true),
            TestCaseResult(name: "e", passed: true, duration: 0, skipped: true, skipReason: .platform),
            TestCaseResult(name: "teardown", passed: false, duration: 0),
        ]
        let sink = RecordingSink()
        reporter(sink).runEnded(rows: rows)
        XCTAssertEqual(sink.records[0]["passed"] as? Int, 2)
        XCTAssertEqual(sink.records[0]["failed"] as? Int, 2)
        XCTAssertEqual(sink.records[0]["skipped"] as? Int, 2)

        let written = ResultsWriter.resultsJSON([TestRunResult(testName: "t", caseResults: rows, totalDuration: 1)], platform: "ios")
        let statuses = ((written["suites"] as! [[String: Any]])[0]["results"] as! [[String: Any]]).map { $0["status"] as! String }
        XCTAssertEqual(statuses.filter { $0 == "passed" }.count, 2)
        XCTAssertEqual(statuses.filter { $0 == "failed" }.count, 2)
        XCTAssertEqual(statuses.filter { $0 == "skipped" }.count, 2)
    }

    func testTimeIsIntegerEpochMilliseconds() {
        XCTAssertEqual(ProgressRecord.milliseconds(1.9999), 1999)
        XCTAssertEqual(ProgressRecord.milliseconds(.nan), 0)
        XCTAssertEqual(ProgressRecord.milliseconds(.infinity), 0)
        XCTAssertEqual(ProgressRecord.milliseconds(-1), 0)
        let sink = RecordingSink()
        reporter(sink).runEnded(rows: [])
        XCTAssertTrue(sink.lines[0].contains("\"t\":1760000000123"), sink.lines[0])
    }

    // MARK: The sink never changes a result

    func testAMissingSinkDoesNothing() {
        let r = reporter(nil)
        r.runStarted(files: 1, environment: [:])
        r.caseSkipped(aCase)
        var calls = 0
        let (result, attempts) = r.retrying(aCase, retries: 1, isPass: { $0 }) { () -> Bool in
            calls += 1
            return calls == 2
        }
        r.runEnded(rows: [])
        XCTAssertTrue(result)
        XCTAssertEqual(attempts, 2)
    }

    /// A sink that throws on every line: the case's result and attempt count
    /// are the same as with no progress at all, and nothing throws out.
    func testAThrowingSinkDoesNotChangeTheCaseResult() {
        let sink = ThrowingSink()
        let r = reporter(sink)
        func run(_ retrying: (() -> Bool) -> (result: Bool, attempts: Int)) -> (Bool, Int) {
            var calls = 0
            let (result, attempts) = retrying { calls += 1; return calls == 2 }
            return (result, attempts)
        }
        let withThrowingSink = run { r.retrying(aCase, retries: 3, isPass: { $0 }, attempt: $0) }
        let plain = run { CaseRetry.run(retries: 3, isPass: { $0 }, attempt: $0) }
        XCTAssertEqual(withThrowingSink.0, plain.0)
        XCTAssertEqual(withThrowingSink.1, plain.1)
        XCTAssertEqual(sink.calls, 4, "the sink was called (and threw) for both pairs")

        let failing = r.retrying(aCase, retries: 1, isPass: { $0 }) { false }
        XCTAssertFalse(failing.result)
        XCTAssertEqual(failing.attempts, 2)
    }

    // MARK: caseIsolation reopen

    private func reopenCases(_ names: [String], skip: Set<String> = []) -> [TestCase] {
        names.map { name in
            var object: [String: Any] = ["name": name, "steps": []]
            if skip.contains(name) { object["skip"] = true }
            return try! JSONDecoder().decode(TestCase.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    private struct Row { let name: String; let passed: Bool; var skipped = false }

    private func reopenHooks(failing: Set<String>, teardownThrows: Bool = false) -> ReopenedCases.Hooks<Row> {
        ReopenedCases.Hooks(
            gate: { $0.skip == true ? Row(name: $0.name, passed: true, skipped: true) : nil },
            reopen: { _ in },
            setup: {},
            body: { Row(name: $0.name, passed: !failing.contains($0.name)) },
            teardown: { if teardownThrows { throw SinkFailure() } },
            setupFailed: { tc, _ in Row(name: tc.name, passed: false) },
            teardownFailed: { _, _ in Row(name: "teardown", passed: false) },
            isPass: { $0.passed },
            stampAttempts: { row, _ in row }
        )
    }

    func testReopenEmitsASkipAPairPerAttemptAndTheTeardownRow() {
        let sink = RecordingSink()
        let r = reporter(sink)
        let rows = ReopenedCases.run(
            cases: reopenCases(["skipped one", "flaky", "good"], skip: ["skipped one"]),
            retries: 1,
            progress: (r, "screens/x/x.test.json", "x", { $0.name }),
            hooks: reopenHooks(failing: ["flaky"], teardownThrows: false)
        )
        XCTAssertEqual(rows.map(\.name), ["skipped one", "flaky", "good"])
        XCTAssertEqual(sink.records.map { "\($0["event"]!)/\($0["case"]!)/\($0["attempt"]!)" }, [
            "case_end/skipped one/0",
            "case_start/flaky/1", "case_end/flaky/1",
            "case_start/flaky/2", "case_end/flaky/2",
            "case_start/good/1", "case_end/good/1",
        ])
        XCTAssertTrue(sink.records.allSatisfy { $0["file"] as? String == "screens/x/x.test.json" && $0["test"] as? String == "x" })

        let torn = RecordingSink()
        _ = ReopenedCases.run(
            cases: reopenCases(["good"]), retries: 0,
            progress: (reporter(torn), "f.test.json", "x", { $0.name }),
            hooks: reopenHooks(failing: [], teardownThrows: true)
        )
        XCTAssertEqual(torn.records.map { "\($0["event"]!)/\($0["case"]!)/\($0["status"] ?? "-")" }, [
            "case_start/good/-", "case_end/good/passed",
            "case_start/teardown/-", "case_end/teardown/failed",
        ])
    }

    func testReopenRowsAreTheSameWithAThrowingSinkAsWithNone() {
        let cases = reopenCases(["a", "b", "c"], skip: ["b"])
        let none = ReopenedCases.run(cases: cases, retries: 2,
                                     hooks: reopenHooks(failing: ["c"], teardownThrows: true))
        let throwing = ReopenedCases.run(cases: cases, retries: 2,
                                         progress: (reporter(ThrowingSink()), "f", "t", { $0.name }),
                                         hooks: reopenHooks(failing: ["c"], teardownThrows: true))
        XCTAssertEqual(none.map { "\($0.name)/\($0.passed)/\($0.skipped)" },
                       throwing.map { "\($0.name)/\($0.passed)/\($0.skipped)" })
    }

    /// Every row results.json gets has case lines, so the final case_end of
    /// each row, counted by status, is run_end: a launch that failed (the
    /// body never ran), a teardown failure's own row, a skipped row, a retried
    /// failure and a pass.
    func testFinalCaseEndsCountedByStatusAreRunEnd() {
        let sink = RecordingSink()
        let r = reporter(sink)
        struct LaunchFailed: Error {}
        let cases = reopenCases(["launch fails", "skipped", "flaky fails", "passes, teardown fails"], skip: ["skipped"])
        r.runStarted(files: 1, environment: [:])
        var current = ""
        let rows = ReopenedCases.run(
            cases: cases, retries: 1,
            progress: (r, "screens/x/x.test.json", "x", { $0.name }),
            hooks: ReopenedCases.Hooks<TestCaseResult>(
                gate: { $0.skip == true ? TestCaseResult(name: $0.name, passed: true, duration: 0, skipped: true) : nil },
                reopen: { current = $0.name; if $0.name == "launch fails" { throw LaunchFailed() } },
                setup: {},
                body: { TestCaseResult(name: $0.name, passed: $0.name != "flaky fails", duration: 0.01) },
                teardown: { if current == "passes, teardown fails" { throw LaunchFailed() } },
                setupFailed: { tc, error in TestCaseResult(name: tc.name, passed: false, duration: 0, error: error) },
                teardownFailed: { _, error in TestCaseResult(name: "teardown", passed: false, duration: 0, error: error) },
                isPass: { $0.passed },
                stampAttempts: { $0.stamping(attempts: $1) }
            )
        )
        // The shared path records these two without the retry loop: a
        // launch / setup failure for a case, and the file's teardown row.
        r.caseFailedWithoutRunning(.init(file: "screens/x/x.test.json", test: "x", name: "setup never confirmed"))
        r.caseFailedWithoutRunning(.init(file: "screens/x/x.test.json", test: "x", name: "teardown"))
        let allRows = rows + [
            TestCaseResult(name: "setup never confirmed", passed: false, duration: 0),
            TestCaseResult(name: "teardown", passed: false, duration: 0),
        ]
        r.runEnded(rows: allRows)

        // The final case_end of each row: a case_start with attempt > 1
        // supersedes the case_end before it for the same case.
        var finals: [[String: Any]] = []
        for record in sink.records {
            switch record["event"] as? String {
            case "case_start":
                if (record["attempt"] as? Int ?? 1) > 1,
                   let i = finals.lastIndex(where: { $0["case"] as? String == record["case"] as? String }) {
                    finals.remove(at: i)
                }
            case "case_end":
                finals.append(record)
            default:
                break
            }
        }
        let byStatus = Dictionary(grouping: finals, by: { $0["status"] as! String }).mapValues(\.count)
        let end = sink.records.last!
        XCTAssertEqual(end["event"] as? String, "run_end")
        XCTAssertEqual(finals.count, allRows.count, "one final case_end per results row")
        XCTAssertEqual(byStatus["passed"] ?? 0, end["passed"] as? Int)
        XCTAssertEqual(byStatus["failed"] ?? 0, end["failed"] as? Int)
        XCTAssertEqual(byStatus["skipped"] ?? 0, end["skipped"] as? Int)
        XCTAssertEqual([end["passed"] as? Int, end["failed"] as? Int, end["skipped"] as? Int], [1, 5, 1])
    }

    // MARK: a failure does not stop the file

    /// The cases after a failure run, so each has its own case_start /
    /// case_end pair — none is a skipped attempt-0 line — and the lines still
    /// close to run_end: one final case_end per results row.
    private func assertEveryCaseLines(_ sink: RecordingSink, rows: [Row], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rows.map { "\($0.name)/\($0.passed)/\($0.skipped)" },
                       ["pass/true/false", "fail/false/false", "after a/true/false", "after b/true/false"], file: file, line: line)
        XCTAssertEqual(sink.records.map { "\($0["event"]!)/\($0["case"]!)/\($0["attempt"]!)/\($0["status"] ?? "-")" }, [
            "case_start/pass/1/-", "case_end/pass/1/passed",
            "case_start/fail/1/-", "case_end/fail/1/failed",
            "case_start/after a/1/-", "case_end/after a/1/passed",
            "case_start/after b/1/-", "case_end/after b/1/passed",
        ], file: file, line: line)
        XCTAssertEqual(sink.records.filter { $0["event"] as? String == "case_end" }.count, rows.count,
                       "one case_end per results row", file: file, line: line)
    }

    private let afterFailureNames = ["pass", "fail", "after a", "after b"]

    func testReopenEmitsAPairForEveryCaseAfterAFailure() {
        let sink = RecordingSink()
        let hooks = reopenHooks(failing: ["fail"])
        let rows = ReopenedCases.run(
            cases: reopenCases(afterFailureNames), retries: 0,
            progress: (reporter(sink), "f.test.json", "x", { $0.name }), hooks: hooks
        )
        assertEveryCaseLines(sink, rows: rows)
    }

    func testSharedEmitsAPairForEveryCaseAfterAFailure() {
        let sink = RecordingSink()
        let r = reporter(sink)
        let progressFor: (String) -> ProgressRecord.Case = { .init(file: "f.test.json", test: "x", name: $0) }
        let rows = SharedCases.run(
            cases: reopenCases(afterFailureNames),
            progress: (r, "f.test.json", "x", { $0.name }),
            hooks: SharedCases.Hooks(
                gate: { $0.skip == true ? Row(name: $0.name, passed: true, skipped: true) : nil },
                unrunnable: { _ in nil },
                // The runner's body emits its own pair (runTestCaseWithRetries).
                body: { tc in r.retrying(progressFor(tc.name), retries: 0, isPass: { $0.passed }) {
                    Row(name: tc.name, passed: tc.name != "fail") }.result }
            )
        )
        assertEveryCaseLines(sink, rows: rows)
    }

    /// A case the shared loop cannot run (setup failed) is one failed
    /// case_end of its own.
    func testSharedUnrunnableCaseIsOneFailedCaseEnd() {
        let sink = RecordingSink()
        let rows = SharedCases.run(
            cases: reopenCases(["cannot", "runs"]),
            progress: (reporter(sink), "f.test.json", "x", { $0.name }),
            hooks: SharedCases.Hooks(
                gate: { _ in nil },
                unrunnable: { $0.name == "cannot" ? Row(name: $0.name, passed: false) : nil },
                body: { Row(name: $0.name, passed: true) }
            )
        )
        XCTAssertEqual(rows.map(\.name), ["cannot", "runs"])
        XCTAssertEqual(sink.records.map { "\($0["event"]!)/\($0["case"]!)/\($0["status"] ?? "-")" }, [
            "case_start/cannot/-", "case_end/cannot/failed",
        ])
    }

    // MARK: sourceFile (the `file` of a line)

    func testSourceFileIsRelativeToTheRootItWasLoadedFrom() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("screens/login")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = dir.appendingPathComponent("login.test.json")
        try Data(#"{"type":"screen","source":{"layout":"login"},"metadata":{"name":"login"},"cases":[]}"#.utf8).write(to: file)

        let loader = TestLoader()
        let all = try loader.loadAll(from: root)
        guard case .screen(let fromDirectory)? = all.first else { return XCTFail("not loaded") }
        XCTAssertEqual(fromDirectory.sourceFile, "screens/login/login.test.json")

        guard case .screen(let single) = try loader.load(from: file) else { return XCTFail("not a screen") }
        XCTAssertEqual(single.sourceFile, "login.test.json")

        let decoded = try JSONDecoder().decode(ScreenTest.self, from: Data(contentsOf: file))
        XCTAssertNil(decoded.sourceFile, "decoding alone sets nothing")
    }

    /// `sourceFile` is not a key of the file: a test that writes one does not set it.
    func testSourceFileIsNotDecodedFromTheFile() throws {
        let json = #"{"type":"screen","source":{"layout":"l"},"metadata":{"name":"n"},"cases":[],"sourceFile":"x"}"#
        XCTAssertNil(try JSONDecoder().decode(ScreenTest.self, from: Data(json.utf8)).sourceFile)
        let flow = #"{"type":"flow","metadata":{"name":"n"},"steps":[],"sourceFile":"x"}"#
        XCTAssertNil(try JSONDecoder().decode(FlowTest.self, from: Data(flow.utf8)).sourceFile)
    }
}
