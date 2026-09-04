import Foundation

/// The machine-readable half of a failed result (`results.schema.json`
/// `failureReason`), beside the prose in `error`.
///
/// Prose moves between releases. A consumer aggregation matched on
/// "scrolled both ways and it is still off the viewport" — a sentence that
/// lived in 1.9.4 through 1.9.7 and was deleted in 1.9.8 — and would have
/// reported zero of a thing that had only been reworded. The same release
/// turned one failure's output from one line into five. `skipReason` has been
/// an enum since it existed; failures had no such channel.
///
/// The vocabulary is the failure's STAGE, not the exception type, because the
/// three drivers share no taxonomy: this one has five typed enums, android
/// throws `IllegalArgumentException` at 75 sites, web throws a bare `Error` at
/// 80. Mapping types would have produced three different enums, which is the
/// spelling problem rebuilt in a new spelling.
public enum FailureReason: String {
    /// The target could not be resolved at all.
    case elementNotFound = "element-not-found"
    /// A wait expired.
    case timeout
    /// An expectation was evaluated and did not hold.
    case assertion
    /// The test file or step is malformed: unknown action, missing parameter,
    /// bad JSON, no such case. The suite is wrong, not the app.
    case invalidTest = "invalid-test"
    /// Talking to the mock server failed.
    case mock
    /// The case's own setup steps failed, so the body never ran.
    case setup
    /// The case's own teardown steps failed. Says nothing about the
    /// behaviour under test.
    case teardown
    /// The app or screen could not be brought up, so nothing was measured.
    case launch
    /// An action ran and did not achieve its effect.
    case action
    /// Unclassified. Carries no information on its own, so a result using it
    /// must still carry prose in `error` — and a rising count of it is how
    /// this list says it is too short.
    case other
}

public enum FailureClassifier {

    /// Derive the reason from the error a case actually failed with.
    ///
    /// Derived rather than threaded: the error is already on the result, and
    /// a second field set by hand at each throw site would be one more thing
    /// to keep in step with the first.
    ///
    /// Returns nil when there is no error to classify — absent must read as
    /// "unknown", never as "no reason".
    public static func classify(_ error: Error?) -> FailureReason? {
        guard let error else { return nil }

        if let actionError = error as? ActionError {
            switch actionError {
            case .elementNotFound:
                return .elementNotFound
            case .timeout, .timeoutAny:
                return .timeout
            case .missingParameter, .unknownAction:
                // The step could not be executed as written.
                return .invalidTest
            case .actionFailed:
                // It ran; it did not achieve the effect.
                return .action
            }
        }
        if error is AssertionError { return .assertion }
        if error is MockClientError { return .mock }
        if error is TestLoaderError { return .invalidTest }
        if let runnerError = error as? TestRunnerError {
            switch runnerError {
            case .setupFailed:
                // The case's setup steps, not the app launch — measured: this
                // is raised where `setup` actions throw, and all three drivers
                // record that on a path of its own.
                return .setup
            case .repeatExceededCap, .retryExhausted:
                return .other
            }
        }
        return .other
    }
}
