import XCTest
@testable import JsonUITestRunner

/// The `within` errors an action throws: their text and their
/// `failureReason` stage, and that a flow step's `within` reaches the step
/// the executors run.
final class WithinErrorTests: XCTestCase {

    func testAMissingContainerReadsAsTheContainerAndIsElementNotFound() {
        let error = ActionError.containerNotFound(within: "list_item_4", id: "delete")
        XCTAssertEqual(error.errorDescription,
                       "Element not found: " + WithinScope.containerNotFound(within: "list_item_4", id: "delete"))
        XCTAssertEqual(FailureClassifier.classify(error), .elementNotFound)
    }

    func testAMissingTargetNamesBothAndIsElementNotFound() {
        let error = ActionError.notFoundWithin(id: "delete", within: "list_item_4")
        XCTAssertEqual(error.errorDescription,
                       "Element not found: " + WithinScope.targetNotFound(id: "delete", within: "list_item_4"))
        XCTAssertEqual(FailureClassifier.classify(error), .elementNotFound)
    }

    func testAScopedWaitThatRanOutIsATimeoutNamingWhatWasMissing() {
        let noContainer = ActionError.timeoutWithin(ids: ["a", "b"], within: "c_item_0", containerFound: false, timeout: 3000)
        XCTAssertEqual(noContainer.errorDescription,
                       "Timeout after 3000ms: " + WithinScope.containerNotFound(within: "c_item_0", id: "a, b"))
        let noTarget = ActionError.timeoutWithin(ids: ["a"], within: "c_item_0", containerFound: true, timeout: 3000)
        XCTAssertEqual(noTarget.errorDescription,
                       "Timeout after 3000ms: " + WithinScope.targetNotFound(id: "a", within: "c_item_0"))
        XCTAssertEqual(FailureClassifier.classify(noContainer), .timeout)
        XCTAssertEqual(FailureClassifier.classify(noTarget), .timeout)
    }

    func testAFlowStepsWithinReachesTheExecutedStep() throws {
        let flowStep = try JSONDecoder().decode(
            FlowTestStep.self,
            from: Data(#"{"screen":"s","assert":"count","id":"tag","within":"rows_item_1","equals":2}"#.utf8))
        XCTAssertEqual(flowStep.toTestStep().within, "rows_item_1")
    }
}
