import XCTest
#if canImport(CoreLocation)
import CoreLocation
#endif

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
    private let platform: String
    /// Runtime variable store written by readText and read by the runner for @{name} substitution
    private let variables: VariableStore

    public init(platform: String = "ios", variables: VariableStore = VariableStore()) {
        self.platform = platform
        self.variables = variables
    }

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
        case "typeText":
            try executeTypeText(step: step, in: app)
        case "clear":
            try executeClear(step: step, in: app)
        case "scroll":
            try executeScroll(step: step, in: app)
        case "scrollUntilVisible":
            try executeScrollUntilVisible(step: step, in: app)
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
        case "selectTab":
            try executeSelectTab(step: step, in: app)
        case "readText":
            try executeReadText(step: step, in: app)
        case "setLocation":
            try executeSetLocation(step: step)
        case "setViewport":
            // Permanently web-only: the viewport is not drivable on iOS (a
            // running app cannot be freely resized), so this is a documented
            // no-op instead of an unknown-action throw. Asserts that depend on
            // the swept size must self-gate with a matching `when.responsive`
            // so they skip cleanly instead of running at the device's fixed size.
            print("Warning: 'setViewport' is a no-op on the iOS driver (device size is fixed); gate dependent asserts with when.responsive")
        case "setOrientation":
            try executeSetOrientation(step: step)
        case "addMedia":
            throw ActionError.actionFailed(action: "addMedia", reason: "addMedia is not supported on the iOS driver")
        case "repeat", "retry":
            throw ActionError.actionFailed(action: action, reason: "'\(action)' is a control step handled by the test runner")
        default:
            throw ActionError.unknownAction(action: action)
        }
    }

    public func execute(flowStep: FlowTestStep, in app: XCUIApplication) throws {
        guard flowStep.action != nil else {
            throw ActionError.unknownAction(action: "nil")
        }
        try execute(step: flowStep.toTestStep(), in: app)
    }

    // MARK: - Action Implementations

    private func executeTap(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "tap", parameter: "id")
        }

        let element = try findTappableElement(id: id, in: app)

        // If text is specified, tap on the specific text portion within the element
        if let targetText = step.text {
            try tapTextPortion(element: element, targetText: targetText, fullText: element.label)
            return
        }

        if step.retryTapIfNoChange == true {
            // Ghost-tap mitigation: re-tap once if the hierarchy did not change
            let before = app.debugDescription
            element.tap()
            Thread.sleep(forTimeInterval: 0.5)
            if app.debugDescription == before {
                element.tap()
            }
        } else {
            element.tap()
        }
    }

    private func executeDoubleTap(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "doubleTap", parameter: "id")
        }

        let element = try findTappableElement(id: id, in: app)
        element.doubleTap()
    }

    private func executeLongPress(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "longPress", parameter: "id")
        }

        let element = try findTappableElement(id: id, in: app)
        // Default 800ms, not 500ms: the iOS long-press recognizer minimum
        // (SwiftUI LongPressGesture / UILongPressGestureRecognizer) is 0.5s,
        // so a press of exactly 500ms races the recognizer and fires only
        // sometimes. The press must comfortably exceed the threshold.
        let duration = TimeInterval(step.duration ?? 800) / 1000.0
        element.press(forDuration: duration)
    }

    private func executeInput(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "input", parameter: "id")
        }
        guard let value = step.value else {
            throw ActionError.missingParameter(action: "input", parameter: "value")
        }

        let element = try findTypableElement(id: id, in: app)
        element.tap()

        // `input` SETS the field value (parity with the web driver's
        // Playwright fill() and Android's setText): clear existing text first.
        // CRITICAL: element.value returns the PLACEHOLDER for an empty field,
        // so guard the clear against placeholderValue — otherwise an empty
        // field (value == placeholder) wrongly enters the clear branch, whose
        // bottom-right coordinate tap drops keyboard focus and makes the
        // following typeText fail with "no keyboard focus".
        if let existing = element.value as? String,
           !existing.isEmpty,
           existing != element.placeholderValue {
            // Caret position after tap() is unspecified (TextEditor tends to
            // put it at the start): tap the bottom-right of the element to
            // move the caret to the end, then backspace through everything.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            element.typeText(deleteString)
        }
        element.typeText(value)
    }

    /// Type into whatever currently holds keyboard focus — no element id.
    /// For fields that are focused but not directly targetable (e.g. an
    /// invisible code-entry TextField behind visible slots): focus is
    /// established app-side (auto-focus or a prior tap on a visible container),
    /// then this sends the characters via the keyboard. Requires the keyboard
    /// to be up; XCUIApplication.typeText throws "no keyboard focus" otherwise.
    private func executeTypeText(step: TestStep, in app: XCUIApplication) throws {
        guard let value = step.value else {
            throw ActionError.missingParameter(action: "typeText", parameter: "value")
        }
        app.typeText(value)
    }

    private func executeClear(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "clear", parameter: "id")
        }

        let element = try findTypableElement(id: id, in: app)
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

    private func executeScrollUntilVisible(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "scrollUntilVisible", parameter: "id")
        }
        let direction = step.direction ?? "down"
        let timeout = step.timeoutInterval(default: 20.0)

        func targetVisible() -> Bool {
            let element = findElementQuery(id: id, in: app)
            return element.exists && (element.isHittable || !element.frame.isEmpty)
        }

        if targetVisible() {
            return
        }

        // Resolve the scrollable container: explicit id, else the first scroll view,
        // else the whole app as a swipe surface.
        let scroller: XCUIElement
        if let containerId = step.container {
            scroller = findElementQuery(id: containerId, in: app)
        } else if app.scrollViews.firstMatch.exists {
            scroller = app.scrollViews.firstMatch
        } else {
            scroller = app
        }

        let deadline = Date().addingTimeInterval(timeout)
        var previousSnapshot = ""
        var unchangedCount = 0

        while Date() < deadline {
            switch direction {
            case "up": scroller.swipeDown()
            case "down": scroller.swipeUp()
            case "left": scroller.swipeRight()
            case "right": scroller.swipeLeft()
            default:
                throw ActionError.actionFailed(action: "scrollUntilVisible", reason: "Invalid direction: \(direction)")
            }

            if targetVisible() {
                return
            }

            // End-reached detection: two consecutive scrolls with no hierarchy change
            let snapshot = app.debugDescription
            if snapshot == previousSnapshot {
                unchangedCount += 1
                if unchangedCount >= 1 {
                    throw ActionError.actionFailed(
                        action: "scrollUntilVisible",
                        reason: "Element '\(id)' not found after scrolling to the end"
                    )
                }
            } else {
                unchangedCount = 0
            }
            previousSnapshot = snapshot
        }

        throw ActionError.timeout(id: id, timeout: Int(timeout * 1000))
    }

    private func executeReadText(step: TestStep, in app: XCUIApplication) throws {
        guard let id = step.id else {
            throw ActionError.missingParameter(action: "readText", parameter: "id")
        }
        guard let variable = step.variable else {
            throw ActionError.missingParameter(action: "readText", parameter: "variable")
        }
        let element = try findElement(id: id, in: app)
        let text: String
        if let valueText = element.value as? String, !valueText.isEmpty {
            text = valueText
        } else {
            text = element.label
        }
        variables.set(variable, to: text)
    }

    private func executeSetLocation(step: TestStep) throws {
        guard let latitude = step.latitude, let longitude = step.longitude else {
            throw ActionError.missingParameter(action: "setLocation", parameter: "latitude/longitude")
        }
        #if canImport(CoreLocation)
        if #available(iOS 16.4, *) {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            XCUIDevice.shared.location = XCUILocation(location: location)
        } else {
            throw ActionError.actionFailed(action: "setLocation", reason: "setLocation requires iOS 16.4 or newer")
        }
        #else
        throw ActionError.actionFailed(action: "setLocation", reason: "CoreLocation is not available")
        #endif
    }

    /// Rotate the device via XCUIDevice. "landscape" maps to landscapeLeft
    /// (home button / indicator on the right) — one deterministic pick, since
    /// the test vocabulary does not distinguish left from right.
    private func executeSetOrientation(step: TestStep) throws {
        guard let orientation = step.orientation else {
            throw ActionError.missingParameter(action: "setOrientation", parameter: "orientation")
        }
        switch orientation {
        case "portrait":
            XCUIDevice.shared.orientation = .portrait
        case "landscape":
            XCUIDevice.shared.orientation = .landscapeLeft
        default:
            throw ActionError.actionFailed(
                action: "setOrientation",
                reason: "Invalid orientation: \(orientation) (expected portrait|landscape)"
            )
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

        // Save the screenshot PNG to a screenshots directory under the temp dir.
        // (Failure/checkpoint screenshots are attached as XCTAttachment by the runner;
        // this explicit action persists a named capture that survives outside a test.)
        let screenshot = app.screenshot()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jsonui-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
    }

    private func executeAlertTap(step: TestStep, in app: XCUIApplication) throws {
        guard let buttonText = step.button else {
            throw ActionError.missingParameter(action: "alertTap", parameter: "button")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0

        // SpringBoard owns system prompts (Save Password?, permission dialogs).
        // They cover the app but never appear in the app's element tree, so
        // sweep both processes. addUIInterruptionMonitor does not reliably
        // fire for these prompts on current iOS.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let providers = [app, springboard]

        var sawAlert = false
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for provider in providers {
                for container in [provider.alerts.firstMatch, provider.sheets.firstMatch] {
                    guard container.exists else { continue }
                    sawAlert = true
                    let button = container.buttons[buttonText]
                    if button.exists {
                        button.tap()
                        return
                    }
                }
            }

            // The Save Password sheet exposes its buttons directly under
            // SpringBoard on some iOS versions, outside alerts/sheets queries.
            let systemButton = springboard.buttons[buttonText]
            if systemButton.exists, systemButton.isHittable {
                systemButton.tap()
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        if sawAlert {
            throw ActionError.actionFailed(action: "alertTap", reason: "Button '\(buttonText)' not found in alert")
        }
        throw ActionError.actionFailed(action: "alertTap", reason: "No alert appeared within \(Int(timeout * 1000))ms")
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

    private func executeSelectTab(step: TestStep, in app: XCUIApplication) throws {
        guard let index = step.index else {
            throw ActionError.missingParameter(action: "selectTab", parameter: "index")
        }

        let timeout = TimeInterval(step.timeout ?? 5000) / 1000.0

        // For UIKit mode, use standard TabBar buttons directly
        if platform == "ios-uikit" {
            let tabBar = app.tabBars.firstMatch
            if tabBar.waitForExistence(timeout: timeout) {
                let buttons = tabBar.buttons
                if index < buttons.count {
                    buttons.element(boundBy: index).tap()
                    return
                }
            }
            throw ActionError.actionFailed(action: "selectTab", reason: "Tab at index \(index) not found in TabBar")
        }

        // For SwiftUI mode (default), try accessibilityIdentifier pattern first
        if let id = step.id {
            let tabId = "\(id)_tab_\(index)"
            let tabElement = app.descendants(matching: .any).matching(identifier: tabId).firstMatch

            if tabElement.waitForExistence(timeout: timeout) {
                tabElement.tap()
                return
            }
        }

        // Fallback: Use standard TabBar buttons by index (works for both SwiftUI TabView and UIKit)
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: timeout) {
            let buttons = tabBar.buttons
            if index < buttons.count {
                buttons.element(boundBy: index).tap()
                return
            }
        }

        let idInfo = step.id ?? "no id"
        throw ActionError.actionFailed(action: "selectTab", reason: "Tab at index \(index) not found (id: \(idInfo))")
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

    /// Element resolution for text-input actions. The generic `.any`
    /// firstMatch can resolve an identifier to a mirror StaticText (SwiftUI
    /// exposes a field's mirrored label under the same id), which cannot
    /// take keyboard focus — typeText then fails with "Neither element nor
    /// any descendant has keyboard focus". Prefer typable element types and
    /// only fall back to the generic match.
    private func findTypableElement(id: String, in app: XCUIApplication) throws -> XCUIElement {
        let generic = findElementQuery(id: id, in: app)
        guard generic.waitForExistence(timeout: defaultTimeout) else {
            throw ActionError.elementNotFound(id: id)
        }
        let typableTypes: [XCUIElement.ElementType] = [.textField, .secureTextField, .textView, .searchField]
        for type in typableTypes {
            let candidate = app.descendants(matching: type).matching(identifier: id).firstMatch
            if candidate.exists {
                return candidate
            }
        }
        return generic
    }

    /// Element resolution for tap-like actions (tap / doubleTap / longPress).
    /// The generic `.any` firstMatch can resolve an identifier to a mirror
    /// StaticText or a non-interactive wrapper under the same id — the tap
    /// then lands on an element that swallows it and the control's callback
    /// never fires. Snapshot traversal order is not stable across runs, so
    /// this surfaces as intermittent conformance failures
    /// (common/onclick__callback_fire, Toggle/onValueChange__callback_fire).
    /// Prefer interactive element types, then any hittable match, and only
    /// fall back to the generic match.
    private func findTappableElement(id: String, in app: XCUIApplication) throws -> XCUIElement {
        let generic = findElementQuery(id: id, in: app)
        guard generic.waitForExistence(timeout: defaultTimeout) else {
            throw ActionError.elementNotFound(id: id)
        }
        let interactiveTypes: [XCUIElement.ElementType] = [
            .button, .switch, .toggle, .checkBox, .segmentedControl,
            .slider, .stepper, .link, .cell,
        ]
        for type in interactiveTypes {
            let candidate = app.descendants(matching: type).matching(identifier: id).firstMatch
            if candidate.exists {
                return candidate
            }
        }
        // No interactive-typed match — scan the first few generic matches for
        // a hittable one (the mirror StaticText of an offscreen control is
        // typically not hittable at the control's position).
        let matches = app.descendants(matching: .any).matching(identifier: id)
        let count = min(matches.count, 8)
        var index = 0
        while index < count {
            let candidate = matches.element(boundBy: index)
            if candidate.exists && candidate.isHittable {
                return candidate
            }
            index += 1
        }
        return generic
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
