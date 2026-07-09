import XCTest

/// Configuration for test execution
public struct TestRunnerConfig {
    public var platform: String = "ios"
    public var screenshotOnFailure: Bool = true
    public var continueOnFailure: Bool = false
    public var defaultTimeout: TimeInterval = 5.0
    /// Baseline directory for the `screenshot` assertion (default: temp dir)
    public var baselineDir: URL? = nil
    /// When true, screenshot baselines are always overwritten and the assertion passes
    public var updateBaselines: Bool = false
    /// When set, results are written to this path as standardized results JSON
    public var resultsPath: URL? = nil
    /// Mock server base URL (e.g. http://localhost:8790). Required to use `mocks` / `setMocks`.
    public var mockServerURL: URL? = nil
    /// Admin token printed by `jsonui-test mock serve`. Required with mockServerURL.
    public var mockToken: String? = nil

    public init() {}
}

/// Result of a single test case execution
public struct TestCaseResult {
    public let name: String
    public let passed: Bool
    public let duration: TimeInterval
    public let error: Error?
    public let screenshots: [XCTAttachment]
    /// True when the case was skipped (skip flag or platform mismatch)
    public let skipped: Bool
    /// Warnings collected during the case (optional-step failures, baseline created, ...)
    public let warnings: [String]

    public init(
        name: String,
        passed: Bool,
        duration: TimeInterval,
        error: Error? = nil,
        screenshots: [XCTAttachment] = [],
        skipped: Bool = false,
        warnings: [String] = []
    ) {
        self.name = name
        self.passed = passed
        self.duration = duration
        self.error = error
        self.screenshots = screenshots
        self.skipped = skipped
        self.warnings = warnings
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
    private var testLoader: TestLoader?
    private let mockClient: MockClient?
    /// Runtime variables (readText results), shared with the action executor
    private let variables = VariableStore()

    public init(
        app: XCUIApplication,
        config: TestRunnerConfig = TestRunnerConfig(),
        stateProvider: ViewModelStateProvider? = nil
    ) {
        self.app = app
        self.config = config
        self.actionExecutor = XCUITestActionExecutor(platform: config.platform, variables: variables)
        self.assertionExecutor = XCUITestAssertionExecutor(
            stateProvider: stateProvider,
            defaultTimeout: config.defaultTimeout,
            baselineDir: config.baselineDir,
            updateBaselines: config.updateBaselines
        )
        if let url = config.mockServerURL, let token = config.mockToken {
            self.mockClient = MockClient(baseURL: url, token: token)
        } else {
            self.mockClient = nil
        }
    }

    /// Return the configured mock client or throw a clear setup error.
    private func requireMockClient(_ feature: String) throws -> MockClient {
        guard let client = mockClient else {
            throw MockClientError.notConfigured(feature: feature)
        }
        return client
    }

    // MARK: - Launch Configuration

    /// Apply a launch configuration and (re)launch the app. Called before a test
    /// with a `launch` block runs.
    private func applyLaunch(_ launch: LaunchConfig) {
        if launch.clearState == true {
            app.launchEnvironment["JSONUI_TEST_CLEAR_STATE"] = "1"
        }
        if let arguments = launch.arguments, !arguments.isEmpty {
            var plain: [String: Any] = [:]
            for (key, value) in arguments {
                plain[key] = value.value
            }
            if let data = try? JSONSerialization.data(withJSONObject: plain),
               let json = String(data: data, encoding: .utf8) {
                app.launchEnvironment["JSONUI_TEST_ARGS"] = json
            }
        }
        // Permissions: reset to system default for `unset`. allow/deny require a
        // UI interruption monitor installed on the host XCTestCase (see
        // JsonUILaunchConfigurator); the runner records them as env hints.
        if let permissions = launch.permissions {
            if let data = try? JSONSerialization.data(withJSONObject: permissions),
               let json = String(data: data, encoding: .utf8) {
                app.launchEnvironment["JSONUI_TEST_PERMISSIONS"] = json
            }
        }
        app.launch()
    }

    /// Set a test loader for file reference resolution
    public func setTestLoader(_ loader: TestLoader) {
        self.testLoader = loader
    }

    // MARK: - Screen Test Execution

    /// Run a screen test
    public func run(screenTest: ScreenTest) -> TestRunResult {
        let startTime = Date()
        var caseResults: [TestCaseResult] = []

        // Apply the file-level mock scenario set BEFORE the app (re)launches, so the
        // screen fetches under the selected scenarios. Scenario switching is per-file
        // for screen tests; there is no per-case re-open (see plan §8.1).
        if let mocks = screenTest.mocks {
            do {
                try requireMockClient("mocks").scenarioSet(mocks)
            } catch {
                let failed = screenTest.cases.map {
                    TestCaseResult(name: $0.name, passed: false, duration: 0, error: error)
                }
                return TestRunResult(testName: screenTest.metadata.name, caseResults: failed, totalDuration: Date().timeIntervalSince(startTime))
            }
        }

        // Apply launch configuration (relaunches the app) before running cases.
        // If mocks were set but there is no launch block, still relaunch so the
        // screen re-fetches under the new scenarios.
        if let launch = screenTest.launch {
            applyLaunch(launch)
        } else if screenTest.mocks != nil {
            app.launch()
        }

        // Run setup once. If it throws, every case is recorded as failed but
        // teardown still runs (§7 teardown guarantee).
        var setupError: Error? = nil
        if let setupSteps = screenTest.setup {
            do {
                var warnings: [String] = []
                try executeSteps(setupSteps, warnings: &warnings)
            } catch {
                setupError = error
            }
        }

        for testCase in screenTest.cases {
            // Skip if marked to skip
            if testCase.skip == true {
                caseResults.append(TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true))
                continue
            }

            // Check platform filter
            if let platform = testCase.platform, !platform.includes(config.platform) {
                caseResults.append(TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true))
                continue
            }

            if let setupError = setupError {
                caseResults.append(TestCaseResult(
                    name: testCase.name,
                    passed: false,
                    duration: 0,
                    error: TestRunnerError.setupFailed(reason: setupError.localizedDescription)
                ))
                continue
            }

            let result = runTestCase(testCase)
            caseResults.append(result)

            if !result.passed && !config.continueOnFailure {
                break
            }
        }

        // Teardown (guaranteed). A teardown failure is recorded as an extra failed result.
        if let teardownSteps = screenTest.teardown {
            do {
                var warnings: [String] = []
                try executeSteps(teardownSteps, warnings: &warnings)
            } catch {
                caseResults.append(TestCaseResult(name: "teardown", passed: false, duration: 0, error: error))
            }
        }

        // Reset mock scenarios so state does not leak into the next test file.
        if screenTest.mocks != nil {
            try? mockClient?.reset()
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let result = TestRunResult(
            testName: screenTest.metadata.name,
            caseResults: caseResults,
            totalDuration: totalDuration
        )
        writeResultsIfNeeded(result)
        return result
    }

    /// Run a single test case (setup/teardown are handled by the caller)
    private func runTestCase(_ testCase: TestCase) -> TestCaseResult {
        let startTime = Date()
        var screenshots: [XCTAttachment] = []
        var warnings: [String] = []

        // Apply load-time args substitution if test case has args
        let processedCase: TestCase
        if let loader = testLoader {
            processedCase = loader.applyArgsSubstitution(to: testCase)
        } else {
            processedCase = applyArgsSubstitutionLocally(to: testCase)
        }

        do {
            try executeSteps(processedCase.steps, warnings: &warnings)
            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: testCase.name, passed: true, duration: duration, screenshots: screenshots, warnings: warnings)
        } catch {
            if config.screenshotOnFailure {
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Failure_\(testCase.name)"
                attachment.lifetime = .keepAlways
                screenshots.append(attachment)
            }
            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: testCase.name, passed: false, duration: duration, error: error, screenshots: screenshots, warnings: warnings)
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

        // Apply launch configuration (relaunches the app) before running
        if let launch = flowTest.launch {
            applyLaunch(launch)
        }

        let caseResults = runFlowSteps(flowTest)

        // Reset mock scenarios so a flow's setMocks state does not leak to the next test.
        try? mockClient?.reset()

        let totalDuration = Date().timeIntervalSince(startTime)

        let result = TestRunResult(
            testName: flowTest.metadata.name,
            caseResults: caseResults,
            totalDuration: totalDuration
        )
        writeResultsIfNeeded(result)
        return result
    }

    private func runFlowSteps(_ flowTest: FlowTest) -> [TestCaseResult] {
        let startTime = Date()
        var screenshots: [XCTAttachment] = []
        var warnings: [String] = []
        var currentStepIndex = 0
        var flowError: Error? = nil

        do {
            // Execute setup
            if let setupSteps = flowTest.setup {
                for step in setupSteps {
                    try executeFlowStep(step, warnings: &warnings)
                }
            }

            // Execute flow steps
            for (index, step) in flowTest.steps.enumerated() {
                currentStepIndex = index
                try executeFlowStep(step, warnings: &warnings)

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
        } catch {
            flowError = error
            if config.screenshotOnFailure {
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Failure_Step\(currentStepIndex)"
                attachment.lifetime = .keepAlways
                screenshots.append(attachment)
            }
        }

        var results: [TestCaseResult] = [
            TestCaseResult(
                name: flowTest.metadata.name,
                passed: flowError == nil,
                duration: Date().timeIntervalSince(startTime),
                error: flowError,
                screenshots: screenshots,
                warnings: warnings
            )
        ]

        // Teardown (guaranteed), runs even when the flow body failed
        if let teardownSteps = flowTest.teardown {
            do {
                var teardownWarnings: [String] = []
                for step in teardownSteps {
                    try executeFlowStep(step, warnings: &teardownWarnings)
                }
            } catch {
                results.append(TestCaseResult(name: "teardown", passed: false, duration: 0, error: error))
            }
        }

        return results
    }

    // MARK: - Step Execution

    /// Execute a sequence of steps, collecting warnings.
    private func executeSteps(_ steps: [TestStep], warnings: inout [String]) throws {
        for step in steps {
            try executeStepGuarded(step, warnings: &warnings)
        }
    }

    /// Execute a single step honoring `when` (skip), `optional` (failure→warning),
    /// runtime `@{name}` substitution, and control steps (repeat/retry).
    private func executeStepGuarded(_ rawStep: TestStep, warnings: inout [String]) throws {
        // Resolve runtime variables (@{name}) at execution time
        let step = substituteRuntimeVariables(rawStep)

        // Evaluate `when` pre-condition
        if let condition = step.when {
            let satisfied = try assertionExecutor.evaluate(condition: condition, platform: config.platform, in: app)
            if !satisfied {
                return
            }
        }

        do {
            try executeStep(step, warnings: &warnings)
        } catch {
            if step.optional == true {
                let label = step.label ?? step.action ?? step.assert ?? "step"
                warnings.append("optional step failed (\(label)): \(error.localizedDescription)")
                return
            }
            throw error
        }
    }

    private func executeStep(_ step: TestStep, warnings: inout [String]) throws {
        // Control steps
        if step.action == "repeat" {
            try executeRepeat(step, warnings: &warnings)
            return
        }
        if step.action == "retry" {
            try executeRetry(step, warnings: &warnings)
            return
        }
        if step.action == "setMocks" {
            // Switch scenarios mid-flow; the next navigation re-fetches under them.
            try requireMockClient("setMocks").scenarioSet(step.mocks ?? [:])
            return
        }

        if step.isAction {
            try actionExecutor.execute(step: step, in: app)
        } else if step.isAssertion {
            try assertionExecutor.execute(step: step, in: app)
            warnings.append(contentsOf: assertionExecutor.drainWarnings())
        }
    }

    private func executeRepeat(_ step: TestStep, warnings: inout [String]) throws {
        let steps = step.steps ?? []
        let hasTimes = step.times != nil
        let hasWhile = step.while != nil

        if hasTimes && hasWhile {
            for _ in 0..<(step.times ?? 0) {
                if !(try assertionExecutor.evaluate(condition: step.while!, platform: config.platform, in: app)) {
                    return
                }
                try executeSteps(steps, warnings: &warnings)
            }
            return
        }
        if hasTimes {
            for _ in 0..<(step.times ?? 0) {
                try executeSteps(steps, warnings: &warnings)
            }
            return
        }
        // while only: safety cap of 100
        for _ in 0..<100 {
            if !(try assertionExecutor.evaluate(condition: step.while!, platform: config.platform, in: app)) {
                return
            }
            try executeSteps(steps, warnings: &warnings)
        }
        if try assertionExecutor.evaluate(condition: step.while!, platform: config.platform, in: app) {
            throw TestRunnerError.repeatExceededCap
        }
    }

    private func executeRetry(_ step: TestStep, warnings: inout [String]) throws {
        let steps = step.steps ?? []
        let maxRetries = min(step.maxRetries ?? 1, 3)
        var lastError: Error?

        for _ in 0...maxRetries {
            do {
                var attemptWarnings: [String] = []
                try executeSteps(steps, warnings: &attemptWarnings)
                warnings.append(contentsOf: attemptWarnings)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? TestRunnerError.retryExhausted
    }

    /// Substitute @{name} runtime variables into a step's string fields at execution time.
    private func substituteRuntimeVariables(_ step: TestStep) -> TestStep {
        if variables.isEmpty {
            return step
        }
        return substituteArgsInStep(step, args: variables.asDictionary)
    }

    private func executeFlowStep(_ step: FlowTestStep, warnings: inout [String]) throws {
        // Step-level `when` for file / block / inline steps
        if let condition = step.when {
            let satisfied = try assertionExecutor.evaluate(condition: condition, platform: config.platform, in: app)
            if !satisfied {
                return
            }
        }

        // Handle file reference steps
        if step.isFileReference {
            try executeFileReferenceStep(step, warnings: &warnings)
            return
        }

        // Handle block steps (grouped inline actions)
        if step.isBlockStep {
            try executeBlockStep(step, warnings: &warnings)
            return
        }

        // Handle inline steps
        if step.action != nil || step.assert != nil {
            try executeStepGuarded(step.toTestStep(), warnings: &warnings)
        }
    }

    private func executeBlockStep(_ step: FlowTestStep, warnings: inout [String]) throws {
        guard let blockSteps = step.steps else {
            return
        }
        for innerStep in blockSteps {
            try executeStepGuarded(innerStep.toTestStep(), warnings: &warnings)
        }
    }

    private func executeFileReferenceStep(_ step: FlowTestStep, warnings: inout [String]) throws {
        guard let loader = testLoader else {
            throw TestLoaderError.fileNotFound(path: step.file ?? "unknown")
        }

        let testCases = try loader.resolveFileReferenceCases(step)

        for testCase in testCases {
            // Skip if marked to skip
            if testCase.skip == true {
                continue
            }

            // Check platform filter
            if let platform = testCase.platform, !platform.includes(config.platform) {
                continue
            }

            try executeSteps(testCase.steps, warnings: &warnings)
        }
    }

    // MARK: - Args Substitution (Local fallback when testLoader is not available)

    /// Apply args substitution locally when testLoader is not set
    private func applyArgsSubstitutionLocally(to testCase: TestCase) -> TestCase {
        guard let args = testCase.args, !args.isEmpty else {
            return testCase
        }

        // Convert AnyCodable args to [String: Any]
        var argsDict: [String: Any] = [:]
        for (key, value) in args {
            argsDict[key] = value.value
        }

        // Apply substitution to steps
        let substitutedSteps = testCase.steps.map { substituteArgsInStep($0, args: argsDict) }

        return TestCase(
            name: testCase.name,
            description: testCase.description,
            skip: testCase.skip,
            platform: testCase.platform,
            initialState: testCase.initialState,
            steps: substitutedSteps,
            args: testCase.args
        )
    }

    /// Substitute @{varName} placeholders in a TestStep, preserving all fields.
    /// Nested control-step `steps` are substituted recursively.
    private func substituteArgsInStep(_ step: TestStep, args: [String: Any]) -> TestStep {
        return TestStep(
            action: step.action,
            assert: step.assert,
            id: substituteArgsInOptionalString(step.id, args: args),
            ids: step.ids?.map { substituteArgsInString($0, args: args) },
            text: substituteArgsInOptionalString(step.text, args: args),
            value: substituteArgsInOptionalString(step.value, args: args),
            direction: step.direction,
            duration: step.duration,
            timeout: step.timeout,
            ms: step.ms,
            name: substituteArgsInOptionalString(step.name, args: args),
            equals: substituteArgsInAnyCodable(step.equals, args: args),
            contains: substituteArgsInOptionalString(step.contains, args: args),
            path: substituteArgsInOptionalString(step.path, args: args),
            amount: step.amount,
            button: substituteArgsInOptionalString(step.button, args: args),
            label: substituteArgsInOptionalString(step.label, args: args),
            index: step.index,
            optional: step.optional,
            when: step.when,
            retryTapIfNoChange: step.retryTapIfNoChange,
            container: substituteArgsInOptionalString(step.container, args: args),
            variable: step.variable,
            times: step.times,
            while: step.while,
            steps: step.steps?.map { substituteArgsInStep($0, args: args) },
            maxRetries: step.maxRetries,
            latitude: step.latitude,
            longitude: step.longitude,
            paths: step.paths,
            cropId: substituteArgsInOptionalString(step.cropId, args: args),
            threshold: step.threshold,
            mocks: step.mocks
        )
    }

    /// Substitute @{varName} placeholders in an optional string
    private func substituteArgsInOptionalString(_ string: String?, args: [String: Any]) -> String? {
        guard let string = string else { return nil }
        return substituteArgsInString(string, args: args)
    }

    /// Substitute @{varName} placeholders in a string
    private func substituteArgsInString(_ string: String, args: [String: Any]) -> String {
        var result = string
        let pattern = #"@\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return string
        }

        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = regex.matches(in: string, range: range)

        // Replace from end to start to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let varNameRange = Range(match.range(at: 1), in: result) else {
                continue
            }

            let varName = String(result[varNameRange])
            if let value = args[varName] {
                let replacement = stringValueFromAny(value)
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        return result
    }

    /// Substitute @{varName} in AnyCodable (only for string values)
    private func substituteArgsInAnyCodable(_ anyCodable: AnyCodable?, args: [String: Any]) -> AnyCodable? {
        guard let anyCodable = anyCodable else { return nil }
        if let stringValue = anyCodable.stringValue {
            let substituted = substituteArgsInString(stringValue, args: args)
            return AnyCodable(substituted)
        }
        return anyCodable
    }

    /// Convert Any to String
    private func stringValueFromAny(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let bool as Bool:
            return String(bool)
        default:
            return String(describing: value)
        }
    }

    // MARK: - Results Output

    private func writeResultsIfNeeded(_ result: TestRunResult) {
        guard let path = config.resultsPath else { return }
        try? ResultsWriter.write([result], to: path, platform: config.platform)
    }
}

/// Errors surfaced by the test runner's control flow
public enum TestRunnerError: Error, LocalizedError {
    case setupFailed(reason: String)
    case repeatExceededCap
    case retryExhausted

    public var errorDescription: String? {
        switch self {
        case .setupFailed(let reason):
            return "setup failed: \(reason)"
        case .repeatExceededCap:
            return "repeat exceeded 100 iterations (possible infinite loop)"
        case .retryExhausted:
            return "retry exhausted with no error captured"
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
