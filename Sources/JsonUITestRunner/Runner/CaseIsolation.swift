import Foundation

/// Whether a screen test file's cases share one app state or each start from
/// a freshly launched app (`screen-test.schema.json` `caseIsolation`).
///
/// - `shared` (the default, and what an absent key means): setup runs once,
///   every case runs in the state the previous case left — its scroll
///   position, the screen it navigated to — and teardown runs once. The order
///   of the cases matters.
/// - `reopen`: before each case the app is relaunched with the file's launch
///   configuration and mock scenarios, then setup runs; teardown runs after
///   each case.
///
/// An unknown value fails decoding rather than running as `shared`: a
/// misspelling would otherwise give the file exactly the shared state it
/// declared it did not want.
public enum CaseIsolation: String, Codable {
    case shared
    case reopen
}

/// The per-case sequence for `caseIsolation: reopen`.
///
/// Pure on purpose, like `CaseRetry`: the runner needs the XCUITest runtime,
/// the ordering of reopen → setup → case → teardown and its failure semantics
/// do not, so they live here where a plain XCTest can pin them.
enum ReopenedCases {

    struct Hooks<R> {
        /// The skipped row for a case gated out (skip / platform / responsive), or nil.
        let gate: (TestCase) -> R?
        /// Bring the screen up afresh for this case (re-apply mocks, relaunch
        /// with the case's initialState, re-apply orientation).
        let reopen: (TestCase) throws -> Void
        let setup: () throws -> Void
        let body: (TestCase) -> R
        let teardown: () throws -> Void
        /// The row for a case whose reopen or setup threw; the body never ran.
        let setupFailed: (TestCase, Error) -> R
        /// The extra row recorded when a case's teardown threw.
        let teardownFailed: (TestCase, Error) -> R
        /// The row for a case not run because an earlier case failed and
        /// `continueOnFailure` is false (see `CaseStop`).
        let stoppedAfterFailure: (TestCase) -> R
        let isPass: (R) -> Bool
        let stampAttempts: (R, Int) -> R
    }

    /// Runs every case through reopen → setup → body → teardown.
    ///
    /// - A gated case is recorded without reopening anything.
    /// - A reopen or setup failure fails that case alone; its teardown still
    ///   runs, and the next case reopens independently.
    /// - Each retry attempt is a full reopen → setup → body → teardown, so a
    ///   retry starts clean. Only the final attempt's teardown failure is
    ///   recorded (earlier attempts were superseded, the same rule as their
    ///   results).
    /// - A failed case stops the file unless `continueOnFailure`, as in the
    ///   shared path. Every case after the stop still gets a row (`CaseStop`):
    ///   its gate row if it is gated, else a skipped row. Nothing is reopened
    ///   for them.
    /// - Progress (when given): a gated case, and a case after the stop, is one
    ///   skipped case_end; every attempt — reopen and setup included, they are
    ///   part of it — is a case_start / case_end pair; a teardown row is a
    ///   failed pair of its own.
    static func run<R>(
        cases: [TestCase],
        retries: Int,
        continueOnFailure: Bool,
        progress: (reporter: TestProgressReporter, file: String, test: String, rowName: (R) -> String)? = nil,
        hooks: Hooks<R>
    ) -> [R] {
        var rows: [R] = []
        var stopped = false
        // The reporter and the case a line is about, when progress is wanted.
        func progressCase(_ name: String) -> (TestProgressReporter, ProgressRecord.Case)? {
            progress.map { ($0.reporter, ProgressRecord.Case(file: $0.file, test: $0.test, name: name)) }
        }
        for testCase in cases {
            if let gated = hooks.gate(testCase) {
                rows.append(gated)
                if case let (reporter, id)? = progressCase(testCase.name) { reporter.caseSkipped(id) }
                continue
            }
            if stopped {
                rows.append(hooks.stoppedAfterFailure(testCase))
                if case let (reporter, id)? = progressCase(testCase.name) { reporter.caseSkipped(id) }
                continue
            }
            var teardownError: Error?
            let retry: (() -> R) -> (result: R, attempts: Int) = { attempt in
                if case let (reporter, id)? = progressCase(testCase.name) {
                    return reporter.retrying(id, retries: retries, isPass: hooks.isPass, attempt: attempt)
                }
                return CaseRetry.run(retries: retries, isPass: hooks.isPass, attempt: attempt)
            }
            let (result, attempts) = retry { () -> R in
                let result: R
                do {
                    try hooks.reopen(testCase)
                    try hooks.setup()
                    result = hooks.body(testCase)
                } catch {
                    result = hooks.setupFailed(testCase, error)
                }
                teardownError = nil
                do {
                    try hooks.teardown()
                } catch {
                    teardownError = error
                }
                return result
            }
            rows.append(hooks.stampAttempts(result, attempts))
            if let teardownError {
                let row = hooks.teardownFailed(testCase, teardownError)
                rows.append(row)
                if let progress, case let (reporter, id)? = progressCase(progress.rowName(row)) {
                    reporter.caseFailedWithoutRunning(id)
                }
            }
            if !hooks.isPass(result) && !continueOnFailure {
                stopped = true
            }
        }
        return rows
    }
}

/// The per-case loop for `caseIsolation: shared` (the default): setup and
/// teardown run once around it, in the runner.
///
/// Pure for the same reason as `ReopenedCases`. A case whose setup failed (or
/// that cannot run under shared) is recorded failed and does NOT stop the
/// file — that is the behaviour this loop was extracted with. A case that ran
/// and failed stops it unless `continueOnFailure`.
enum SharedCases {

    struct Hooks<R> {
        /// The skipped row for a case gated out (skip / platform / responsive), or nil.
        let gate: (TestCase) -> R?
        /// The failed row for a case that cannot run (setup failed, or a case
        /// initialState under shared), or nil when it can.
        let unrunnable: (TestCase) -> R?
        /// Run the case (retries included) and return its final row.
        let body: (TestCase) -> R
        /// The row for a case not run because of an earlier failure (see `CaseStop`).
        let stoppedAfterFailure: (TestCase) -> R
        let isPass: (R) -> Bool
    }

    /// Progress (when given): a gated case, and a case after the stop, is one
    /// skipped case_end; a case that cannot run is one failed case_end. The
    /// body emits its own attempts (the runner's retry loop does).
    static func run<R>(
        cases: [TestCase],
        continueOnFailure: Bool,
        progress: (reporter: TestProgressReporter, file: String, test: String, rowName: (R) -> String)? = nil,
        hooks: Hooks<R>
    ) -> [R] {
        var rows: [R] = []
        var stopped = false
        func progressCase(_ name: String) -> (TestProgressReporter, ProgressRecord.Case)? {
            progress.map { ($0.reporter, ProgressRecord.Case(file: $0.file, test: $0.test, name: name)) }
        }
        for testCase in cases {
            if let gated = hooks.gate(testCase) {
                rows.append(gated)
                if case let (reporter, id)? = progressCase(testCase.name) { reporter.caseSkipped(id) }
                continue
            }
            if stopped {
                rows.append(hooks.stoppedAfterFailure(testCase))
                if case let (reporter, id)? = progressCase(testCase.name) { reporter.caseSkipped(id) }
                continue
            }
            if let failed = hooks.unrunnable(testCase) {
                rows.append(failed)
                if let progress, case let (reporter, id)? = progressCase(progress.rowName(failed)) {
                    reporter.caseFailedWithoutRunning(id)
                }
                continue
            }
            let result = hooks.body(testCase)
            rows.append(result)
            if !hooks.isPass(result) && !continueOnFailure {
                stopped = true
            }
        }
        return rows
    }
}

/// The row for a case the run stopped before.
///
/// `continueOnFailure` false (the default) stops a file at its first failed
/// case. The cases after it used to appear nowhere in results.json, so a
/// stopped file looked shorter than it was and its row count stopped matching
/// its case count. Each now gets a skipped row with NO skipReason: the schema's
/// skipReason names a gate (platform / responsive), and this is not one. A
/// case gated out (skip / platform / responsive) keeps its gate row.
enum CaseStop {
    static func skippedRow(_ testCase: TestCase) -> TestCaseResult {
        TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true)
    }
}
