import XCTest

/// Configuration for test execution
public struct TestRunnerConfig {
    public var platform: String = "ios"
    public var screenshotOnFailure: Bool = true
    public var continueOnFailure: Bool = false
    public var defaultTimeout: TimeInterval = 5.0

    public init() {}
}

/// Result of a single test case execution
public struct TestCaseResult {
    public let name: String
    public let passed: Bool
    public let duration: TimeInterval
    public let error: Error?
    public let screenshots: [XCTAttachment]

    public init(name: String, passed: Bool, duration: TimeInterval, error: Error? = nil, screenshots: [XCTAttachment] = []) {
        self.name = name
        self.passed = passed
        self.duration = duration
        self.error = error
        self.screenshots = screenshots
    }
}

/// Result of a full test run
public struct TestRunResult {
    public let testName: String
    public let caseResults: [TestCaseResult]
    public let totalDuration: TimeInterval

    public var passedCount: Int {
        caseResults.filter { $0.passed }.count
    }

    public var failedCount: Int {
        caseResults.filter { !$0.passed }.count
    }

    public var allPassed: Bool {
        failedCount == 0
    }
}

/// Main test runner that executes JsonUI tests
public class JsonUITestRunner {

    private let actionExecutor: ActionExecutor
    private let assertionExecutor: AssertionExecutor
    private let config: TestRunnerConfig
    private var app: XCUIApplication

    public init(
        app: XCUIApplication,
        config: TestRunnerConfig = TestRunnerConfig(),
        stateProvider: ViewModelStateProvider? = nil
    ) {
        self.app = app
        self.config = config
        self.actionExecutor = XCUITestActionExecutor()
        self.assertionExecutor = XCUITestAssertionExecutor(stateProvider: stateProvider)
    }

    // MARK: - Screen Test Execution

    /// Run a screen test
    public func run(screenTest: ScreenTest) -> TestRunResult {
        let startTime = Date()
        var caseResults: [TestCaseResult] = []

        for testCase in screenTest.cases {
            // Skip if marked to skip
            if testCase.skip == true {
                let result = TestCaseResult(
                    name: testCase.name,
                    passed: true,
                    duration: 0,
                    error: nil
                )
                caseResults.append(result)
                continue
            }

            // Check platform filter
            if let platform = testCase.platform, !platform.includes(config.platform) {
                continue
            }

            let result = runTestCase(testCase, setup: screenTest.setup, teardown: screenTest.teardown)
            caseResults.append(result)

            if !result.passed && !config.continueOnFailure {
                break
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        return TestRunResult(
            testName: screenTest.metadata.name,
            caseResults: caseResults,
            totalDuration: totalDuration
        )
    }

    /// Run a single test case
    private func runTestCase(_ testCase: TestCase, setup: [TestStep]?, teardown: [TestStep]?) -> TestCaseResult {
        let startTime = Date()
        var screenshots: [XCTAttachment] = []

        do {
            // Execute setup
            if let setupSteps = setup {
                for step in setupSteps {
                    try executeStep(step)
                }
            }

            // Execute test steps
            for step in testCase.steps {
                try executeStep(step)
            }

            // Execute teardown
            if let teardownSteps = teardown {
                for step in teardownSteps {
                    try executeStep(step)
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: testCase.name, passed: true, duration: duration, screenshots: screenshots)

        } catch {
            // Take screenshot on failure
            if config.screenshotOnFailure {
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Failure_\(testCase.name)"
                attachment.lifetime = .keepAlways
                screenshots.append(attachment)
            }

            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: testCase.name, passed: false, duration: duration, error: error, screenshots: screenshots)
        }
    }

    // MARK: - Flow Test Execution

    /// Run a flow test
    public func run(flowTest: FlowTest) -> TestRunResult {
        let startTime = Date()

        // Check platform filter
        if let platform = flowTest.platform, !platform.includes(config.platform) {
            return TestRunResult(
                testName: flowTest.metadata.name,
                caseResults: [],
                totalDuration: 0
            )
        }

        let result = runFlowSteps(flowTest)
        let totalDuration = Date().timeIntervalSince(startTime)

        return TestRunResult(
            testName: flowTest.metadata.name,
            caseResults: [result],
            totalDuration: totalDuration
        )
    }

    private func runFlowSteps(_ flowTest: FlowTest) -> TestCaseResult {
        let startTime = Date()
        var screenshots: [XCTAttachment] = []
        var currentStepIndex = 0

        do {
            // Execute setup
            if let setupSteps = flowTest.setup {
                for step in setupSteps {
                    try executeFlowStep(step)
                }
            }

            // Execute flow steps
            for (index, step) in flowTest.steps.enumerated() {
                currentStepIndex = index
                try executeFlowStep(step)

                // Check for checkpoints
                if let checkpoints = flowTest.checkpoints {
                    for checkpoint in checkpoints where checkpoint.afterStep == index {
                        if checkpoint.screenshot == true {
                            let screenshot = app.screenshot()
                            let attachment = XCTAttachment(screenshot: screenshot)
                            attachment.name = "Checkpoint_\(checkpoint.name)"
                            attachment.lifetime = .keepAlways
                            screenshots.append(attachment)
                        }
                    }
                }
            }

            // Execute teardown
            if let teardownSteps = flowTest.teardown {
                for step in teardownSteps {
                    try executeFlowStep(step)
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: flowTest.metadata.name, passed: true, duration: duration, screenshots: screenshots)

        } catch {
            // Take screenshot on failure
            if config.screenshotOnFailure {
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Failure_Step\(currentStepIndex)"
                attachment.lifetime = .keepAlways
                screenshots.append(attachment)
            }

            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: flowTest.metadata.name, passed: false, duration: duration, error: error, screenshots: screenshots)
        }
    }

    // MARK: - Step Execution

    private func executeStep(_ step: TestStep) throws {
        if step.isAction {
            try actionExecutor.execute(step: step, in: app)
        } else if step.isAssertion {
            try assertionExecutor.execute(step: step, in: app)
        }
    }

    private func executeFlowStep(_ step: FlowTestStep) throws {
        if step.action != nil {
            try actionExecutor.execute(flowStep: step, in: app)
        } else if step.assert != nil {
            try assertionExecutor.execute(flowStep: step, in: app)
        }
    }
}

// MARK: - XCTestCase Extension for Easy Integration

extension XCTestCase {

    /// Run a JsonUI test from JSON data
    public func runJsonUITest(json: Data, app: XCUIApplication, config: TestRunnerConfig = TestRunnerConfig()) throws -> TestRunResult {
        // Parse JSON manually since we don't have a URL
        guard let jsonObject = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let type = jsonObject["type"] as? String else {
            throw TestLoaderError.invalidJSON(path: "inline", error: "Missing 'type' field")
        }

        let decoder = JSONDecoder()

        switch type {
        case "screen":
            let screenTest = try decoder.decode(ScreenTest.self, from: json)
            let runner = JsonUITestRunner(app: app, config: config)
            return runner.run(screenTest: screenTest)

        case "flow":
            let flowTest = try decoder.decode(FlowTest.self, from: json)
            let runner = JsonUITestRunner(app: app, config: config)
            return runner.run(flowTest: flowTest)

        default:
            throw TestLoaderError.unsupportedTestType(type: type)
        }
    }

    /// Run a JsonUI test from a bundle resource
    public func runJsonUITest(resourceName: String, bundle: Bundle = .main, app: XCUIApplication, config: TestRunnerConfig = TestRunnerConfig()) throws -> TestRunResult {
        let loader = TestLoader()
        let loadedTest = try loader.loadFromBundle(name: resourceName, bundle: bundle)

        let runner = JsonUITestRunner(app: app, config: config)

        switch loadedTest {
        case .screen(let screenTest):
            return runner.run(screenTest: screenTest)
        case .flow(let flowTest):
            return runner.run(flowTest: flowTest)
        }
    }
}
