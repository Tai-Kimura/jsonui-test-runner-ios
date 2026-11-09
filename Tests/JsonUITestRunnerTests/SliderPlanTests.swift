import XCTest
@testable import JsonUITestRunner

/// setSliderValue / the value assertion, from numbers alone (SliderPlan):
/// the refusals shared with Android and web, the readings measured on a
/// SwiftUI Slider (2026-11-09, iOS 27.2), and where each drag goes.
final class SliderPlanTests: XCTestCase {
    private func refusal(_ v: Double, _ lo: Double = 1, _ hi: Double = 10, range: [Double]? = nil, step: Double? = nil) -> String? {
        SliderPlan.refusal(id: "r", value: v, min: lo, max: hi, declaredRange: range, step: step)
    }

    func testInRangeOnTheGridIsAccepted() {
        XCTAssertNil(refusal(9)); XCTAssertNil(refusal(1)); XCTAssertNil(refusal(10)); XCTAssertNil(refusal(9.4))
        XCTAssertNil(refusal(9, step: 1)); XCTAssertNil(refusal(0.3, 0, 1, step: 0.1)); XCTAssertNil(refusal(-2.5, -5, 5, step: 0.5))
    }

    func testBelowAndAboveNameTheBound() {
        XCTAssertEqual(refusal(0), "setSliderValue 'r': 0 is below the slider's range [1, 10]; the nearest value it can take is 1")
        XCTAssertEqual(refusal(11), "setSliderValue 'r': 11 is above the slider's range [1, 10]; the nearest value it can take is 10")
    }

    func testOffTheGridNamesBothNeighbours() {
        XCTAssertEqual(refusal(9.4, step: 1),
                       "setSliderValue 'r': 9.4 is not on the slider's steps (1 + k * 1); the nearest values are 9 and 10")
        XCTAssertTrue(refusal(0.25, 0, 1, step: 0.1)!.hasSuffix("the nearest values are 0.2 and 0.3"))
        XCTAssertTrue(refusal(2, 1, 10, step: 2)!.hasSuffix("the nearest values are 1 and 3"))
        XCTAssertTrue(refusal(9.5, 1, 10, step: 2)!.hasSuffix("the nearest values are 9 and 10"))
    }

    func testADeclaredRangeThatIsNotTheSlidersIsRefusedFirst() {
        XCTAssertEqual(refusal(50, range: [0, 100]),
                       "setSliderValue 'r': the step declares range [0, 100] but the slider's own is [1, 10]")
        XCTAssertNil(refusal(5, range: [1, 10]))
    }

    func testToleranceIsHalfAStepElseHalfAPercentOfTheRange() {
        XCTAssertEqual(SliderPlan.tolerance(min: 1, max: 10, step: 1), 0.5)
        XCTAssertEqual(SliderPlan.tolerance(min: 1, max: 10, step: nil), 0.045, accuracy: 1e-12)
        XCTAssertEqual(SliderPlan.tolerance(min: 0, max: 1, step: nil), 0.005, accuracy: 1e-12)
    }

    func testTheAccessibilityValueAsIOSShowsIt() {
        // Measured shapes: three decimals, grouping, the typographic minus, a percentage.
        XCTAssertEqual(SliderPlan.parse("9.003"), .number(9.003))
        XCTAssertEqual(SliderPlan.parse("1,000"), .number(1000))
        XCTAssertEqual(SliderPlan.parse("-2.001"), .number(-2.001))
        XCTAssertEqual(SliderPlan.parse("\u{2212}2.5"), .number(-2.5))
        XCTAssertEqual(SliderPlan.parse("37%"), .percent(37))
        XCTAssertNil(SliderPlan.parse(""))
        XCTAssertNil(SliderPlan.parse("on"))
        XCTAssertEqual(SliderPlan.value(of: .percent(37), min: 0, max: 1)!, 0.37, accuracy: 1e-12)
        XCTAssertEqual(SliderPlan.value(of: .percent(37), min: 0, max: 100)!, 37, accuracy: 1e-12)
        XCTAssertNil(SliderPlan.value(of: .percent(37), min: nil, max: nil))
    }

    // The probe's 1...10 slider: frame x 16, width 370, on a 402pt screen.
    private func drag(_ from: Double, _ to: Double, _ lo: Double = 1, _ hi: Double = 10) -> SliderPlan.Drag {
        SliderPlan.nextDrag(current: from, target: to, min: lo, max: hi, minX: 16, width: 370, screenWidth: 402)
    }

    func testAFarMoveStartsOnTheThumbAndEndsTheSlopPastTheTarget() {
        let d = drag(5, 9)
        XCTAssertFalse(d.isStepAway)
        XCTAssertEqual(d.from, SliderPlan.x(of: 5, min: 1, max: 10, minX: 16, width: 370), accuracy: 1e-9)
        XCTAssertEqual(d.to, SliderPlan.x(of: 9, min: 1, max: 10, minX: 16, width: 370) + 10, accuracy: 1e-9)
        let back = drag(9, 2)
        XCTAssertEqual(back.to, SliderPlan.x(of: 2, min: 1, max: 10, minX: 16, width: 370) - 10, accuracy: 1e-9)
    }

    func testAShortMoveStepsAwayFirstToTheSideWithRoom() {
        // 8 -> 9 is 41pt: shorter than 60, so step away — 9 is in the right half, so to the left.
        let d = drag(8, 9)
        XCTAssertTrue(d.isStepAway)
        XCTAssertLessThan(d.to, d.from)
        // 1 -> 2 (left half): away to the right of 2.
        let e = drag(1, 2)
        XCTAssertTrue(e.isStepAway)
        XCTAssertGreaterThan(e.to, SliderPlan.x(of: 2, min: 1, max: 10, minX: 16, width: 370))
    }

    func testABoundIsReachedByDraggingPastTheFrameEdge() {
        // Measured: adjust(0/1) does not move a thumb already close to that end.
        XCTAssertEqual(drag(5, 1).to, 16 - 10 - 4)
        XCTAssertEqual(drag(5, 10).to, 16 + 370 + 10 + 4)
        // Close to the end: step away first.
        XCTAssertTrue(drag(9.9, 10).isStepAway)
        // Points stay on screen.
        let edge = SliderPlan.nextDrag(current: 5, target: 10, min: 1, max: 10, minX: 0, width: 402, screenWidth: 402)
        XCTAssertEqual(edge.to, 401)
    }

    func testNumbersAreWrittenAsATestAuthorWritesThem() {
        XCTAssertEqual(SliderPlan.format(9), "9"); XCTAssertEqual(SliderPlan.format(-2.5), "-2.5")
        XCTAssertEqual(SliderPlan.format(0.123456), "0.123456"); XCTAssertEqual(SliderPlan.format(0.1 * 3), "0.3")
        XCTAssertEqual(SliderPlan.format(1000), "1000")
    }

    func testANumericValueDecodesAsTheStepsValueAndATextOneStaysText() throws {
        let decoder = JSONDecoder()
        let slider = try decoder.decode(TestStep.self, from: Data(#"{"action":"setSliderValue","id":"r","value":9.5,"range":[1,10],"step":0.5}"#.utf8))
        XCTAssertEqual(slider.value, "9.5"); XCTAssertEqual(slider.range, [1, 10]); XCTAssertEqual(slider.step, 0.5)
        XCTAssertEqual(try decoder.decode(TestStep.self, from: Data(#"{"action":"setSliderValue","id":"r","value":9}"#.utf8)).value, "9")
        XCTAssertEqual(try decoder.decode(TestStep.self, from: Data(#"{"action":"input","id":"r","value":"007"}"#.utf8)).value, "007")
        XCTAssertNil(try decoder.decode(TestStep.self, from: Data(#"{"action":"tap","id":"r"}"#.utf8)).value)
        let flow = try decoder.decode(FlowTestStep.self, from: Data(#"{"screen":"s","action":"setSliderValue","id":"r","value":3,"tolerance":0.25}"#.utf8))
        XCTAssertEqual(flow.value, "3"); XCTAssertEqual(flow.toTestStep().tolerance, 0.25)
        // Encoding leaves an absent value out, as a plain String? did.
        let encoded = String(decoding: try JSONEncoder().encode(TestStep(action: "tap", id: "r")), as: UTF8.self)
        XCTAssertFalse(encoded.contains("value"))
    }
}
