import XCTest

/// Protocol for executing test assertions
public protocol AssertionExecutor {
    func execute(step: TestStep, in app: XCUIApplication) throws
    func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws
}

/// Errors that can occur during assertion execution
public enum AssertionError: Error, LocalizedError {
    case elementNotFound(id: String)
    case unknownAssertion(assertion: String)
    case missingParameter(assertion: String, parameter: String)
    case assertionFailed(assertion: String, expected: String, actual: String)
    case stateNotAccessible(path: String)

    public var errorDescription: String? {
        switch self {
        case .elementNotFound(let id):
            return "Element not found: '\(id)'"
        case .unknownAssertion(let assertion):
            return "Unknown assertion: '\(assertion)'"
        case .missingParameter(let assertion, let parameter):
            return "Missing parameter '\(parameter)' for assertion '\(assertion)'"
        case .assertionFailed(let assertion, let expected, let actual):
            return "Assertion '\(assertion)' failed - Expected: \(expected), Actual: \(actual)"
        case .stateNotAccessible(let path):
            return "Cannot access ViewModel state at path: '\(path)'"
        }
    }
}

/// Protocol for accessing ViewModel state from XCUITest
public protocol ViewModelStateProvider {
    func getValue(at path: String) -> Any?
}

/// Default implementation of AssertionExecutor using XCUITest
public class XCUITestAssertionExecutor: AssertionExecutor {

    private let defaultTimeout: TimeInterval = 5.0
    private var stateProvider: ViewModelStateProvider?

    public init(stateProvider: ViewModelStateProvider? = nil) {
        self.stateProvider = stateProvider
    }

    public func setStateProvider(_ provider: ViewModelStateProvider) {
        self.stateProvider = provider
    }

    public func execute(step: TestStep, in app: XCUIApplication) throws {
        guard let assertion = step.assert else {
            throw AssertionError.unknownAssertion(assertion: "nil")
        }

        switch assertion {
        case "visible":
            try assertVisible(step: step, in: app)
        case "notVisible":
            try assertNotVisible(step: step, in: app)
        case "enabled":
            try assertEnabled(step: step, in: app)
        case "disabled":
            try assertDisabled(step: step, in: app)
        case "text":
            try assertText(step: step, in: app)
        case "count":
            try assertCount(step: step, in: app)
        case "state":
            try assertState(step: step)
        default:
            throw AssertionError.unknownAssertion(assertion: assertion)
        }
    }

    public func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws {
        guard flowStep.assert != nil else {
            throw AssertionError.unknownAssertion(assertion: "nil")
        }

        // Convert FlowTestStep to TestStep for reuse
        let step = TestStep(
            action: flowStep.action,
            assert: flowStep.assert,
            id: flowStep.id,
            value: flowStep.value,
            direction: flowStep.direction,
            duration: flowStep.duration,
            timeout: flowStep.timeout,
            ms: flowStep.ms,
            name: flowStep.name,
            equals: flowStep.equals,
            contains: flowStep.contains,
            path: flowStep.path,
            amount: flowStep.amount
        )

        try execute(step: step, in: app)
    }

    // MARK: - Assertion Implementations

    private func assertVisible(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "visible", parameter: "id")
        }

        let element = app.descendants(matching: .any)[id]

        // Wait for element and check visibility
        let exists = element.waitForExistence(timeout: defaultTimeout)

        XCTAssertTrue(
            exists && element.isHittable,
            "Element '\(id)' should be visible"
        )
    }

    private func assertNotVisible(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "notVisible", parameter: "id")
        }

        let element = app.descendants(matching: .any)[id]

        // Give a short wait to ensure state is settled
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertFalse(
            element.exists && element.isHittable,
            "Element '\(id)' should not be visible"
        )
    }

    private func assertEnabled(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "enabled", parameter: "id")
        }

        let element = try findElement(id: id, in: app)

        XCTAssertTrue(
            element.isEnabled,
            "Element '\(id)' should be enabled"
        )
    }

    private func assertDisabled(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "disabled", parameter: "id")
        }

        let element = try findElement(id: id, in: app)

        XCTAssertFalse(
            element.isEnabled,
            "Element '\(id)' should be disabled"
        )
    }

    private func assertText(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "text", parameter: "id")
        }

        let element = try findElement(id: id, in: app)

        // Get text from element (label or value)
        let actualText = (element.value as? String) ?? element.label

        if let expectedEquals = step.equals?.stringValue {
            XCTAssertEqual(
                actualText,
                expectedEquals,
                "Element '\(id)' text should equal '\(expectedEquals)'"
            )
        } else if let expectedContains = step.contains {
            XCTAssertTrue(
                actualText.contains(expectedContains),
                "Element '\(id)' text '\(actualText)' should contain '\(expectedContains)'"
            )
        } else {
            throw AssertionError.missingParameter(assertion: "text", parameter: "equals or contains")
        }
    }

    private func assertCount(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "count", parameter: "id")
        }
        guard let expectedCount = step.equals?.intValue else {
            throw AssertionError.missingParameter(assertion: "count", parameter: "equals")
        }

        // Find all elements matching the identifier
        let elements = app.descendants(matching: .any).matching(identifier: id)
        let actualCount = elements.count

        XCTAssertEqual(
            actualCount,
            expectedCount,
            "Element '\(id)' count should be \(expectedCount), but was \(actualCount)"
        )
    }

    private func assertState(step: TestStep) throws {
        guard let path = step.path else {
            throw AssertionError.missingParameter(assertion: "state", parameter: "path")
        }
        guard let expectedValue = step.equals else {
            throw AssertionError.missingParameter(assertion: "state", parameter: "equals")
        }

        guard let provider = stateProvider else {
            throw AssertionError.stateNotAccessible(path: path)
        }

        guard let actualValue = provider.getValue(at: path) else {
            throw AssertionError.stateNotAccessible(path: path)
        }

        // Compare values based on type
        if let expectedBool = expectedValue.boolValue, let actualBool = actualValue as? Bool {
            XCTAssertEqual(actualBool, expectedBool, "State '\(path)' should be \(expectedBool)")
        } else if let expectedInt = expectedValue.intValue, let actualInt = actualValue as? Int {
            XCTAssertEqual(actualInt, expectedInt, "State '\(path)' should be \(expectedInt)")
        } else if let expectedString = expectedValue.stringValue, let actualString = actualValue as? String {
            XCTAssertEqual(actualString, expectedString, "State '\(path)' should be '\(expectedString)'")
        } else if let expectedDouble = expectedValue.doubleValue, let actualDouble = actualValue as? Double {
            XCTAssertEqual(actualDouble, expectedDouble, accuracy: 0.0001, "State '\(path)' should be \(expectedDouble)")
        } else {
            // Fallback to string comparison
            let actualString = String(describing: actualValue)
            let expectedString = String(describing: expectedValue.value)
            XCTAssertEqual(actualString, expectedString, "State '\(path)' mismatch")
        }
    }

    // MARK: - Helper Methods

    private func findElement(id: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = app.descendants(matching: .any)[id]

        if !element.waitForExistence(timeout: defaultTimeout) {
            throw AssertionError.elementNotFound(id: id)
        }

        return element
    }
}
