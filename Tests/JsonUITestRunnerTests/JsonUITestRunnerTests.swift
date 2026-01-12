import XCTest
@testable import JsonUITestRunner

final class JsonUITestRunnerTests: XCTestCase {

    func testScreenTestParsing() throws {
        let json = """
        {
            "type": "screen",
            "source": {
                "layout": "Layouts/Login.json"
            },
            "metadata": {
                "name": "Login Test"
            },
            "cases": [
                {
                    "name": "Test Case 1",
                    "steps": [
                        { "assert": "visible", "id": "test_element" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let screenTest = try decoder.decode(ScreenTest.self, from: json)

        XCTAssertEqual(screenTest.type, "screen")
        XCTAssertEqual(screenTest.source.layout, "Layouts/Login.json")
        XCTAssertEqual(screenTest.metadata.name, "Login Test")
        XCTAssertEqual(screenTest.cases.count, 1)
        XCTAssertEqual(screenTest.cases[0].name, "Test Case 1")
        XCTAssertEqual(screenTest.cases[0].steps.count, 1)
    }

    func testFlowTestParsing() throws {
        let json = """
        {
            "type": "flow",
            "sources": [
                { "layout": "Layouts/Login.json", "alias": "Login" },
                { "layout": "Layouts/Home.json", "alias": "Home" }
            ],
            "metadata": {
                "name": "Login Flow Test"
            },
            "steps": [
                { "screen": "Login", "action": "tap", "id": "login_button" },
                { "screen": "Home", "assert": "visible", "id": "welcome_label" }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let flowTest = try decoder.decode(FlowTest.self, from: json)

        XCTAssertEqual(flowTest.type, "flow")
        XCTAssertEqual(flowTest.sources.count, 2)
        XCTAssertEqual(flowTest.metadata.name, "Login Flow Test")
        XCTAssertEqual(flowTest.steps.count, 2)
        XCTAssertEqual(flowTest.steps[0].screen, "Login")
        XCTAssertEqual(flowTest.steps[0].action, "tap")
        XCTAssertEqual(flowTest.steps[1].screen, "Home")
        XCTAssertEqual(flowTest.steps[1].assert, "visible")
    }

    func testTestStepParsing() throws {
        // Action step
        let actionJson = """
        { "action": "input", "id": "email_field", "value": "test@example.com" }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let actionStep = try decoder.decode(TestStep.self, from: actionJson)

        XCTAssertEqual(actionStep.action, "input")
        XCTAssertEqual(actionStep.id, "email_field")
        XCTAssertEqual(actionStep.value, "test@example.com")
        XCTAssertTrue(actionStep.isAction)
        XCTAssertFalse(actionStep.isAssertion)

        // Assertion step
        let assertJson = """
        { "assert": "text", "id": "label", "contains": "Hello" }
        """.data(using: .utf8)!

        let assertStep = try decoder.decode(TestStep.self, from: assertJson)

        XCTAssertEqual(assertStep.assert, "text")
        XCTAssertEqual(assertStep.id, "label")
        XCTAssertEqual(assertStep.contains, "Hello")
        XCTAssertFalse(assertStep.isAction)
        XCTAssertTrue(assertStep.isAssertion)
    }

    func testPlatformTargetParsing() throws {
        // Single platform
        let singleJson = "\"ios\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let single = try decoder.decode(PlatformTarget.self, from: singleJson)

        XCTAssertTrue(single.includes("ios"))
        XCTAssertFalse(single.includes("android"))

        // All platforms
        let allJson = "\"all\"".data(using: .utf8)!
        let all = try decoder.decode(PlatformTarget.self, from: allJson)

        XCTAssertTrue(all.includes("ios"))
        XCTAssertTrue(all.includes("android"))
        XCTAssertTrue(all.includes("web"))

        // Multiple platforms
        let multiJson = "[\"ios\", \"android\"]".data(using: .utf8)!
        let multi = try decoder.decode(PlatformTarget.self, from: multiJson)

        XCTAssertTrue(multi.includes("ios"))
        XCTAssertTrue(multi.includes("android"))
        XCTAssertFalse(multi.includes("web"))
    }

    func testAnyCodableParsing() throws {
        let json = """
        {
            "string": "hello",
            "int": 42,
            "bool": true,
            "double": 3.14,
            "null": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let dict = try decoder.decode([String: AnyCodable].self, from: json)

        XCTAssertEqual(dict["string"]?.stringValue, "hello")
        XCTAssertEqual(dict["int"]?.intValue, 42)
        XCTAssertEqual(dict["bool"]?.boolValue, true)
        XCTAssertEqual(dict["double"]?.doubleValue, 3.14)
    }
}
