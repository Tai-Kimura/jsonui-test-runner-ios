import XCTest
@testable import JsonUITestRunner

/// A flow's results rows carry caseName "flow" (testName stays the flow's
/// own name), as the Android and Web drivers have always written. The runner
/// needs the XCUITest runtime, so the rows are pinned on `FlowRows`, which
/// builds every flow row the runner emits.
final class FlowCaseNameTests: XCTestCase {

    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    private func rows(_ caseResults: [TestCaseResult]) -> [[String: Any]] {
        let run = TestRunResult(testName: "checkout_flow", caseResults: caseResults, totalDuration: 0)
        let payload = ResultsWriter.resultsJSON([run], platform: "ios")
        let suites = payload["suites"] as? [[String: Any]]
        return suites?.first?["results"] as? [[String: Any]] ?? []
    }

    func testEveryFlowRowIsNamedFlow() {
        let written = rows([
            FlowRows.platformSkipped(),
            FlowRows.notStarted(error: Boom()),
            FlowRows.body(error: nil, duration: 0.1, screenshots: [], warnings: [], attempts: 1),
            FlowRows.body(error: Boom(), duration: 0.1, screenshots: [], warnings: [], attempts: 2),
        ])
        XCTAssertEqual(written.count, 4)
        XCTAssertEqual(written.map { $0["caseName"] as? String }, ["flow", "flow", "flow", "flow"])
        XCTAssertEqual(Set(written.map { $0["testName"] as? String }), ["checkout_flow"])
        XCTAssertEqual(written.map { $0["status"] as? String }, ["skipped", "failed", "passed", "failed"])
        XCTAssertEqual(written[0]["skipReason"] as? String, "platform")
        XCTAssertEqual(written[3]["attempts"] as? Int, 2)
    }

    /// The runner's flow paths must go through `FlowRows`, not build a row
    /// named after the flow. A raw read of the runner source: the row
    /// builders above are only worth pinning if the runner uses them.
    func testTheRunnerDoesNotNameAFlowRowOrArtifactAfterTheFlow() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JsonUITestRunner/Runner/TestRunner.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.contains("name: flowTest.metadata.name"), "a flow row named after the flow")
        XCTAssertFalse(text.contains("currentCaseName = flowTest.metadata.name"), "flow artifacts named after the flow")
        XCTAssertTrue(text.contains("currentCaseName = FlowRows.caseName"))
        XCTAssertEqual(text.components(separatedBy: "FlowRows.").count - 1, 4,
                       "platformSkipped, notStarted, body, caseName")
    }
}
