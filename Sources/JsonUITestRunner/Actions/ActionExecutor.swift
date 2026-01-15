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
        case "selectOption":
            try executeSelectOption(step: step, in: app)
        case "tapItem":
            try executeTapItem(step: step, in: app)
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
            button: flowStep.button,
            label: flowStep.label,
            index: flowStep.index
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

    private func executeSelectOption(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "selectOption", parameter: "id")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0

        // Step 1: Tap the SelectBox to open the picker sheet
        let selectBox = try findElement(id: id, in: app)
        selectBox.tap()

        // Step 2: Wait for the picker to appear
        let pickerView = app.descendants(matching: .any).matching(identifier: "sjui_x7q_picker").firstMatch
        let datePicker = app.descendants(matching: .any).matching(identifier: "sjui_x7q_datePicker").firstMatch

        let pickerAppeared = pickerView.waitForExistence(timeout: timeout)
        let datePickerAppeared = datePicker.waitForExistence(timeout: timeout)

        guard pickerAppeared || datePickerAppeared else {
            throw ActionError.actionFailed(action: "selectOption", reason: "Picker sheet did not appear within \(Int(timeout * 1000))ms")
        }

        // Step 3: Select the option
        if pickerAppeared && pickerView.isHittable {
            // Normal picker (UIPickerView)
            try selectPickerValue(pickerView: pickerView, step: step, in: app)
        } else if datePickerAppeared && datePicker.isHittable {
            // Date picker - select using ISO format value
            try selectDatePickerValue(datePicker: datePicker, step: step, in: app)
        }

        // Step 4: Tap Done button to confirm selection
        let doneButton = app.descendants(matching: .any).matching(identifier: "sjui_x7q_done").firstMatch
        if doneButton.waitForExistence(timeout: 2.0) {
            doneButton.tap()
        }
    }

    private func selectPickerValue(pickerView: XCUIElement, step: TestStep, in app: XCUIApplication) throws {
        // Get the picker wheels
        let pickerWheels = pickerView.pickerWheels

        if pickerWheels.count == 0 {
            throw ActionError.actionFailed(action: "selectOption", reason: "No picker wheels found in picker view")
        }

        // Select by label (text value)
        if let label = step.label {
            let wheel = pickerWheels.firstMatch
            wheel.adjust(toPickerWheelValue: label)
            return
        }

        // Select by value (same as label for UIPickerView)
        if let value = step.value {
            let wheel = pickerWheels.firstMatch
            wheel.adjust(toPickerWheelValue: value)
            return
        }

        // Select by index - parse items from accessibility value
        if let index = step.index {
            // SwiftJsonUI encodes items in accessibilityValue with "|||" separator
            guard let itemsString = pickerView.value as? String, !itemsString.isEmpty else {
                throw ActionError.actionFailed(action: "selectOption", reason: "Cannot get items from picker. Ensure SelectBox has items with accessibilityValue set.")
            }

            let items = itemsString.components(separatedBy: "|||")
            guard index >= 0 && index < items.count else {
                throw ActionError.actionFailed(action: "selectOption", reason: "Index \(index) out of range. Picker has \(items.count) items.")
            }

            let targetValue = items[index]
            let wheel = pickerWheels.firstMatch
            wheel.adjust(toPickerWheelValue: targetValue)
            return
        }

        throw ActionError.missingParameter(action: "selectOption", parameter: "label, value, or index")
    }

    private func selectDatePickerValue(datePicker: XCUIElement, step: TestStep, in app: XCUIApplication) throws {
        // Parse ISO format value: "2024-01-15", "14:30", or "2024-01-15T14:30"
        guard let value = step.value else {
            throw ActionError.missingParameter(action: "selectOption", parameter: "value (ISO format date/time)")
        }

        let pickerWheels = datePicker.pickerWheels

        if pickerWheels.count == 0 {
            throw ActionError.actionFailed(action: "selectOption", reason: "No picker wheels found in date picker")
        }

        // Detect format and parse accordingly
        if value.contains("T") {
            // DateTime format: "2024-01-15T14:30"
            let parts = value.split(separator: "T")
            if parts.count == 2 {
                try selectDateComponents(from: String(parts[0]), pickerWheels: pickerWheels)
                try selectTimeComponents(from: String(parts[1]), pickerWheels: pickerWheels)
            }
        } else if value.contains(":") {
            // Time format: "14:30"
            try selectTimeComponents(from: value, pickerWheels: pickerWheels)
        } else if value.contains("-") {
            // Date format: "2024-01-15"
            try selectDateComponents(from: value, pickerWheels: pickerWheels)
        } else {
            throw ActionError.actionFailed(action: "selectOption", reason: "Invalid date/time format: \(value). Use ISO format (e.g., '2024-01-15', '14:30', or '2024-01-15T14:30')")
        }
    }

    private func selectDateComponents(from dateString: String, pickerWheels: XCUIElementQuery) throws {
        // Parse "2024-01-15" format
        let components = dateString.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            throw ActionError.actionFailed(action: "selectOption", reason: "Invalid date format: \(dateString). Expected YYYY-MM-DD")
        }

        // iOS date picker wheel order varies by locale, but typically:
        // Japanese locale: Year, Month, Day (e.g., "2024年", "1月", "15日")
        // US locale: Month, Day, Year (e.g., "January", "15", "2024")
        // Try to find and adjust each component

        let allWheels = pickerWheels.allElementsBoundByIndex

        for wheel in allWheels {
            guard let currentValue = wheel.value as? String else { continue }

            // Try to match year wheel
            if currentValue.contains("年") || (Int(currentValue) ?? 0) > 1900 {
                // Japanese format: "2024年" or just "2024"
                let yearValue = currentValue.contains("年") ? "\(year)年" : "\(year)"
                wheel.adjust(toPickerWheelValue: yearValue)
            }
            // Try to match month wheel
            else if currentValue.contains("月") || isMonthName(currentValue) {
                // Japanese format: "1月" or English: "January"
                if currentValue.contains("月") {
                    wheel.adjust(toPickerWheelValue: "\(month)月")
                } else {
                    // English month names
                    let monthNames = ["January", "February", "March", "April", "May", "June",
                                     "July", "August", "September", "October", "November", "December"]
                    if month >= 1 && month <= 12 {
                        wheel.adjust(toPickerWheelValue: monthNames[month - 1])
                    }
                }
            }
            // Try to match day wheel
            else if currentValue.contains("日") || (Int(currentValue) ?? 0) >= 1 && (Int(currentValue) ?? 0) <= 31 {
                // Japanese format: "15日" or just "15"
                let dayValue = currentValue.contains("日") ? "\(day)日" : "\(day)"
                wheel.adjust(toPickerWheelValue: dayValue)
            }
        }
    }

    private func selectTimeComponents(from timeString: String, pickerWheels: XCUIElementQuery) throws {
        // Parse "14:30" format
        let components = timeString.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            throw ActionError.actionFailed(action: "selectOption", reason: "Invalid time format: \(timeString). Expected HH:mm")
        }

        let allWheels = pickerWheels.allElementsBoundByIndex

        for wheel in allWheels {
            guard let currentValue = wheel.value as? String else { continue }

            // Try to match hour wheel
            if currentValue.contains("時") || currentValue.contains("時") {
                wheel.adjust(toPickerWheelValue: "\(hour)時")
            }
            // Try to match minute wheel
            else if currentValue.contains("分") {
                wheel.adjust(toPickerWheelValue: "\(minute)分")
            }
            // Plain number format (e.g., "14", "30")
            else if let value = Int(currentValue.replacingOccurrences(of: " ", with: "")) {
                if value >= 0 && value <= 23 && !currentValue.contains("分") {
                    // Likely hour wheel
                    wheel.adjust(toPickerWheelValue: "\(hour)")
                } else if value >= 0 && value <= 59 {
                    // Likely minute wheel
                    wheel.adjust(toPickerWheelValue: "\(minute)")
                }
            }
        }
    }

    private func isMonthName(_ value: String) -> Bool {
        let monthNames = ["January", "February", "March", "April", "May", "June",
                         "July", "August", "September", "October", "November", "December",
                         "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return monthNames.contains { value.contains($0) }
    }

    private func executeTapItem(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "tapItem", parameter: "id")
        }
        guard let index = step.index else {
            throw ActionError.missingParameter(action: "tapItem", parameter: "index")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0

        // Find the item using the generated testTag pattern: {collectionId}_item_{index}
        let itemId = "\(id)_item_\(index)"
        let element = app.descendants(matching: .any).matching(identifier: itemId).firstMatch

        if !element.waitForExistence(timeout: timeout) {
            throw ActionError.elementNotFound(id: itemId)
        }

        element.tap()
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
