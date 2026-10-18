import XCTest

/// The results rows a flow file produces.
///
/// A flow is one case named `"flow"`: `testName` is the flow's own name
/// (`metadata.name`), `caseName` is the literal `"flow"`, on every path —
/// a platform skip, a flow that could not start, and the body's result. The
/// Android and Web drivers have always written `"flow"`; this driver wrote
/// the flow's name a second time, so the same flow had two identities in
/// merged reports. The same name is used for the flow's artifact identity
/// (`currentCaseName`), matching Android's `<test>/flow/` folders.
///
/// Built here rather than inline in the runner so a plain XCTest can pin the
/// name without the XCUITest runtime.
enum FlowRows {

    /// The case name of every row a flow file produces.
    static let caseName = "flow"

    /// The flow is excluded by its platform gate.
    static func platformSkipped() -> TestCaseResult {
        TestCaseResult(name: caseName, passed: true, duration: 0, skipped: true, skipReason: .platform)
    }

    /// The flow failed before its body ran (e.g. its mock scenarios could not be set).
    static func notStarted(error: Error) -> TestCaseResult {
        TestCaseResult(name: caseName, passed: false, duration: 0, error: error)
    }

    /// The flow body's final result (setup + steps, after retries).
    static func body(
        error: Error?,
        duration: TimeInterval,
        screenshots: [XCTAttachment],
        warnings: [String],
        attempts: Int
    ) -> TestCaseResult {
        TestCaseResult(
            name: caseName,
            passed: error == nil,
            duration: duration,
            error: error,
            screenshots: screenshots,
            warnings: warnings,
            attempts: attempts
        )
    }
}
