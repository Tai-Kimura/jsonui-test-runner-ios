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
        /// Bring the screen up afresh (re-apply mocks, relaunch, re-apply orientation).
        let reopen: () throws -> Void
        let setup: () throws -> Void
        let body: (TestCase) -> R
        let teardown: () throws -> Void
        /// The row for a case whose reopen or setup threw; the body never ran.
        let setupFailed: (TestCase, Error) -> R
        /// The extra row recorded when a case's teardown threw.
        let teardownFailed: (TestCase, Error) -> R
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
    ///   shared path.
    static func run<R>(
        cases: [TestCase],
        retries: Int,
        continueOnFailure: Bool,
        hooks: Hooks<R>
    ) -> [R] {
        var rows: [R] = []
        for testCase in cases {
            if let gated = hooks.gate(testCase) {
                rows.append(gated)
                continue
            }
            var teardownError: Error?
            let (result, attempts) = CaseRetry.run(retries: retries, isPass: hooks.isPass) { () -> R in
                let result: R
                do {
                    try hooks.reopen()
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
                rows.append(hooks.teardownFailed(testCase, teardownError))
            }
            if !hooks.isPass(result) && !continueOnFailure {
                break
            }
        }
        return rows
    }
}
