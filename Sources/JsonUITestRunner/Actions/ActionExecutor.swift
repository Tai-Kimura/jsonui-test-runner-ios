import XCTest

/// Protocol for executing test actions
public protocol ActionExecutor {
    func execute(step: TestStep, in app: XCUIApplication) throws
    func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws
}

/// Errors that can occur during action execution
public enum ActionError: Error, LocalizedError {
    case elementNotFound(id: String)
    case unknownAction(action: String)
    case missingParameter(action: String, parameter: String)
    case timeout(id: String, timeout: Int)
    case timeoutAny(ids: [String], timeout: Int)
    case actionFailed(action: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .elementNotFound(let id):
            return "Element not found: '\(id)'"
        case .unknownAction(let action):
            return "Unknown action: '\(action)'"
        case .missingParameter(let action, let parameter):
            return "Missing parameter '\(parameter)' for action '\(action)'"
        case .timeout(let id, let timeout):
            return "Timeout waiting for element '\(id)' after \(timeout)ms"
        case .timeoutAny(let ids, let timeout):
            return "Timeout waiting for any of elements '\(ids.joined(separator: ", "))' after \(timeout)ms"
        case .actionFailed(let action, let reason):
            return "Action '\(action)' failed: \(reason)"
        }
    }
}

/// Default implementation of ActionExecutor using XCUITest
public class XCUITestActionExecutor: ActionExecutor {

    private let defaultTimeout: TimeInterval = 5.0

    public init() {}

    public func execute(step: TestStep, in app: XCUIApplication) throws {
        guard let action = step.action else {
            throw ActionError.unknownAction(action: "nil")
        }

        switch action {
        case "tap":
            try executeTap(step: step, in: app)
        case "doubleTap":
            try executeDoubleTap(step: step, in: app)
        case "longPress":
            try executeLongPress(step: step, in: app)
        case "input":
            try executeInput(step: step, in: app)
        case "clear":
            try executeClear(step: step, in: app)
        case "scroll":
            try executeScroll(step: step, in: app)
        case "swipe":
            try executeSwipe(step: step, in: app)
        case "waitFor":
            try executeWaitFor(step: step, in: app)
        case "waitForAny":
            try executeWaitForAny(step: step, in: app)
        case "wait":
            try executeWait(step: step)
        case "back":
            try executeBack(in: app)
        case "screenshot":
            try executeScreenshot(step: step, in: app)
        case "alertTap":
            try executeAlertTap(step: step, in: app)
        default:
            throw ActionError.unknownAction(action: action)
        }
    }

    public func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws {
        guard flowStep.action != nil else {
            throw ActionError.unknownAction(action: "nil")
        }

        // Convert FlowTestStep to TestStep for reuse
        let step = TestStep(
            action: flowStep.action,
            assert: flowStep.assert,
            id: flowStep.id,
            ids: flowStep.ids,
            text: flowStep.text,
            value: flowStep.value,
            direction: flowStep.direction,
            duration: flowStep.duration,
            timeout: flowStep.timeout,
            ms: flowStep.ms,
            name: flowStep.name,
            equals: flowStep.equals,
            contains: flowStep.contains,
            path: flowStep.path,
            amount: flowStep.amount,
            button: flowStep.button
        )

        try execute(step: step, in: app)
    }

    // MARK: - Action Implementations

    private func executeTap(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "tap", parameter: "id")
        }

        let element = try findElement(id: id, in: app)

        // If text is specified, tap on the specific text portion within the element
        if let targetText = step.text {
            try tapTextPortion(element: element, targetText: targetText, fullText: element.label)
        } else {
            element.tap()
        }
    }

    private func executeDoubleTap(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "doubleTap", parameter: "id")
        }

        let element = try findElement(id: id, in: app)
        element.doubleTap()
    }

    private func executeLongPress(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "longPress", parameter: "id")
        }

        let element = try findElement(id: id, in: app)
        let duration = TimeInterval(step.duration ?? 500) / 1000.0
        element.press(forDuration: duration)
    }

    private func executeInput(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "input", parameter: "id")
        }
        guard let value = step.value else {
            throw ActionError.missingParameter(action: "input", parameter: "value")
        }

        let element = try findElement(id: id, in: app)
        element.tap()
        element.typeText(value)
    }

    private func executeClear(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "clear", parameter: "id")
        }

        let element = try findElement(id: id, in: app)
        element.tap()

        // Select all and delete
        if let stringValue = element.value as? String, !stringValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            element.typeText(deleteString)
        }
    }

    private func executeScroll(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "scroll", parameter: "id")
        }
        guard let direction = step.direction else {
            throw ActionError.missingParameter(action: "scroll", parameter: "direction")
        }

        let element = try findElement(id: id, in: app)

        switch direction {
        case "up":
            element.swipeDown()
        case "down":
            element.swipeUp()
        case "left":
            element.swipeRight()
        case "right":
            element.swipeLeft()
        default:
            throw ActionError.actionFailed(action: "scroll", reason: "Invalid direction: \(direction)")
        }
    }

    private func executeSwipe(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "swipe", parameter: "id")
        }
        guard let direction = step.direction else {
            throw ActionError.missingParameter(action: "swipe", parameter: "direction")
        }

        let element = try findElement(id: id, in: app)

        switch direction {
        case "up":
            element.swipeUp()
        case "down":
            element.swipeDown()
        case "left":
            element.swipeLeft()
        case "right":
            element.swipeRight()
        default:
            throw ActionError.actionFailed(action: "swipe", reason: "Invalid direction: \(direction)")
        }
    }

    private func executeWaitFor(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "waitFor", parameter: "id")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0
        let element = findElementQuery(id: id, in: app)

        let exists = element.waitForExistence(timeout: timeout)
        if !exists {
            throw ActionError.timeout(id: id, timeout: step.timeout ?? 5000)
        }
    }

    private func executeWaitForAny(step: TestStep, in app: XCUIApplication) throws {
        guard let ids = step.ids, !ids.isEmpty else {
            throw ActionError.missingParameter(action: "waitForAny", parameter: "ids")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0
        let startTime = Date()

        // Poll until one element exists or timeout
        while Date().timeIntervalSince(startTime) < timeout {
            for id in ids {
                let element = findElementQuery(id: id, in: app)
                if element.exists {
                    return // Found one, success
                }
            }
            Thread.sleep(forTimeInterval: 0.1) // Poll every 100ms
        }

        throw ActionError.timeoutAny(ids: ids, timeout: step.timeout ?? 5000)
    }

    private func executeWait(step: TestStep) throws {
        guard let ms = step.ms else {
            throw ActionError.missingParameter(action: "wait", parameter: "ms")
        }

        Thread.sleep(forTimeInterval: TimeInterval(ms) / 1000.0)
    }

    private func executeBack(in app: XCUIApplication) throws {
        // Try navigation bar back button first
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
            return
        }

        // Fallback: swipe from left edge
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        let targetCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        coordinate.press(forDuration: 0.1, thenDragTo: targetCoordinate)
    }

    private func executeScreenshot(step: TestStep, in app: XCUIApplication) throws {
        guard let name = step.name else {
            throw ActionError.missingParameter(action: "screenshot", parameter: "name")
        }

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways

        // Note: XCTContext.runActivity is used to attach screenshots in actual tests
        XCTContext.runActivity(named: "Screenshot: \(name)") { activity in
            activity.add(attachment)
        }
    }

    private func executeAlertTap(step: TestStep, in app: XCUIApplication) throws {
        guard let buttonText = step.button else {
            throw ActionError.missingParameter(action: "alertTap", parameter: "button")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0

        // Wait for alert to appear
        let alert = app.alerts.firstMatch
        if !alert.waitForExistence(timeout: timeout) {
            throw ActionError.actionFailed(action: "alertTap", reason: "No alert appeared within \(Int(timeout * 1000))ms")
        }

        // Find and tap the button with matching text
        let button = alert.buttons[buttonText]
        if button.exists {
            button.tap()
            return
        }

        // Try scrollViews for action sheets
        let actionSheet = app.sheets.firstMatch
        if actionSheet.exists {
            let sheetButton = actionSheet.buttons[buttonText]
            if sheetButton.exists {
                sheetButton.tap()
                return
            }
        }

        throw ActionError.actionFailed(action: "alertTap", reason: "Button '\(buttonText)' not found in alert")
    }

    // MARK: - Helper Methods

    /// Fast element query using accessibilityIdentifier matching
    private func findElementQuery(id: String, in app: XCUIApplication) -> XCUIElement {
        // Use firstMatch for faster lookup - it returns immediately when found
        // instead of scanning the entire hierarchy
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func findElement(id: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = findElementQuery(id: id, in: app)

        // Wait briefly for element to appear
        if !element.waitForExistence(timeout: defaultTimeout) {
            throw ActionError.elementNotFound(id: id)
        }

        return element
    }

    /// Tap on a specific text portion within an element
    /// Calculates the approximate position of the target text and taps there
    private func tapTextPortion(element: XCUIElement, targetText: String, fullText: String) throws {
        guard let range = fullText.range(of: targetText) else {
            throw ActionError.actionFailed(action: "tap", reason: "Text '\(targetText)' not found in element label '\(fullText)'")
        }

        let frame = element.frame

        // Calculate the relative position of the target text within the full text
        let startIndex = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
        let endIndex = fullText.distance(from: fullText.startIndex, to: range.upperBound)
        let totalLength = fullText.count

        guard totalLength > 0 else {
            element.tap()
            return
        }

        // Calculate the center position of the target text (as a ratio of the element width)
        let startRatio = CGFloat(startIndex) / CGFloat(totalLength)
        let endRatio = CGFloat(endIndex) / CGFloat(totalLength)
        let centerRatio = (startRatio + endRatio) / 2.0

        // Calculate the tap coordinate
        let tapX = frame.minX + (frame.width * centerRatio)
        let tapY = frame.midY

        // Create coordinate and tap
        let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: centerRatio, dy: 0.5))
        coordinate.tap()
    }
}
