import Foundation

/// Serializes run results to the standardized results JSON (schemas/results.schema.json).
public enum ResultsWriter {

    /// Write test run results to a file in the jsonui-test-results format.
    public static func write(_ runs: [TestRunResult], to url: URL, platform: String) throws {
        let payload = resultsJSON(runs, platform: platform)
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// Build the results.schema.json payload from run results.
    public static func resultsJSON(_ runs: [TestRunResult], platform: String) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let suites: [[String: Any]] = runs.map { run in
            let results: [[String: Any]] = run.caseResults.map { caseResult in
                var entry: [String: Any] = [
                    "testName": run.testName,
                    "caseName": caseResult.name,
                    "status": status(for: caseResult),
                    "durationMs": Int(caseResult.duration * 1000)
                ]
                if let error = caseResult.error {
                    entry["error"] = error.localizedDescription
                }
                if !caseResult.warnings.isEmpty {
                    entry["warnings"] = caseResult.warnings
                }
                return entry
            }
            return [
                "suiteName": run.testName,
                "totalDurationMs": Int(run.totalDuration * 1000),
                "results": results
            ]
        }

        return [
            "format": "jsonui-test-results",
            "version": 1,
            "platform": platform,
            "generatedAt": iso.string(from: Date()),
            "suites": suites
        ]
    }

    private static func status(for result: TestCaseResult) -> String {
        if result.skipped { return "skipped" }
        return result.passed ? "passed" : "failed"
    }
}
