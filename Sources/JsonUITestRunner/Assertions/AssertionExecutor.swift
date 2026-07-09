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
}

/// Errors that can occur during assertion execution
public enum AssertionError: Error, LocalizedError {
    case elementNotFound(id: String)
    case unknownAssertion(assertion: String)
    case missingParameter(assertion: String, parameter: String)
    case assertionFailed(assertion: String, expected: String, actual: String)
    case stateNotAccessible(path: String)
    case screenshotUnavailable(reason: String)

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
        case .screenshotUnavailable(let reason):
            return "Screenshot assertion unavailable: \(reason)"
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
/// AssertionError with the last-observed value.
public class XCUITestAssertionExecutor: AssertionExecutor {

    /// Poll interval for auto-wait assertions
    private let pollInterval: TimeInterval = 0.1
    /// RGBA channel difference (0-255) below which two pixels count as a match
    private let channelTolerance: Int = 16

    private let defaultTimeout: TimeInterval
    private var stateProvider: ViewModelStateProvider?
    private let baselineDir: URL
    private let updateBaselines: Bool
    private var collectedWarnings: [String] = []

    public var warnings: [String] { collectedWarnings }

    public init(
        stateProvider: ViewModelStateProvider? = nil,
        defaultTimeout: TimeInterval = 5.0,
        baselineDir: URL? = nil,
        updateBaselines: Bool = false
    ) {
        self.stateProvider = stateProvider
        self.defaultTimeout = defaultTimeout
        self.baselineDir = baselineDir
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("jsonui-baselines", isDirectory: true)
        self.updateBaselines = updateBaselines
    }

    public func setStateProvider(_ provider: ViewModelStateProvider) {
        self.stateProvider = provider
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
        case "enabled":
            try assertEnabled(step: step, timeout: timeout, in: app)
        case "disabled":
            try assertDisabled(step: step, timeout: timeout, in: app)
        case "text":
            try assertText(step: step, timeout: timeout, in: app)
        case "count":
            try assertCount(step: step, timeout: timeout, in: app)
        case "state":
            try assertState(step: step, timeout: timeout)
        case "screenshot":
            try assertScreenshot(step: step, in: app)
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
        if let target = condition.platform, !target.includes(platform) {
            return false
        }
        if let visibleId = condition.visible, !isInstantlyVisible(id: visibleId, in: app) {
            return false
        }
        if let notVisibleId = condition.notVisible, isInstantlyVisible(id: notVisibleId, in: app) {
            return false
        }
        if let stateCondition = condition.state {
            guard let provider = stateProvider else {
                throw AssertionError.stateNotAccessible(path: stateCondition.path)
            }
            guard let actual = provider.getValue(at: stateCondition.path) else {
                return false
            }
            return valuesMatch(expected: stateCondition.equals, actual: actual)
        }
        return true
    }

    // MARK: - Assertion Implementations

    private func assertVisible(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "visible", parameter: "id")
        }
        // SwiftUI accessibility *containers* report isHittable == false because
        // hit-testing resolves to a child — fall back to a non-empty frame.
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: id, in: app)
            return element.exists && (element.isHittable || !element.frame.isEmpty)
        } onTimeout: {
            AssertionError.assertionFailed(assertion: "visible", expected: "visible", actual: "not visible for '\(id)'")
        }
    }

    private func assertNotVisible(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "notVisible", parameter: "id")
        }
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: id, in: app)
            return !(element.exists && element.isHittable)
        } onTimeout: {
            AssertionError.assertionFailed(assertion: "notVisible", expected: "not visible", actual: "still visible for '\(id)'")
        }
    }

    private func assertEnabled(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "enabled", parameter: "id")
        }
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: id, in: app)
            return element.exists && element.isEnabled
        } onTimeout: {
            AssertionError.assertionFailed(assertion: "enabled", expected: "enabled", actual: "disabled for '\(id)'")
        }
    }

    private func assertDisabled(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "disabled", parameter: "id")
        }
        try pollUntil(timeout: timeout) {
            let element = self.findElementQuery(id: id, in: app)
            return element.exists && !element.isEnabled
        } onTimeout: {
            AssertionError.assertionFailed(assertion: "disabled", expected: "disabled", actual: "enabled for '\(id)'")
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

        var actualText = currentText()
        try pollUntil(timeout: timeout) {
            actualText = currentText()
            return matches(actualText)
        } onTimeout: {
            let expected = step.equals?.stringValue.map { "equals '\($0)'" } ?? "contains '\(step.contains ?? "")'"
            return AssertionError.assertionFailed(assertion: "text", expected: expected, actual: "'\(actualText)' for '\(id)'")
        }
    }

    private func assertCount(step: TestStep, timeout: TimeInterval, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw AssertionError.missingParameter(assertion: "count", parameter: "id")
        }
        guard let expectedCount = step.equals?.intValue else {
            throw AssertionError.missingParameter(assertion: "count", parameter: "equals")
        }
        var actualCount = 0
        try pollUntil(timeout: timeout) {
            actualCount = app.descendants(matching: .any).matching(identifier: id).count
            return actualCount == expectedCount
        } onTimeout: {
            AssertionError.assertionFailed(assertion: "count", expected: "\(expectedCount)", actual: "\(actualCount) for '\(id)'")
        }
    }

    private func assertState(step: TestStep, timeout: TimeInterval) throws {
        guard let path = step.path else {
            throw AssertionError.missingParameter(assertion: "state", parameter: "path")
        }
        guard let expectedValue = step.equals else {
            throw AssertionError.missingParameter(assertion: "state", parameter: "equals")
        }
        guard let provider = stateProvider else {
            throw AssertionError.stateNotAccessible(path: path)
        }

        var actualDescription = "nil"
        try pollUntil(timeout: timeout) {
            guard let actual = provider.getValue(at: path) else {
                actualDescription = "nil"
                return false
            }
            actualDescription = String(describing: actual)
            return self.valuesMatch(expected: expectedValue, actual: actual)
        } onTimeout: {
            AssertionError.assertionFailed(
                assertion: "state",
                expected: String(describing: expectedValue.value),
                actual: "\(actualDescription) at '\(path)'"
            )
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

    /// Poll `check` every `pollInterval` until it returns true or the timeout elapses.
    private func pollUntil(
        timeout: TimeInterval,
        check: () -> Bool,
        onTimeout: () -> AssertionError
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if check() {
                return
            }
            if Date() >= deadline {
                break
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        // Final check to avoid off-by-one at the boundary
        if check() {
            return
        }
        throw onTimeout()
    }

    /// Instant visibility check (no waiting) used by conditions
    private func isInstantlyVisible(id: String, in app: XCUIApplication) -> Bool {
        let element = findElementQuery(id: id, in: app)
        return element.exists && (element.isHittable || !element.frame.isEmpty)
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
            mocks: mocks
        )
    }
}
