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
                // The machine-readable half of the same fact. Derived from the
                // error rather than set at each throw site, and only on a
                // failed row: the validator rejects it elsewhere, and a
                // skipped case that carried one would be claiming a failure it
                // did not have. Absent means unknown, never "no reason".
                if !caseResult.skipped, !caseResult.passed,
                   let reason = FailureClassifier.classify(caseResult.error) {
                    entry["failureReason"] = reason.rawValue
                }
                // Distinct skip reason (platform vs responsive gate) so a
                // gate-caused skip never hides as an unexplained green row;
                // plain `skip: true` skips carry no reason.
                if caseResult.skipped, let reason = caseResult.skipReason {
                    entry["skipReason"] = reason.rawValue
                }
                if !caseResult.warnings.isEmpty {
                    entry["warnings"] = caseResult.warnings
                }
                // attempts = total runs (1 = settled first try); flaky only
                // on a pass that needed retries — the validator rejects
                // flaky on failures (results.schema.json).
                if !caseResult.skipped, let attempts = caseResult.attempts {
                    entry["attempts"] = attempts
                    if caseResult.passed && attempts > 1 {
                        entry["flaky"] = true
                    }
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
