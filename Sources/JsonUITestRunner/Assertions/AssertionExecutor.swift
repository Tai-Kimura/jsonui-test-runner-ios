import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Protocol for executing test assertions
public protocol AssertionExecutor {
    func execute(step: TestStep, in app: XCUIApplication) throws
    func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws
    /// Evaluate a `when` / `while` condition against the current UI / state.
    func evaluate(condition: WhenCondition, platform: String, in app: XCUIApplication) throws -> Bool
    /// Warnings produced by the last executed step (e.g. baseline created); drained by the runner.
    var warnings: [String] { get }
    func drainWarnings() -> [String]
    /// The screen whose state bridge `state` reads when no provider was
    /// passed (spec §6): the runner sets it as screens change.
    func setStateScreen(_ screenId: String?)
}

/// Errors that can occur during assertion execution
public enum AssertionError: Error, LocalizedError {
    case elementNotFound(id: String)
    case unknownAssertion(assertion: String)
    case missingParameter(assertion: String, parameter: String)
    case assertionFailed(assertion: String, expected: String, actual: String)
    case stateNotAccessible(path: String)
    /// The iOS state bridge is over its 32KB limit: nothing in it can be read.
    case stateBridgeTruncated(screenId: String, bytes: Int)
    case screenshotUnavailable(reason: String)
    /// An auto-waiting assertion whose reason changed while it waited: the
    /// failure it ended on, followed by every reason with its span
    /// (ReasonHistory).
    indirect case timedOut(AssertionError, history: String)

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
            return "Cannot access ViewModel state at path: '\(path)' — no screen to read it from (a flow step names none yet) and no state provider was passed"
        case .stateBridgeTruncated(let screenId, let bytes):
            return "The state bridge of '\(screenId)' is \(bytes) bytes; the iOS bridge holds up to 32KB, so `state` cannot read this screen"
        case .screenshotUnavailable(let reason):
            return "Screenshot assertion unavailable: \(reason)"
        case .timedOut(let last, let history):
            return "\(last.errorDescription ?? "")\n\(history)"
        }
    }
}

/// Protocol for accessing ViewModel state from XCUITest
public protocol ViewModelStateProvider {
    func getValue(at path: String) -> Any?
}

/// Default implementation of AssertionExecutor using XCUITest.
///
/// All element assertions auto-wait: they poll the condition every 100ms until it
/// holds or the timeout (step.timeout ?? defaultTimeout) elapses, then throw
/// AssertionError with the last-observed reason — and, when the reason changed
/// while waiting, every reason with its span (ReasonHistory).
public class XCUITestAssertionExecutor: AssertionExecutor {

    /// Poll interval for auto-wait assertions
    private let pollInterval: TimeInterval = 0.1
    /// RGBA channel difference (0-255) below which two pixels count as a match
    private let channelTolerance: Int = 16

    private let defaultTimeout: TimeInterval
    /// Cross-screen waits are legitimately slower than in-screen ones: real
    /// suites already hand-write 15-20s after a cold start. Distinct from
    /// defaultTimeout so raising one does not silently raise the other.
    private let screenTransitionTimeout: TimeInterval
    private var stateProvider: ViewModelStateProvider?
    /// The screen `state` reads when no provider was passed (spec §6).
    private var stateScreen: String?
    private let baselineDir: URL
    private let updateBaselines: Bool
    private var collectedWarnings: [String] = []

    public var warnings: [String] { collectedWarnings }

    public init(
        stateProvider: ViewModelStateProvider? = nil,
        defaultTimeout: TimeInterval = 5.0,
        screenTransitionTimeout: TimeInterval = 10.0,
        baselineDir: URL? = nil,
        updateBaselines: Bool = false
    ) {
        self.stateProvider = stateProvider
        self.defaultTimeout = defaultTimeout
        self.screenTransitionTimeout = screenTransitionTimeout
        self.baselineDir = baselineDir
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("jsonui-baselines", isDirectory: true)
        self.updateBaselines = updateBaselines
    }

    public func setStateProvider(_ provider: ViewModelStateProvider) {
        self.stateProvider = provider
    }

    public func setStateScreen(_ screenId: String?) {
        self.stateScreen = screenId
    }

    /// One read of `path` through the default provider: the state bridge of
    /// `stateScreen` (spec §10.5).
    private func bridgeOutcome(path: String, in app: XCUIApplication) throws -> StateBridge.Outcome {
        guard let screenId = stateScreen else { throw AssertionError.stateNotAccessible(path: path) }
        return StateBridge.outcome(StateBridge.read(screenId, in: app), path: path)
    }

    public func drainWarnings() -> [String] {
        let drained = collectedWarnings
        collectedWarnings = []
        return drained
    }

    public func execute(step: TestStep, in app: XCUIApplication) throws {
        guard let assertion = step.assert else {
            throw AssertionError.unknownAssertion(assertion: "nil")
        }

        let timeout = step.timeoutInterval(default: defaultTimeout)

        switch assertion {
        case "visible":
            try assertVisible(step: step, timeout: timeout, in: app)
        case "notVisible":
            try assertNotVisible(step: step, timeout: timeout, in: app)
        case "hidden":
            try assertHidden(step: step, timeout: timeout, in: app)
        case "enabled":
            try assertEnabled(step: step, timeout: timeout, in: app)
        case "disabled":
            try assertDisabled(step: step, timeout: timeout, in: app)
        case "text":
            try assertText(step: step, timeout: timeout, in: app)
        case "count":
            try assertCount(step: step, timeout: timeout, in: app)
        case "state":
            try assertState(step: step, timeout: timeout, in: app)
        case "screenshot":
            try assertScreenshot(step: step, in: app)
        case "screen":
            try assertScreen(step: step, timeout: step.timeoutInterval(default: screenTransitionTimeout), in: app)
        default:
            throw AssertionError.unknownAssertion(assertion: assertion)
        }
    }

    public func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws {
        guard flowStep.assert != nil else {
            throw AssertionError.unknownAssertion(assertion: "nil")
        }
        try execute(step: flowStep.toTestStep(), in: app)
    }

    // MARK: - Condition evaluation (for `when` / `while`)

    public func evaluate(condition: WhenCondition, platform: String, in app: XCUIApplication) throws -> Bool {
        // Fail-safe skip: a condition carrying keys this driver cannot evaluate
        // (written against a newer schema than this driver) is UNMET — the
        // gated step is skipped, never run-anyway on the keys we do know,
        // never a hard error.
        if !condition.unknownKeys.isEmpty {
            print("Warning: condition contains unevaluable key(s) \(condition.unknownKeys) on the iOS driver; treating as unmet (step skipped)")
            return false
        }
        if let target = condition.platform, !target.includes(platform) {
            return false
        }
        // Size gate resolved against the live device/window size. Named
        // buckets mirror the sjui renderer's size-class rules; constraint
        // objects compare the window frame in pt (see ResponsiveEvaluator).
        if let responsive = condition.responsive, !ResponsiveRuntime.matches(responsive, app: app) {
            return false
        }
        if let visibleId = condition.visible, !isInstantlyVisible(id: visibleId, in: app) {
            return false
        }
        if let notVisibleId = condition.notVisible, isInstantlyVisible(id: notVisibleId, in: app) {
            return false
        }
        if let hiddenId = condition.hidden, !isHidden(id: hiddenId, in: app) {
            return false
        }
        if let stateCondition = condition.state {
            if let provider = stateProvider {
                guard let actual = provider.getValue(at: stateCondition.path) else {
                    return false
                }
                return valuesMatch(expected: stateCondition.equals, actual: actual)
            }
            switch try bridgeOutcome(path: stateCondition.path, in: app) {
            case .value(let actual):
                return valuesMatch(expected: stateCondition.equals, actual: actual)
            case .pending, .unresolved:
                return false
            case .truncated(let bytes):
                throw AssertionError.stateBridgeTruncated(screenId: stateScreen ?? "", bytes: bytes)
            }
        }
        return true
    }

    // MARK: - Assertion Implementations

    /// `assert: "screen"` — the named screen IS DISPLAYED.
    ///
    /// Not "displayed exclusively": embedded screens, split panes and tab
    /// hosts legitimately show several markers at once, so this only ever
    /// looks at the target's own marker.
    ///
    /// The predicate is `exists && isHittable`, measured on iOS 18.6 across
    /// push / sheet / fullScreenCover / tab switch / split pane: a pushed-away
    /// screen and an inactive tab leave the hierarchy entirely, while a screen
    /// covered by a sheet stays but reports isHittable == false. This works
    /// only because the marker is a LEAF — the same reason `visible` has to
    /// fall back to a non-empty frame for containers does not apply here.
    private func assertScreen(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let screenId = step.name else {
            throw AssertionError.missingParameter(assertion: "screen", parameter: "name")
        }
        let marker = ScreenMarker.identifier(for: screenId)
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: marker, in: app)
            // The diagnosis is taken once, at timeout (ScreenMarker.diagnosis);
            // a look only says "not yet", so the history is one segment.
            guard element.exists else { return "not displayed" }
            // Covered — but by WHAT? isHittable alone cannot tell a sheet
            // from the app's own overlay, and the difference is the whole
            // question. The marker sits inside the generated view, so any
            // overlay the app layers outside it (coach mark, loading scrim,
            // hand-rolled modal) always covers the marker while the screen
            // is plainly still the one on display. A sheet or cover, by
            // contrast, is another SCREEN and brings its own marker.
            //
            // So: still displayed unless something else claims to be.
            //
            // ⚠️ The two questions are asked in THIS order, and the order is
            // the fix. Written as `if element.isHittable { return true }`
            // first, the fallback below was unreachable whenever XCUITest
            // could not COMPUTE hittability: "Activation point invalid and no
            // suggested hit points based on element frame" is recorded as a
            // test failure rather than returned as `false`, so the most
            // thoroughly covered case — the one this fallback exists for —
            // failed on its way to the rescue. Reported from a consumer face,
            // reproducing on a tablet lane in two consecutive runs 0.3s apart
            // while the same 75 cases passed on phone.
            //
            // `screenIsDisplayed` is outcome-identical to the old order (see
            // its truth table and the arms that pin it), so this changes no
            // verdict — it only stops asking a question whose failure to
            // answer was being treated as a No.
            return ScreenMarker.screenIsDisplayed(
                noOtherScreenIsHittable:
                    ScreenMarker.hittableScreens(in: app, excluding: screenId).isEmpty,
                markerIsHittable: element.isHittable
            ) ? nil : "not displayed"
        } onTimeout: { _ in
            AssertionError.assertionFailed(
                assertion: "screen",
                expected: "screen '\(screenId)' displayed",
                actual: ScreenMarker.diagnosis(screenId: screenId, in: app)
            )
        }
    }

    private func assertVisible(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "visible", parameter: "id")
        }
        // In the viewport: some of the element (at least 1pt each way) inside
        // the app's frame and every scroll container above it
        // (VisibleFrame.inViewport, ViewportVisibility). Not isHittable:
        // SwiftUI accessibility *containers* report it false because
        // hit-testing resolves to a child.
        try pollUntil(timeout: timeout) {
            ViewportVisibility.notVisibleReason(id: id, in: app)
        } onTimeout: { reason in
            AssertionError.assertionFailed(assertion: "visible", expected: "visible", actual: "\(reason) for '\(id)'")
        }
    }

    private func assertNotVisible(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "notVisible", parameter: "id")
        }
        // The negation of `visible`, as on Android (findObject(By.res) is
        // null). Not isHittable: an element under an opaque view in the same
        // window, or at opacity 0, is not hittable but Android calls it
        // visible — and so did `visible` here, so both asserts passed on it.
        // An element under a sheet, fullScreenCover, alert or
        // confirmationDialog is not visible by the predicate itself
        // (ViewportVisibility), not by hit-testing.
        try pollUntil(timeout: timeout) {
            ViewportVisibility.isVisible(id: id, in: app) ? "still visible" : nil
        } onTimeout: { reason in
            AssertionError.assertionFailed(assertion: "notVisible", expected: "not visible", actual: "\(reason) for '\(id)'")
        }
    }

    /// `hidden`: not drawn, wherever it is — no element has the id. An element
    /// scrolled off screen, under a sheet, at opacity 0 or disabled is in
    /// XCUITest's tree (exists), so `hidden` fails on it; `notVisible` is the
    /// viewport's question, this is not. SwiftJsonUI takes a "gone" view out
    /// of the tree and, from 10.29.16, an "invisible" / `hidden: true` one
    /// too (accessibilityRepresentation); before 10.29.16 a bound invisible /
    /// hidden view and a static `hidden: true` one stayed in it and read as
    /// shown. Measured 2026-10-15 (iOS 26.2, SwiftJsonUI 10.29.16): the same
    /// answer as Android's semantics tree and web's checkVisibility on every
    /// shape — plain, opacity 0, disabled, 3000pt below, under a sheet shown;
    /// invisible, gone, hidden, their bindings, a child of either parent,
    /// absent hidden.
    private func assertHidden(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "hidden", parameter: "id")
        }
        try pollUntil(timeout: timeout) {
            self.isHidden(id: id, in: app) ? nil : "shown"
        } onTimeout: { reason in
            AssertionError.assertionFailed(assertion: "hidden", expected: "hidden", actual: "\(reason) for '\(id)'")
        }
    }

    /// The `hidden` predicate, once (also `when: { hidden }`).
    private func isHidden(id: String, in app: XCUIApplication) -> Bool {
        !findElementQuery(id: id, in: app).exists
    }

    private func assertEnabled(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "enabled", parameter: "id")
        }
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: id, in: app)
            guard element.exists else { return "does not exist" }
            return element.isEnabled ? nil : "disabled"
        } onTimeout: { reason in
            AssertionError.assertionFailed(assertion: "enabled", expected: "enabled", actual: "\(reason) for '\(id)'")
        }
    }

    private func assertDisabled(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "disabled", parameter: "id")
        }
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: id, in: app)
            guard element.exists else { return "does not exist" }
            return element.isEnabled ? "enabled" : nil
        } onTimeout: { reason in
            AssertionError.assertionFailed(assertion: "disabled", expected: "disabled", actual: "\(reason) for '\(id)'")
        }
    }

    private func assertText(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "text", parameter: "id")
        }
        guard step.equals?.stringValue != nil || step.contains != nil else {
            throw AssertionError.missingParameter(assertion: "text", parameter: "equals or contains")
        }

        // Read text from element (value first, then label). SwiftUI StaticText
        // reports an EMPTY string value while the actual text lives in the label.
        func currentText() -> String {
            let element = self.findElementQuery(id: id, in: app)
            if let valueText = element.value as? String, !valueText.isEmpty {
                return valueText
            }
            return element.label
        }
        func matches(_ actual: String) -> Bool {
            if let expectedEquals = step.equals?.stringValue {
                return actual == expectedEquals
            }
            if let expectedContains = step.contains {
                return actual.contains(expectedContains)
            }
            return false
        }

        try pollUntil(timeout: timeout) {
            let actualText = currentText()
            return matches(actualText) ? nil : "'\(actualText)'"
        } onTimeout: { reason in
            let expected = step.equals?.stringValue.map { "equals '\($0)'" } ?? "contains '\(step.contains ?? "")'"
            return AssertionError.assertionFailed(assertion: "text", expected: expected, actual: "\(reason) for '\(id)'")
        }
    }

    private func assertCount(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "count", parameter: "id")
        }
        guard let expectedCount = step.equals?.intValue else {
            throw AssertionError.missingParameter(assertion: "count", parameter: "equals")
        }
        try pollUntil(timeout: timeout) {
            let actualCount = app.descendants(matching: .any).matching(identifier: id).count
            return actualCount == expectedCount ? nil : "\(actualCount)"
        } onTimeout: { reason in
            AssertionError.assertionFailed(assertion: "count", expected: "\(expectedCount)", actual: "\(reason) for '\(id)'")
        }
    }

    private func assertState(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let path = step.path else {
            throw AssertionError.missingParameter(assertion: "state", parameter: "path")
        }
        guard let expectedValue = step.equals else {
            throw AssertionError.missingParameter(assertion: "state", parameter: "equals")
        }

        // A provider the harness passed wins; otherwise the state bridge of the
        // screen the runner names (spec §6, §10.5).
        if let provider = stateProvider {
            try pollUntil(timeout: timeout) {
                guard let actual = provider.getValue(at: path) else { return "nil" }
                return self.valuesMatch(expected: expectedValue, actual: actual) ? nil : String(describing: actual)
            } onTimeout: { reason in
                AssertionError.assertionFailed(
                    assertion: "state",
                    expected: String(describing: expectedValue.value),
                    actual: "\(reason) at '\(path)'"
                )
            }
            return
        }

        guard let screenId = stateScreen else { throw AssertionError.stateNotAccessible(path: path) }
        // A truncated bridge ends the wait at once; pollUntil's check cannot
        // throw, so it stops the poll and the throw happens here.
        var truncated: Int?
        try pollUntil(timeout: timeout) {
            switch StateBridge.outcome(StateBridge.read(screenId, in: app), path: path) {
            case .pending:
                return "no state bridge for '\(screenId)' (the screen is not showing, or its library predates the bridge: SwiftJsonUI 10.30.0)"
            case .truncated(let bytes):
                truncated = bytes
                return nil
            case .unresolved:
                return "path not resolved in the data of '\(screenId)'"
            case .value(let actual):
                return self.valuesMatch(expected: expectedValue, actual: actual) ? nil : String(describing: actual)
            }
        } onTimeout: { reason in
            AssertionError.assertionFailed(
                assertion: "state",
                expected: String(describing: expectedValue.value),
                actual: "\(reason) at '\(path)'"
            )
        }
        if let truncated {
            throw AssertionError.stateBridgeTruncated(screenId: screenId, bytes: truncated)
        }
    }

    private func assertScreenshot(step: TestStep, in app: XCUIApplication) throws {
        #if canImport(UIKit)
        guard let name = step.name else {
            throw AssertionError.missingParameter(assertion: "screenshot", parameter: "name")
        }
        let threshold = step.threshold ?? 98.0

        // Capture (optionally cropped to an element's frame)
        let fullImage = XCUIScreen.main.screenshot().image
        let capture: UIImage
        if let cropId = step.cropId {
            let element = findElementQuery(id: cropId, in: app)
            guard element.exists else {
                throw AssertionError.elementNotFound(id: cropId)
            }
            capture = cropImage(fullImage, toFrame: element.frame) ?? fullImage
        } else {
            capture = fullImage
        }

        guard let captureData = capture.pngData() else {
            throw AssertionError.screenshotUnavailable(reason: "could not encode capture to PNG")
        }

        let platformDir = baselineDir.appendingPathComponent("ios", isDirectory: true)
        let baselinePath = platformDir.appendingPathComponent("\(name).png")

        if updateBaselines || !FileManager.default.fileExists(atPath: baselinePath.path) {
            try FileManager.default.createDirectory(at: platformDir, withIntermediateDirectories: true)
            try captureData.write(to: baselinePath)
            collectedWarnings.append(
                updateBaselines
                    ? "baseline updated: \(baselinePath.path)"
                    : "baseline created: \(baselinePath.path)"
            )
            return
        }

        guard let baselineImage = UIImage(contentsOfFile: baselinePath.path) else {
            throw AssertionError.screenshotUnavailable(reason: "could not read baseline \(baselinePath.path)")
        }

        let similarity = try compareSimilarity(baseline: baselineImage, current: capture, name: name)
        if similarity < threshold {
            throw AssertionError.assertionFailed(
                assertion: "screenshot",
                expected: "similarity >= \(threshold)%",
                actual: String(format: "%.2f%% for '%@'", similarity, name)
            )
        }
        #else
        throw AssertionError.screenshotUnavailable(reason: "UIKit not available")
        #endif
    }

    // MARK: - Helper Methods

    /// Poll `check` every `pollInterval` until it returns nil (pass) or the
    /// timeout elapses. While the condition is unmet `check` returns the
    /// reason, the text that goes into Actual. At timeout `onTimeout` builds
    /// the failure from the last reason; when the reason changed while
    /// waiting, the failure carries every reason with its span.
    private func pollUntil(
        timeout: TimeInterval,
        check: () -> String?,
        onTimeout: (String) -> AssertionError
    ) throws {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        var history = ReasonHistory()
        var last = ""
        func look() -> Bool {
            let lookedAt = Date().timeIntervalSince(start)
            guard let reason = check() else { return true }
            last = reason
            history.observe(reason, at: lookedAt)
            return false
        }
        repeat {
            if look() {
                return
            }
            if Date() >= deadline {
                break
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        // Final check to avoid off-by-one at the boundary
        if look() {
            return
        }
        let failure = onTimeout(last)
        guard let block = history.block(end: Date().timeIntervalSince(start)) else { throw failure }
        throw AssertionError.timedOut(failure, history: block)
    }

    /// Instant visibility check (no waiting) used by conditions
    /// `when: { visible / notVisible }` — the same predicate as the asserts.
    private func isInstantlyVisible(id: String, in app: XCUIApplication) -> Bool {
        ViewportVisibility.isVisible(id: id, in: app)
    }

    private func valuesMatch(expected: AnyCodable, actual: Any) -> Bool {
        if let expectedBool = expected.boolValue, let actualBool = actual as? Bool {
            return expectedBool == actualBool
        }
        if let expectedInt = expected.intValue, let actualInt = actual as? Int {
            return expectedInt == actualInt
        }
        if let expectedString = expected.stringValue, let actualString = actual as? String {
            return expectedString == actualString
        }
        if let expectedDouble = expected.doubleValue, let actualDouble = actual as? Double {
            return abs(expectedDouble - actualDouble) < 0.0001
        }
        return String(describing: actual) == String(describing: expected.value)
    }

    /// Fast element query using accessibilityIdentifier matching
    private func findElementQuery(id: String, in app: XCUIApplication) -> XCUIElement {
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    #if canImport(UIKit)
    private func cropImage(_ image: UIImage, toFrame frame: CGRect) -> UIImage? {
        let scale = image.scale
        let scaledRect = CGRect(
            x: frame.origin.x * scale,
            y: frame.origin.y * scale,
            width: frame.size.width * scale,
            height: frame.size.height * scale
        )
        guard let cgImage = image.cgImage?.cropping(to: scaledRect) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }

    /// Return the similarity percentage (0-100) between two images. Throws on size mismatch.
    private func compareSimilarity(baseline: UIImage, current: UIImage, name: String) throws -> Double {
        guard let a = baseline.cgImage, let b = current.cgImage else {
            throw AssertionError.screenshotUnavailable(reason: "missing CGImage for '\(name)'")
        }
        if a.width != b.width || a.height != b.height {
            throw AssertionError.assertionFailed(
                assertion: "screenshot",
                expected: "\(a.width)x\(a.height)",
                actual: "\(b.width)x\(b.height) for '\(name)'"
            )
        }
        let width = a.width
        let height = a.height
        guard let pixelsA = rgbaBytes(a), let pixelsB = rgbaBytes(b) else {
            throw AssertionError.screenshotUnavailable(reason: "could not read pixels for '\(name)'")
        }
        let total = width * height
        if total == 0 { return 100.0 }
        var matching = 0
        var i = 0
        while i < pixelsA.count {
            let dr = abs(Int(pixelsA[i]) - Int(pixelsB[i]))
            let dg = abs(Int(pixelsA[i + 1]) - Int(pixelsB[i + 1]))
            let db = abs(Int(pixelsA[i + 2]) - Int(pixelsB[i + 2]))
            let da = abs(Int(pixelsA[i + 3]) - Int(pixelsB[i + 3]))
            if dr <= channelTolerance && dg <= channelTolerance && db <= channelTolerance && da <= channelTolerance {
                matching += 1
            }
            i += 4
        }
        return 100.0 * Double(matching) / Double(total)
    }

    private func rgbaBytes(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
    #endif
}

// MARK: - FlowTestStep -> TestStep conversion

extension FlowTestStep {
    /// Convert an inline / block-child flow step into a TestStep for execution.
    func toTestStep() -> TestStep {
        return TestStep(
            action: action,
            assert: assert,
            id: id,
            ids: ids,
            text: text,
            value: value,
            direction: direction,
            duration: duration,
            timeout: timeout,
            ms: ms,
            name: name,
            equals: equals,
            contains: contains,
            path: path,
            amount: amount,
            button: button,
            label: label,
            index: index,
            optional: optional,
            when: when,
            retryTapIfNoChange: retryTapIfNoChange,
            container: container,
            variable: variable,
            times: times,
            while: `while`,
            steps: steps?.map { $0.toTestStep() },
            maxRetries: maxRetries,
            latitude: latitude,
            longitude: longitude,
            paths: paths,
            cropId: cropId,
            threshold: threshold,
            mocks: mocks,
            orientation: orientation
        )
    }
}
