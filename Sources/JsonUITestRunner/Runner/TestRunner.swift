import XCTest

/// Configuration for test execution
public struct TestRunnerConfig {
    public var platform: String = "ios"
    public var screenshotOnFailure: Bool = true
    public var defaultTimeout: TimeInterval = 5.0
    /// Extra attempts for a FAILED case (or flow body) before recording the
    /// failure — 0 (default) keeps single-run behaviour. The final result
    /// carries `attempts` (total runs) and a pass after a retry is marked
    /// `flaky` in the results JSON. Retries re-run the steps as-is (no
    /// re-launch between attempts), so cases that mutate app state
    /// non-idempotently may not benefit.
    public var caseRetries: Int = 0
    /// Verify the screen marker automatically whenever a flow's inline step
    /// moves to a different `screen`, without the test spelling an
    /// assertion. ON by default — this is the canonical behaviour.
    ///
    /// An app whose generated code predates screen markers will fail every
    /// screen change with `marker-absent`. That is the intended signal: the
    /// app needs `jui build` and a current library pin. Set this to false to
    /// opt out while migrating.
    public var verifyScreenTransitions: Bool = true
    /// Timeout for those implicit verifications. Deliberately larger than
    /// defaultTimeout: real cross-screen waits already use 15-20s after a
    /// cold start.
    public var screenTransitionTimeout: TimeInterval = 10.0
    /// How long the runner waits for a screen to confirm the initialState it
    /// was sent (its state bridge showing a receipt for the launch), spec
    /// §10.5. Same name and default as the web driver's setting.
    public var screenReadyTimeout: TimeInterval = 15.0
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
    /// Bundle that carries `addMedia` fixtures (flattened into its root by the
    /// CLI install). Defaults to the bundle the test JSON was loaded from in
    /// runJsonUITest(resourceName:bundle:), else the driver's own bundle.
    public var mediaBundle: Bundle? = nil

    public init() {}
}

/// Why a skipped result was skipped; only set for gate-caused skips
/// (results.schema.json skipReason). Plain `skip: true` skips carry no reason.
public enum SkipReason: String {
    case platform
    case responsive
}

/// Result of a single test case execution
public struct TestCaseResult {
    public let name: String
    public let passed: Bool
    public let duration: TimeInterval
    public let error: Error?
    public let screenshots: [XCTAttachment]
    /// True when the case was skipped (skip flag, platform or responsive mismatch)
    public let skipped: Bool
    /// Why the case was skipped (platform vs responsive gate); nil for plain `skip: true` skips
    public let skipReason: SkipReason?
    /// Warnings collected during the case (optional-step failures, baseline created, ...)
    public let warnings: [String]
    /// How many times the case ran in total, retries included (1 = settled
    /// on the first run). Nil on skipped rows — a case that never ran has
    /// no attempt count (results.schema.json attempts).
    public let attempts: Int?
    /// The orientation this case asked for, after the whole chain: a
    /// `setOrientation` step, else the file's `orientation`, else the run
    /// default for this device's tier. Nil when nothing declared one — which
    /// is a real state (the device stayed as it booted), not "portrait".
    public let declaredOrientation: Orientation?
    /// The orientation the device was ACTUALLY in, asked of the device.
    ///
    /// ⚠️ Reported separately from `declaredOrientation` on purpose. Derived
    /// from the declaration the two would agree by construction and measure
    /// nothing; the disagreement is the whole reason the pair exists. It is
    /// not hypothetical — the Android driver mapped "portrait" onto a
    /// natural-relative rotation, so on a tablet whose natural orientation is
    /// landscape a run that declared portrait executed in landscape and passed
    /// with nothing recording the difference.
    public let observedOrientation: Orientation?

    public init(
        name: String,
        passed: Bool,
        duration: TimeInterval,
        error: Error? = nil,
        screenshots: [XCTAttachment] = [],
        skipped: Bool = false,
        skipReason: SkipReason? = nil,
        warnings: [String] = [],
        attempts: Int? = nil,
        declaredOrientation: Orientation? = nil,
        observedOrientation: Orientation? = nil
    ) {
        self.name = name
        self.passed = passed
        self.duration = duration
        self.error = error
        self.screenshots = screenshots
        self.skipped = skipped
        self.skipReason = skipReason
        self.warnings = warnings
        self.attempts = attempts
        self.declaredOrientation = declaredOrientation
        self.observedOrientation = observedOrientation
    }

    /// Copy with the attempts stamp (results.schema.json attempts).
    ///
    /// ⚠️ Every field is listed. A copy helper that names a subset drops
    /// whatever is added after it was written, silently and only on the path
    /// that uses it — here, only on cases that needed a retry, which is the
    /// hardest population to notice a gap in.
    func stamping(attempts: Int) -> TestCaseResult {
        TestCaseResult(
            name: name,
            passed: passed,
            duration: duration,
            error: error,
            screenshots: screenshots,
            skipped: skipped,
            skipReason: skipReason,
            warnings: warnings,
            attempts: attempts,
            declaredOrientation: declaredOrientation,
            observedOrientation: observedOrientation
        )
    }

    /// Copy with more warnings appended. Every field listed (see above).
    func adding(warnings more: [String]) -> TestCaseResult {
        TestCaseResult(
            name: name,
            passed: passed,
            duration: duration,
            error: error,
            screenshots: screenshots,
            skipped: skipped,
            skipReason: skipReason,
            warnings: warnings + more,
            attempts: attempts,
            declaredOrientation: declaredOrientation,
            observedOrientation: observedOrientation
        )
    }

    /// Copy with the orientation pair, recorded once the case has finished.
    func stamping(declared: Orientation?, observed: Orientation?) -> TestCaseResult {
        TestCaseResult(
            name: name,
            passed: passed,
            duration: duration,
            error: error,
            screenshots: screenshots,
            skipped: skipped,
            skipReason: skipReason,
            warnings: warnings,
            attempts: attempts,
            declaredOrientation: declared,
            observedOrientation: observed
        )
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
    /// Identity of the test file / case currently executing — embedded into
    /// artifact attachment names so `jsonui-test artifacts pull` can organize
    /// captures per test/case (parity with android/web `failure_<test>_<case>`).
    private var currentTestName = ""
    private var currentCaseName = ""
    /// Run-scoped defaults, read once from the installed bundle.
    ///
    /// Read once because it cannot change during a run and because a failure
    /// to read it should be reported once rather than per case. Not folded to
    /// an empty table on failure — see `RunDefaults.Load`.
    private lazy var runDefaults: RunDefaults.Load = RunDefaults.load()
    /// Progress records (progress.schema.json) to unified logging. Internal
    /// and settable so a test can give it another sink.
    var progress = TestProgressReporter()
    /// The file the progress lines of this run name: the test's `sourceFile`
    /// when a TestLoader read it, else "inline" (built in code or from inline
    /// JSON — the same word TestLoaderError uses for that path).
    private var progressFile = "inline"

    public init(
        app: XCUIApplication,
        config: TestRunnerConfig = TestRunnerConfig(),
        stateProvider: ViewModelStateProvider? = nil
    ) {
        self.app = app
        self.config = config
        let executor = XCUITestActionExecutor(platform: config.platform, variables: variables)
        executor.mediaBundle = config.mediaBundle
        self.actionExecutor = executor
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
        // Route `screenshot` action captures into the xcresult with test/case
        // identity in the name — the artifacts extractor collects them from there.
        executor.screenshotAttachmentHandler = { [weak self] name, screenshot in
            guard let self = self else { return }
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Screenshot_\(self.currentTestName)_\(self.currentCaseName)_\(name)"
            attachment.lifetime = .keepAlways
            self.attachArtifact(attachment)
        }
    }

    /// Attach an artifact into the running test's xcresult. Library code is not
    /// an XCTestCase, but XCTContext.runActivity works from anywhere inside a
    /// test's execution context, so attachments land in the xcresult without
    /// requiring the consuming harness to call add() itself (verified on the
    /// conformance host: exported by `xcresulttool export attachments` with the
    /// attachment name preserved as the suggested human-readable name).
    private func attachArtifact(_ attachment: XCTAttachment) {
        XCTContext.runActivity(named: attachment.name ?? "JsonUI Artifact") { activity in
            activity.add(attachment)
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

    /// The one place the runner launches the app (spec §10.2): the four
    /// launch keys it owns are removed and set again for this launch
    /// (LaunchEnvironment), the initialState payload rides with a fresh
    /// launchId, and the app launches once. Returns the launchId when a
    /// payload went with it, for the receipt wait.
    @discardableResult
    private func relaunch(_ launch: LaunchConfig?, screens: [String: [String: Any]]?) -> String? {
        var launchId: String?
        var payload: String?
        if let screens, !screens.isEmpty {
            let id = UUID().uuidString
            if let encoded = InitialStatePayload.encode(screens: screens, launchId: id) {
                launchId = id
                payload = encoded
            }
        }
        app.launchEnvironment = LaunchEnvironment.environment(
            base: app.launchEnvironment, launch: launch, initialStatePayload: payload)
        app.launch()
        return launchId
    }

    /// Wait for `screenId` to confirm launch `launchId`'s initialState
    /// (spec §10.5). Throws a setup failure naming the cause when it does not,
    /// or when it rejected keys.
    private func waitForReceipt(screenId: String, launchId: String) throws {
        let deadline = Date().addingTimeInterval(config.screenReadyTimeout)
        var last = StateBridge.Reading.absent
        repeat {
            last = StateBridge.read(screenId, in: app)
            switch StateBridge.receipt(last, launchId: launchId) {
            case .confirmed:
                return
            case .rejected(let rejections):
                throw TestRunnerError.setupFailed(reason: StateBridge.rejectedMessage(screenId: screenId, rejections))
            case .truncated:
                throw TestRunnerError.setupFailed(reason: StateBridge.noReceiptMessage(
                    screenId: screenId, timeout: config.screenReadyTimeout, lastReading: last))
            case .waiting:
                Thread.sleep(forTimeInterval: 0.2)
            }
        } while Date() < deadline
        throw TestRunnerError.setupFailed(reason: StateBridge.noReceiptMessage(
            screenId: screenId, timeout: config.screenReadyTimeout, lastReading: last))
    }

    /// Launch for one entry of a plan and, when it carried a payload, wait for
    /// the screen under test to confirm it.
    private func launch(_ entry: InitialStatePlan.Launch, config launch: LaunchConfig?, screenId: String) throws {
        if let launchId = relaunch(launch, screens: entry.screens) {
            try waitForReceipt(screenId: screenId, launchId: launchId)
        }
    }

    /// Set a test loader for file reference resolution
    public func setTestLoader(_ loader: TestLoader) {
        self.testLoader = loader
    }

    // MARK: - Screen Test Execution

    /// Run a screen test
    public func run(screenTest: ScreenTest) -> TestRunResult {
        let startTime = Date()
        // One file per run: the one this call was given (a flow's referenced
        // files are read too, but emit nothing of their own).
        progressFile = screenTest.sourceFile ?? "inline"
        progress.runStarted(files: 1)

        // Test-level platform gate: emit one skipped row PER CASE (never an
        // empty caseResults) so a file-level skip stays visible in the report
        // — the plan's "no silent truncation" rule.
        if let platform = screenTest.platform, !platform.includes(config.platform) {
            let skippedRows = screenTest.cases.map {
                TestCaseResult(name: $0.name, passed: true, duration: 0, skipped: true, skipReason: .platform)
            }
            for row in skippedRows {
                progress.caseSkipped(progressCase(screenTest.metadata.name, row.name))
            }
            let result = TestRunResult(
                testName: screenTest.metadata.name,
                caseResults: skippedRows,
                totalDuration: Date().timeIntervalSince(startTime)
            )
            writeResultsIfNeeded(result)
            progress.runEnded(rows: result.caseResults)
            return result
        }

        // Artifact identity for this file (setup/teardown captures carry the
        // phase name until runTestCase overwrites the case name).
        currentTestName = screenTest.metadata.name
        currentCaseName = "setup"

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
                for row in failed {
                    progress.caseFailedWithoutRunning(progressCase(screenTest.metadata.name, row.name))
                }
                progress.runEnded(rows: failed)
                return TestRunResult(testName: screenTest.metadata.name, caseResults: failed, totalDuration: Date().timeIntervalSince(startTime))
            }
        }

        // The launches this file makes and what each carries (spec §10.2),
        // decided once. Under shared there is at most one, before the first
        // case; it happens when the file has a launch, mocks or initialState,
        // and its receipt is awaited before setup.
        let plan = InitialStatePlan.plan(screenTest: screenTest)
        let screenId = ScreenIdentity.screenId(layoutPath: screenTest.source.layout)
        assertionExecutor.setStateScreen(screenId)
        var launchError: Error?
        if (screenTest.caseIsolation ?? .shared) == .shared, let entry = plan.launches.first {
            do {
                try launch(entry, config: screenTest.launch, screenId: screenId)
            } catch {
                launchError = error
            }
        }

        // Orientation for this run, applied ONCE and BEFORE setup.
        //
        // Before setup and before the readiness gate on purpose: applied after
        // them, both would have run in whatever orientation the device booted
        // in, and the run would not be the run the file asked for. Nothing is
        // applied when nothing declared one — the device is left as it booted,
        // which is a real state and is reported as `declaredOrientation`
        // absent rather than as a default nobody chose.
        let runDeclaredOrientation = OrientationRuntime.resolveDeclared(
            fileOrientation: screenTest.orientation,
            defaults: runDefaults,
            tier: OrientationRuntime.tier(
                horizontalSizeClass: ResponsiveRuntime
                    .currentEnvironment(app: app).horizontalSizeClass,
                declaredTiers: runDefaults.declaredTiers
            )
        )
        if let runDeclaredOrientation {
            OrientationRuntime.apply(runDeclaredOrientation)
        }

        let caseResults: [TestCaseResult]
        if (screenTest.caseIsolation ?? .shared) == .reopen {
            caseResults = runCasesReopened(screenTest, plan: plan, screenId: screenId,
                                           runDeclaredOrientation: runDeclaredOrientation)
        } else {
            caseResults = runCasesShared(screenTest, plan: plan, launchError: launchError,
                                         runDeclaredOrientation: runDeclaredOrientation)
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
        progress.runEnded(rows: result.caseResults)
        return result
    }

    /// The case a progress line is about, in this run's file.
    private func progressCase(_ testName: String, _ caseName: String) -> ProgressRecord.Case {
        ProgressRecord.Case(file: progressFile, test: testName, name: caseName)
    }

    /// `caseIsolation: shared` (the default): setup once, every case in the
    /// one app state the previous case left (its scroll position, the screen
    /// it navigated to), teardown once. The order of the cases matters.
    private func runCasesShared(_ screenTest: ScreenTest, plan: InitialStatePlan, launchError: Error?,
                                runDeclaredOrientation: Orientation?) -> [TestCaseResult] {
        var caseResults: [TestCaseResult] = []
        // Run setup once. If it throws, every case is recorded as failed but
        // teardown still runs (§7 teardown guarantee). A launch whose
        // initialState was not confirmed fails the cases the same way, and
        // setup does not run on an app in an unknown state.
        var setupError: Error? = launchError
        let needsReopen = Set(plan.caseFailures.filter { $0.code == InitialStatePlan.caseNeedsReopen }.map(\.caseName))
        if setupError == nil, let setupSteps = screenTest.setup {
            do {
                var warnings: [String] = []
                try executeSteps(setupSteps, warnings: &warnings)
            } catch {
                setupError = error
            }
        }

        let testName = screenTest.metadata.name
        caseResults = SharedCases.run(
            cases: screenTest.cases,
            progress: (progress, progressFile, testName, { $0.name }),
            hooks: SharedCases.Hooks(
                gate: { self.gateRow($0) },
                unrunnable: { testCase in
                    if let setupError = setupError {
                        return TestCaseResult(
                            name: testCase.name,
                            passed: false,
                            duration: 0,
                            error: setupError is TestRunnerError
                                ? setupError
                                : TestRunnerError.setupFailed(reason: setupError.localizedDescription)
                        )
                    }
                    // A case-level initialState under shared has no launch to ride
                    // (spec §10.2): fail this case, not the file.
                    if needsReopen.contains(testCase.name) {
                        return TestCaseResult(
                            name: testCase.name,
                            passed: false,
                            duration: 0,
                            error: TestRunnerError.setupFailed(reason:
                                "case '\(testCase.name)' has its own initialState, which needs caseIsolation \"reopen\": "
                                + "under \"shared\" the screen is opened once, before the first case "
                                + "(\(InitialStatePlan.caseNeedsReopen))")
                        )
                    }
                    return nil
                },
                body: { testCase in
                    // Stamped AFTER the case, never before: `observed` has to be the
                    // orientation the case actually finished in, and `declared` has to
                    // include a `setOrientation` step the case performed. Only on rows
                    // that ran — a skipped case has no orientation to report, the same
                    // reason `attempts` is absent there.
                    self.runTestCaseWithRetries(testCase, testName: testName).stamping(
                        declared: OrientationRuntime.declaredForCase(
                            steps: testCase.steps, runDeclared: runDeclaredOrientation),
                        observed: OrientationRuntime.observe(app: self.app)
                    )
                }
            )
        )

        // Teardown (guaranteed). A teardown failure is recorded as an extra failed result.
        if let teardownSteps = screenTest.teardown {
            currentCaseName = "teardown"
            do {
                var warnings: [String] = []
                try executeSteps(teardownSteps, warnings: &warnings)
            } catch {
                caseResults.append(TestCaseResult(name: "teardown", passed: false, duration: 0, error: error))
                progress.caseFailedWithoutRunning(progressCase(testName, "teardown"))
            }
        }

        return caseResults
    }

    /// `caseIsolation: reopen`: every case that runs starts from a freshly
    /// launched app. Before each case the file's mock scenarios are
    /// re-applied, the app is relaunched with the file's `launch` block
    /// (`applyLaunch`) or a plain `app.launch()`, and the run orientation is
    /// re-applied; then setup, the case, and teardown. A gated case launches
    /// nothing. Each retry attempt relaunches too.
    ///
    /// Failure semantics per case, as the shared path has them per file: a
    /// setup failure fails that case (the body never ran) and its teardown
    /// still runs; a teardown failure is an extra `teardown` row; a failed
    /// case does not stop the file, the next case runs.
    private func runCasesReopened(_ screenTest: ScreenTest, plan: InitialStatePlan, screenId: String,
                                  runDeclaredOrientation: Orientation?) -> [TestCaseResult] {
        ReopenedCases.run(
            cases: screenTest.cases,
            retries: config.caseRetries,
            progress: (progress, progressFile, screenTest.metadata.name, { $0.name }),
            hooks: ReopenedCases.Hooks(
                gate: { self.gateRow($0) },
                reopen: { testCase in
                    self.currentCaseName = "setup"
                    if let mocks = screenTest.mocks {
                        try self.requireMockClient("mocks").scenarioSet(mocks)
                    }
                    // This case's launch from the plan: the file's initialState
                    // merged with the case's (spec §10.2).
                    let entry = plan.launches.first { $0.before == .testCase(testCase.name) }
                        ?? InitialStatePlan.Launch(before: .testCase(testCase.name), screens: nil)
                    try self.launch(entry, config: screenTest.launch, screenId: screenId)
                    if let runDeclaredOrientation {
                        OrientationRuntime.apply(runDeclaredOrientation)
                    }
                },
                setup: {
                    guard let setupSteps = screenTest.setup else { return }
                    var warnings: [String] = []
                    try self.executeSteps(setupSteps, warnings: &warnings)
                },
                body: { testCase in
                    self.runTestCase(testCase).stamping(
                        declared: OrientationRuntime.declaredForCase(
                            steps: testCase.steps, runDeclared: runDeclaredOrientation),
                        observed: OrientationRuntime.observe(app: self.app)
                    )
                },
                teardown: {
                    guard let teardownSteps = screenTest.teardown else { return }
                    self.currentCaseName = "teardown"
                    var warnings: [String] = []
                    try self.executeSteps(teardownSteps, warnings: &warnings)
                },
                setupFailed: { testCase, error in
                    TestCaseResult(
                        name: testCase.name,
                        passed: false,
                        duration: 0,
                        error: error is MockClientError
                            ? error
                            : TestRunnerError.setupFailed(reason: error.localizedDescription)
                    )
                },
                teardownFailed: { _, error in
                    TestCaseResult(name: "teardown", passed: false, duration: 0, error: error)
                },
                isPass: { $0.passed },
                stampAttempts: { $0.stamping(attempts: $1) }
            )
        )
    }

    /// The gates a case passes before anything runs — `skip`, case-level
    /// platform, case-level responsive. Returns the skipped row, or nil when
    /// the case should run.
    private func gateRow(_ testCase: TestCase) -> TestCaseResult? {
        // Skip if marked to skip
        if testCase.skip == true {
            return TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true)
        }

        // Check platform filter. Deterministic skip-reason rule: platform
        // is evaluated BEFORE responsive, so when a case carries both
        // gates and both are unmet, skipReason is "platform" (the static
        // gate wins over the size-dependent one, keeping reports stable
        // across device sizes).
        if let platform = testCase.platform, !platform.includes(config.platform) {
            return TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true, skipReason: .platform)
        }

        // Case-level responsive gate, evaluated against the live
        // device/window size (parallel to the platform gate).
        if let responsive = testCase.responsive, !ResponsiveRuntime.matches(responsive, app: app) {
            return TestCaseResult(name: testCase.name, passed: true, duration: 0, skipped: true, skipReason: .responsive)
        }
        return nil
    }

    /// Run a case, re-running it up to `config.caseRetries` extra times
    /// while it fails. The returned result is the final attempt's, stamped
    /// with the total attempt count (skips are handled by the caller and
    /// never reach this).
    private func runTestCaseWithRetries(_ testCase: TestCase, testName: String) -> TestCaseResult {
        let (result, attempts) = progress.retrying(
            progressCase(testName, testCase.name),
            retries: config.caseRetries,
            isPass: { (r: TestCaseResult) in r.passed }
        ) { runTestCase(testCase) }
        return result.stamping(attempts: attempts)
    }

    /// Run a single test case (setup/teardown are handled by the caller)
    private func runTestCase(_ testCase: TestCase) -> TestCaseResult {
        let startTime = Date()
        var screenshots: [XCTAttachment] = []
        var warnings: [String] = []
        currentCaseName = testCase.name

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
                attachment.name = "Failure_\(currentTestName)_\(testCase.name)"
                attachment.lifetime = .keepAlways
                screenshots.append(attachment)
                attachArtifact(attachment)
            }
            let duration = Date().timeIntervalSince(startTime)
            return TestCaseResult(name: testCase.name, passed: false, duration: duration, error: error, screenshots: screenshots, warnings: warnings)
        }
    }

    // MARK: - Flow Test Execution

    /// Run a flow test
    public func run(flowTest: FlowTest) -> TestRunResult {
        let startTime = Date()
        progressFile = flowTest.sourceFile ?? "inline"
        progress.runStarted(files: 1)

        // Flow-level platform gate: emit one skipped row (never an empty
        // caseResults, which made the flow vanish from the report) — the
        // plan's "no silent truncation" rule.
        if let platform = flowTest.platform, !platform.includes(config.platform) {
            let result = TestRunResult(
                testName: flowTest.metadata.name,
                caseResults: [FlowRows.platformSkipped()],
                totalDuration: 0
            )
            progress.caseSkipped(progressCase(flowTest.metadata.name, FlowRows.caseName))
            writeResultsIfNeeded(result)
            progress.runEnded(rows: result.caseResults)
            return result
        }

        // Apply the file-level mock scenario set BEFORE the app (re)launches, so
        // the flow starts under the selected scenarios. Parity with runScreenTest
        // (§8.1); a failure here fails the flow rather than silently running the
        // default scenario.
        if let mocks = flowTest.mocks {
            do {
                try requireMockClient("mocks").scenarioSet(mocks)
            } catch {
                let result = TestRunResult(
                    testName: flowTest.metadata.name,
                    caseResults: [FlowRows.notStarted(error: error)],
                    totalDuration: Date().timeIntervalSince(startTime)
                )
                progress.caseFailedWithoutRunning(progressCase(flowTest.metadata.name, FlowRows.caseName))
                writeResultsIfNeeded(result)
                progress.runEnded(rows: result.caseResults)
                return result
            }
        }

        // The flow's one launch (spec §10.2): when it has a launch, mocks or
        // viewModels. Each screen in viewModels confirms its part the first
        // time the flow reaches it (verifyScreenTransitionIfNeeded).
        let plan = InitialStatePlan.plan(flowTest: flowTest) { [testLoader] file in
            try? testLoader?.resolveFileReference(file)
        }
        var pending: [String: String] = [:]
        if let entry = plan.launches.first {
            if let launchId = relaunch(flowTest.launch, screens: entry.screens) {
                for screenId in (entry.screens ?? [:]).keys { pending[screenId] = launchId }
            }
        }
        // A flow file starts from "unknown": nothing from the previous one.
        flowScreens.startFlow(pendingReceipts: pending)
        assertionExecutor.setStateScreen(flowScreens.stateScreen)

        var caseResults = runFlowSteps(flowTest)

        // Warnings the flow earns as a whole: referenced initialStates it did
        // not apply, and screens in viewModels it never reached.
        var flowWarnings = plan.warnings.map(InitialStatePlan.message)
        flowWarnings.append(contentsOf: flowScreens.unreachedWarnings)
        flowScreens.startFlow(pendingReceipts: [:])
        if !flowWarnings.isEmpty, let first = caseResults.first {
            caseResults[0] = first.adding(warnings: flowWarnings)
        }

        // Reset mock scenarios so a flow's setMocks state does not leak to the next test.
        try? mockClient?.reset()

        let totalDuration = Date().timeIntervalSince(startTime)

        let result = TestRunResult(
            testName: flowTest.metadata.name,
            caseResults: caseResults,
            totalDuration: totalDuration
        )
        writeResultsIfNeeded(result)
        progress.runEnded(rows: result.caseResults)
        return result
    }

    private func runFlowSteps(_ flowTest: FlowTest) -> [TestCaseResult] {
        let startTime = Date()
        var screenshots: [XCTAttachment] = []
        var warnings: [String] = []
        // A flow acts as a single case named "flow" for artifact identity
        // purposes — the same name its results row carries.
        currentTestName = flowTest.metadata.name
        currentCaseName = FlowRows.caseName
        var flowError: Error? = nil

        // The flow body (setup + steps) is the retry unit: flows begin with
        // their own launch/navigation steps, so a re-run starts clean.
        // Teardown still runs exactly once, after the final attempt.
        // Warnings/screenshots from a failed non-final attempt are dropped
        // (same rule as the `retry` step) — the last attempt's survive.
        let maxAttempts = max(0, config.caseRetries) + 1
        var flowAttempts = 0
        // The flow body is the flow's one case: a progress pair per attempt.
        let flowCase = progressCase(flowTest.metadata.name, FlowRows.caseName)
        repeat {
            flowAttempts += 1
            flowError = nil
            let attemptStart = Date()
            progress.caseStarted(flowCase, attempt: flowAttempts)
            // Each attempt starts from "unknown" (FlowScreenTracker).
            flowScreens.startAttempt()
            assertionExecutor.setStateScreen(flowScreens.stateScreen)
            var attemptScreenshots: [XCTAttachment] = []
            var attemptWarnings: [String] = []
            var currentStepIndex = 0

            do {
                // Execute setup
                if let setupSteps = flowTest.setup {
                    for step in setupSteps {
                        try executeFlowStep(step, warnings: &attemptWarnings)
                    }
                }

                // Execute flow steps
                for (index, step) in flowTest.steps.enumerated() {
                    currentStepIndex = index
                    try executeFlowStep(step, warnings: &attemptWarnings)

                    // Check for checkpoints
                    if let checkpoints = flowTest.checkpoints {
                        for checkpoint in checkpoints where checkpoint.afterStep == index {
                            if checkpoint.screenshot == true {
                                let screenshot = app.screenshot()
                                let attachment = XCTAttachment(screenshot: screenshot)
                                attachment.name = "Checkpoint_\(currentTestName)_\(checkpoint.name)"
                                attachment.lifetime = .keepAlways
                                attemptScreenshots.append(attachment)
                                attachArtifact(attachment)
                            }
                        }
                    }
                }
            } catch {
                flowError = error
                if config.screenshotOnFailure {
                    let screenshot = app.screenshot()
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = "Failure_\(currentTestName)_Step\(currentStepIndex)"
                    attachment.lifetime = .keepAlways
                    attemptScreenshots.append(attachment)
                    attachArtifact(attachment)
                }
            }

            progress.caseEnded(flowCase, attempt: flowAttempts, passed: flowError == nil,
                               duration: Date().timeIntervalSince(attemptStart))

            if flowError == nil || flowAttempts >= maxAttempts {
                warnings.append(contentsOf: attemptWarnings)
                screenshots.append(contentsOf: attemptScreenshots)
            }
        } while flowError != nil && flowAttempts < maxAttempts

        var results: [TestCaseResult] = [
            FlowRows.body(
                error: flowError,
                duration: Date().timeIntervalSince(startTime),
                screenshots: screenshots,
                warnings: warnings,
                attempts: flowAttempts
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
                progress.caseFailedWithoutRunning(progressCase(flowTest.metadata.name, "teardown"))
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

    /// The flow's screen, `state`'s screen and the receipts still owed
    /// (FlowScreenTracker).
    private var flowScreens = FlowScreenTracker()

    /// Implicit screen verification (canon: implicitVerification) and the
    /// receipt of a screen reached for the first time. Runs BEFORE the step,
    /// because the step is meant to run ON that screen.
    private func verifyScreenTransitionIfNeeded(_ step: FlowTestStep, warnings: inout [String]) throws {
        defer { assertionExecutor.setStateScreen(flowScreens.stateScreen) }
        try flowScreens.enterStep(
            screen: step.screen,
            verifyScreens: config.verifyScreenTransitions,
            verify: { screen in
                try self.assertionExecutor.execute(
                    step: TestStep(assert: "screen", timeout: Int(self.config.screenTransitionTimeout * 1000), name: screen),
                    in: self.app
                )
            },
            waitForReceipt: { screen, launchId in try self.waitForReceipt(screenId: screen, launchId: launchId) }
        )
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
            // A file reference carries no screen of its own, and the case it
            // runs may end anywhere — reset to unknown so the next inline
            // step is verified rather than trusted.
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
            // `state` reads the step's screen, else the last one named (spec §6).
            try verifyScreenTransitionIfNeeded(step, warnings: &warnings)
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
        // A referenced case reads its own file's screen (spec §6); afterwards
        // `state` goes back to the flow's last named screen.
        let fileScreen = step.file.flatMap { try? loader.resolveFileReference($0) }
            .map { ScreenIdentity.screenId(layoutPath: $0.source.layout) }
        flowScreens.enterFileReference(screenOfFile: fileScreen)
        assertionExecutor.setStateScreen(flowScreens.stateScreen)
        defer {
            flowScreens.leaveFileReference()
            assertionExecutor.setStateScreen(flowScreens.stateScreen)
        }

        for testCase in testCases {
            // Skip if marked to skip
            if testCase.skip == true {
                continue
            }

            // Check platform filter
            if let platform = testCase.platform, !platform.includes(config.platform) {
                continue
            }

            // Case-level responsive gate, evaluated against the live
            // device/window size — unmet means the referenced case is skipped
            // (parallel to the platform filter above)
            if let responsive = testCase.responsive, !ResponsiveRuntime.matches(responsive, app: app) {
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
            responsive: testCase.responsive,
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
            mocks: step.mocks,
            orientation: step.orientation
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

        // Media fixtures ship in the same bundle as the test JSON unless the
        // harness points elsewhere explicitly.
        var config = config
        if config.mediaBundle == nil {
            config.mediaBundle = bundle
        }
        let runner = JsonUITestRunner(app: app, config: config)

        switch loadedTest {
        case .screen(let screenTest):
            return runner.run(screenTest: screenTest)
        case .flow(let flowTest):
            return runner.run(flowTest: flowTest)
        }
    }
}
