import XCTest
@testable import JsonUITestRunner

/// `failureReason` (results.schema.json) — the machine-readable half of a
/// failed row, beside the prose in `error`.
///
/// Prose moves between releases: a consumer aggregation matched on a sentence
/// that existed in 1.9.4–1.9.7 and was deleted in 1.9.8, and would have
/// reported zero occurrences of something that had only been reworded.
final class FailureReasonTests: XCTestCase {

    func testEveryActionErrorCaseMapsToAStage() {
        // The mapping is exhaustive by construction (switch), but the STAGES
        // are the claim: a missing parameter is a broken test, a failed action
        // is a working test that did not achieve its effect.
        XCTAssertEqual(FailureClassifier.classify(ActionError.elementNotFound(id: "x")), .elementNotFound)
        XCTAssertEqual(FailureClassifier.classify(ActionError.timeout(id: "x", timeout: 1)), .timeout)
        XCTAssertEqual(FailureClassifier.classify(ActionError.timeoutAny(ids: ["x"], timeout: 1)), .timeout)
        XCTAssertEqual(FailureClassifier.classify(ActionError.missingParameter(action: "tap", parameter: "id")), .invalidTest)
        XCTAssertEqual(FailureClassifier.classify(ActionError.unknownAction(action: "wiggle")), .invalidTest)
        XCTAssertEqual(FailureClassifier.classify(ActionError.actionFailed(action: "tap", reason: "nope")), .action)
    }

    func testTheOtherErrorTypesEachHaveAStage() {
        XCTAssertEqual(FailureClassifier.classify(MockClientError.httpStatus(500)), .mock)
        XCTAssertEqual(FailureClassifier.classify(TestLoaderError.notAScreenTest(file: "f.json")), .invalidTest)
        XCTAssertEqual(FailureClassifier.classify(TestRunnerError.setupFailed(reason: "no screen")), .setup)
    }

    func testAnUnrecognisedErrorIsOtherRatherThanNil() {
        // nil means "no error to classify". An unknown error IS a failure with
        // a reason we cannot name, and the two must not collapse — one is
        // "unknown", the other is "unclassified".
        struct Surprise: Error {}
        XCTAssertEqual(FailureClassifier.classify(Surprise()), .other)
    }

    func testNoErrorIsNilNotOther() {
        XCTAssertNil(FailureClassifier.classify(nil))
    }

    func testTheRawValuesAreTheSchemaSpelling() {
        // These strings are a cross-repo contract: results.schema.json's enum
        // and report.VALID_FAILURE_REASONS carry the same eight.
        XCTAssertEqual(FailureReason.elementNotFound.rawValue, "element-not-found")
        XCTAssertEqual(FailureReason.invalidTest.rawValue, "invalid-test")
        XCTAssertEqual(
            Set([FailureReason.elementNotFound, .timeout, .assertion, .invalidTest,
                 .mock, .setup, .teardown, .launch, .action, .other].map { $0.rawValue }),
            ["element-not-found", "timeout", "assertion", "invalid-test",
             "mock", "setup", "teardown", "launch", "action", "other"]
        )
    }
}
