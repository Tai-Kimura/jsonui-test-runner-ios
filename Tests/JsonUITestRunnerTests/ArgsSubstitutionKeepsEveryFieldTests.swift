import XCTest
@testable import JsonUITestRunner

/// A referenced case run with args is rebuilt step by step (TestLoader.substituteArgs at load, TestRunner's
/// substituteArgsInStep at run time, and a flow's inline step through toTestStep), field by field. A field left out of
/// a rebuild is dropped in silence: until 2.4.0 the two substitutions dropped setSliderValue's range, step and
/// tolerance, so a slider step in an args case lost its bounds and its tolerance.
final class ArgsSubstitutionKeepsEveryFieldTests: XCTestCase {

    func testASliderStepInAnArgsCaseKeepsItsRangeStepAndTolerance() throws {
        let json = """
        {
            "name": "Slider with args",
            "args": { "which": "rating" },
            "steps": [
                { "action": "setSliderValue", "id": "@{which}", "value": "9", "range": [1, 10], "step": 1 },
                { "assert": "value", "id": "@{which}", "equals": 9, "range": [1, 10], "tolerance": 0.5 },
                { "action": "moveItem", "id": "stops_@{which}", "from": 1, "to": 3, "handle": "grip_@{which}" }
            ]
        }
        """.data(using: .utf8)!
        let testCase = try JSONDecoder().decode(TestCase.self, from: json)
        let steps = TestLoader().applyArgsSubstitution(to: testCase).steps

        XCTAssertEqual(steps[0].id, "rating")
        XCTAssertEqual(steps[0].range, [1, 10])
        XCTAssertEqual(steps[0].step, 1)
        XCTAssertEqual(steps[1].range, [1, 10])
        XCTAssertEqual(steps[1].tolerance, 0.5)
        XCTAssertEqual(steps[2].id, "stops_rating")
        XCTAssertEqual(steps[2].from, 1)
        XCTAssertEqual(steps[2].to, 3)
        XCTAssertEqual(steps[2].handle, "grip_rating")
    }

    /// Every TestStep property is named in each rebuild, so a field added later cannot be dropped by one of them.
    func testEveryRebuildOfAStepNamesEveryField() throws {
        let models = try source("Models/TestModels.swift")
        let start = try XCTUnwrap(models.range(of: "public struct TestStep: Codable"))
        let end = try XCTUnwrap(models.range(of: "\n}\n", range: start.upperBound..<models.endIndex))
        let body = models[start.upperBound..<end.lowerBound]
        let fields = body.split(separator: "\n").compactMap { line -> String? in
            let code = line.trimmingCharacters(in: .whitespaces)
            guard code.hasPrefix("public let ") else { return nil }
            return String(code.dropFirst("public let ".count).prefix { $0 != ":" }).replacingOccurrences(of: "`", with: "")
        }
        XCTAssertGreaterThan(fields.count, 30)

        let sites: [(String, String)] = [
            ("Runner/TestLoader.swift", "private func substituteArgs(in step: TestStep"),
            ("Runner/TestRunner.swift", "private func substituteArgsInStep(_ step: TestStep"),
            ("Assertions/AssertionExecutor.swift", "func toTestStep() -> TestStep {"),
        ]
        for (file, opening) in sites {
            let text = try source(file)
            let at = try XCTUnwrap(text.range(of: opening), "\(opening) not found in \(file)")
            let close = try XCTUnwrap(text.range(of: "\n        )", range: at.upperBound..<text.endIndex))
            let rebuild = String(text[at.upperBound..<close.lowerBound])
            let missing = fields.filter { field in
                !rebuild.contains("\n            \(field):") && !rebuild.contains("\n            `\(field)`:")
            }
            XCTAssertEqual(missing, [], "\(file) rebuilds a TestStep without these fields")
        }
    }

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("Sources/JsonUITestRunner/\(relative)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw XCTSkip("\(relative) not reachable from \(#filePath)")
    }
}
