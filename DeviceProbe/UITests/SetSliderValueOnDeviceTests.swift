import XCTest
import JsonUITestRunner

/// setSliderValue, the value assertion and readText on SwiftUI Sliders
/// (SliderProbeApp), through the public executors — one test per iOS row of
/// the family table measured 2026-11-09 (docs/bugs 2026-11-09
/// test-runner-no-slider-action): a slider moves only under a finger, so the
/// value lands within the tolerance, never exactly; the ends need a drag past
/// the edge; a 0...1 / 0...100 slider reads as a percentage.
final class SetSliderValueOnDeviceTests: XCTestCase {
    private var app: XCUIApplication!
    private var actions: XCUITestActionExecutor!
    private var assertions: XCUITestAssertionExecutor!
    private let variables = VariableStore()

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        actions = XCUITestActionExecutor(variables: variables)
        assertions = XCUITestAssertionExecutor(defaultTimeout: 1.5)
        XCTAssertTrue(app.sliders["s1to10"].waitForExistence(timeout: 10))
    }

    /// What the app holds.
    private func held(_ id: String) -> Double { Double(app.staticTexts["v_" + id].label)! }
    private func finished(_ id: String) -> Int { Int(app.staticTexts["n_" + id].label)! }

    private func set(_ id: String, _ value: String, range: [Double]? = nil, step: Double? = nil) throws {
        try actions.execute(step: TestStep(action: "setSliderValue", id: id, value: value, range: range, step: step), in: app)
    }

    private func refused(_ id: String, _ value: String, range: [Double]? = nil, step: Double? = nil,
                         file: StaticString = #filePath, line: UInt = #line) -> String {
        let before = held(id), drags = finished(id)
        do {
            try set(id, value, range: range, step: step)
        } catch {
            XCTAssertEqual(held(id), before, "\(id) moved although the step was refused", file: file, line: line)
            XCTAssertEqual(finished(id), drags, "\(id) was dragged although the step was refused", file: file, line: line)
            return error.localizedDescription
        }
        XCTFail("setSliderValue \(id) \(value) passed; expected a refusal", file: file, line: line)
        return ""
    }

    func testInRangeValuesLandWithinTheToleranceAndTheLandedValueIsRecorded() throws {
        let cases: [(String, Double, [Double]?, Double?, Double)] = [
            // id, value, range, step, tolerance
            ("s1to10", 9, [1, 10], 1, 0.5),
            ("s1to10", 2, [1, 10], 1, 0.5),
            ("s1to10", 5, [1, 10], 1, 0.5),
            ("s1to10", 9.5, [1, 10], nil, 0.045),
            ("s0to100", 37, [0, 100], 1, 0.5),
            ("s0to1", 0.73, [0, 1], nil, 0.005),
            ("sm5to5", -2.5, nil, nil, 0.05),      // bounds read from the ends
            ("s0to1000", 999, nil, nil, 5),
        ]
        for (id, value, range, step, tolerance) in cases {
            try set(id, SliderPlan.format(value), range: range, step: step)
            XCTAssertEqual(held(id), value, accuracy: tolerance, "\(id) holds \(held(id)) after setSliderValue \(value)")
            let notes = actions.drainWarnings()
            XCTAssertEqual(notes.count, 1, "\(notes)")
            XCTAssertTrue(notes.first?.hasPrefix("setSliderValue '\(id)': landed at ") == true, "\(notes)")
        }
    }

    func testTheEndsAreReachedFromCloseBy() throws {
        // Measured: adjust(1) from 99 and adjust(0) from 0.96 do not move.
        // No step: the tolerance (0.045) is tighter than the 0.2 left to go,
        // and an end is reached exactly, the slider clamping the drag.
        try set("s1to10", "9.8", range: [1, 10])
        try set("s1to10", "10", range: [1, 10])
        XCTAssertEqual(held("s1to10"), 10, accuracy: 1e-9)
        try set("s1to10", "1.2", range: [1, 10])
        try set("s1to10", "1", range: [1, 10])
        XCTAssertEqual(held("s1to10"), 1, accuracy: 1e-9)
    }

    func testOutOfRangeIsRefusedBeforeAnythingMovesNamingTheBound() {
        XCTAssertTrue(refused("s1to10", "0", range: [1, 10]).contains("0 is below the slider's range [1, 10]; the nearest value it can take is 1"))
        XCTAssertTrue(refused("s1to10", "11", range: [1, 10]).contains("11 is above the slider's range [1, 10]; the nearest value it can take is 10"))
    }

    func testOffTheStepIsRefusedBeforeAnythingMovesNamingTheNeighbours() {
        XCTAssertTrue(refused("s1to10", "9.4", range: [1, 10], step: 1).contains("the nearest values are 9 and 10"))
    }

    func testAPercentageSliderWithoutRangeIsRefusedAskingForIt() {
        do {
            try set("s0to1", "0.5")
            XCTFail("a 0...1 slider without range passed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("give range"), error.localizedDescription)
        }
    }

    func testTheValueAssertionReadsTheSlider() throws {
        try assertions.execute(step: TestStep(assert: "value", id: "s1to10", equals: AnyCodable(5), range: [1, 10]), in: app)
        try set("s1to10", "8", range: [1, 10], step: 1)
        try assertions.execute(step: TestStep(assert: "value", id: "s1to10", equals: AnyCodable(8), step: 1), in: app)
        XCTAssertThrowsError(try assertions.execute(step: TestStep(assert: "value", id: "s1to10", equals: AnyCodable(6), step: 1), in: app)) {
            XCTAssertTrue($0.localizedDescription.contains("the slider 's1to10' is at 8"), $0.localizedDescription)
        }
        // A percentage reads with range only.
        try set("s0to100", "40", range: [0, 100], step: 1)
        try assertions.execute(step: TestStep(assert: "value", id: "s0to100", equals: AnyCodable(40), range: [0, 100], step: 1), in: app)
        XCTAssertThrowsError(try assertions.execute(step: TestStep(assert: "value", id: "s0to100", equals: AnyCodable(40), tolerance: 1), in: app)) {
            XCTAssertTrue($0.localizedDescription.contains("give range"), $0.localizedDescription)
        }
    }

    func testReadTextReadsASlidersValue() throws {
        try actions.execute(step: TestStep(action: "readText", id: "s1to10", variable: "v"), in: app)
        XCTAssertEqual(variables.get("v"), "5")
    }
}
