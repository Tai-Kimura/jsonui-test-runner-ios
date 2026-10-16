import XCTest
@testable import JsonUITestRunner

/// The shared vectors (specs/vectors/, vendored into Fixtures/) and the
/// launch environment, all without XCUIApplication.
private func fixture(_ name: String) throws -> [String: Any] {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
                            "Fixtures/\(name).json is not in the test bundle")
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let checked = try XCTUnwrap(root)
    XCTAssertEqual((checked["version"] as? NSNumber)?.intValue, 1)
    return checked
}

private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}

/// JSON values compared as JSON (NSNumber / NSNull / arrays / objects), so a
/// launch's screens equal the vector's when they would serialize the same.
private func sameJSON(_ a: Any?, _ b: Any?) -> Bool {
    let wrap: (Any?) -> Data? = { value in
        try? JSONSerialization.data(withJSONObject: ["v": value ?? NSNull()], options: [.sortedKeys])
    }
    return wrap(a) == wrap(b)
}

final class InitialStatePayloadVectorTests: XCTestCase {
    func testEveryVectorCase() throws {
        let cases = try XCTUnwrap(try fixture("initial-state-payload")["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 15, "the vector lost its cases")
        for vectorCase in cases {
            let name = vectorCase["name"] as? String ?? "?"
            let test = try XCTUnwrap(vectorCase["test"] as? [String: Any])
            let files = vectorCase["files"] as? [String: Any] ?? [:]
            let expect = try XCTUnwrap(vectorCase["expect"] as? [String: Any])

            let plan: InitialStatePlan
            if test["type"] as? String == "flow" {
                let flow = try decode(FlowTest.self, test)
                plan = InitialStatePlan.plan(flowTest: flow) { file in
                    files[file].flatMap { try? decode(ScreenTest.self, $0) }
                }
            } else {
                plan = InitialStatePlan.plan(screenTest: try decode(ScreenTest.self, test))
            }

            let launches = expect["launches"] as? [[String: Any]] ?? []
            XCTAssertEqual(plan.launches.count, launches.count, "launch count: \(name)")
            for (got, want) in zip(plan.launches, launches) {
                let before: InitialStatePlan.Before = (want["before"] as? String) == "file"
                    ? .file : .testCase(String((want["before"] as! String).dropFirst("case:".count)))
                XCTAssertEqual(got.before, before, "before: \(name)")
                XCTAssertTrue(sameJSON(got.screens, want["screens"] is NSNull ? nil : want["screens"]),
                              "screens: \(name) got \(String(describing: got.screens))")
            }

            let failures = (expect["caseFailures"] as? [[String: Any]] ?? []).map {
                InitialStatePlan.CaseFailure(caseName: $0["case"] as! String, code: $0["code"] as! String)
            }
            XCTAssertEqual(plan.caseFailures, failures, "caseFailures: \(name)")
            for failure in expect["caseFailures"] as? [[String: Any]] ?? [] {
                XCTAssertEqual(failure["failureReason"] as? String, "setup", name)
            }

            let warnings = (expect["warnings"] as? [[String: Any]] ?? []).map {
                InitialStatePlan.Warning(code: $0["code"] as! String, file: $0["file"] as! String, caseName: $0["case"] as? String)
            }
            XCTAssertEqual(plan.warnings, warnings, "warnings: \(name)")
        }
    }

    func testThePayloadCarriesVersionLaunchIdAndScreens() throws {
        let text = try XCTUnwrap(InitialStatePayload.encode(screens: ["login": ["email": "a", "nickname": NSNull()]], launchId: "L1"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual((root["version"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(root["launchId"] as? String, "L1")
        let login = try XCTUnwrap((root["screens"] as? [String: Any])?["login"] as? [String: Any])
        XCTAssertTrue(login["nickname"] is NSNull, "a null travels as null")
    }

    func testScreenIdentity() {
        XCTAssertEqual(ScreenIdentity.screenId(layoutPath: "Layouts/ProductDetail.json"), "ProductDetail")
        XCTAssertEqual(ScreenIdentity.screenId(layoutPath: "Layouts/a/home@regular.json"), "home")
        // Only the size classes are variants.
        XCTAssertEqual(ScreenIdentity.screenId(layoutPath: "Layouts/home@other.json"), "home@other")
    }
}

final class LaunchEnvironmentTests: XCTestCase {
    private func launch(_ json: String) throws -> LaunchConfig {
        try JSONDecoder().decode(LaunchConfig.self, from: Data(json.utf8))
    }

    /// The incident: file A launches with clearState and arguments, file B
    /// only with mocks — B's launch must not carry A's keys.
    func testTheNextLaunchCarriesNoneOfTheLastOnesKeys() throws {
        let a = LaunchEnvironment.environment(
            base: ["HARNESS_KEY": "kept"],
            launch: try launch(#"{"clearState":true,"arguments":{"apiBase":"http://x"},"permissions":{"camera":"allow"}}"#),
            initialStatePayload: "{}")
        XCTAssertEqual(a[LaunchEnvironment.clearState], "1")
        XCTAssertNotNil(a[LaunchEnvironment.arguments])
        XCTAssertNotNil(a[LaunchEnvironment.permissions])
        XCTAssertEqual(a[LaunchEnvironment.initialState], "{}")

        let b = LaunchEnvironment.environment(base: a, launch: nil, initialStatePayload: nil)
        for key in LaunchEnvironment.owned {
            XCTAssertNil(b[key], "\(key) leaked into the next launch")
        }
        XCTAssertEqual(b["HARNESS_KEY"], "kept", "a key the harness set is not the runner's to remove")
    }

    func testClearStateFalseSetsNothing() throws {
        let env = LaunchEnvironment.environment(base: [LaunchEnvironment.clearState: "1"],
                                                launch: try launch(#"{"clearState":false}"#), initialStatePayload: nil)
        XCTAssertNil(env[LaunchEnvironment.clearState])
    }

    func testArgumentsAreJSON() throws {
        let env = LaunchEnvironment.environment(base: [:], launch: try launch(#"{"arguments":{"mockApi":true,"n":2}}"#),
                                                initialStatePayload: nil)
        let args = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(env[LaunchEnvironment.arguments]!.utf8)) as? [String: Any])
        XCTAssertEqual(args["mockApi"] as? Bool, true)
        XCTAssertEqual((args["n"] as? NSNumber)?.intValue, 2)
    }
}

final class StateBridgeVectorTests: XCTestCase {
    func testEveryPathCase() throws {
        let root = try fixture("state-path")
        let data = try XCTUnwrap(root["data"] as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 20)
        for vectorCase in cases {
            let name = vectorCase["name"] as? String ?? "?"
            let path = vectorCase["path"] as! String
            let expect = vectorCase["expect"] as! [String: Any]
            switch StateBridge.resolve(path, in: data) {
            case .value(let value):
                XCTAssertNotNil(expect["value"] ?? nil, "resolved but the vector says it does not: \(name)")
                if expect.keys.contains("value") {
                    XCTAssertTrue(sameJSON(value, expect["value"]), "value: \(name)")
                    // A JSON boolean is not a number, and null is not "absent".
                    XCTAssertEqual(CFGetTypeID(value as CFTypeRef), CFGetTypeID(expect["value"]! as CFTypeRef), "type: \(name)")
                }
            case .unresolved:
                XCTAssertEqual(expect["resolved"] as? Bool, false, "did not resolve: \(name)")
            }
        }
    }

    func testEveryBridgeCase() throws {
        let bridges = try XCTUnwrap(try fixture("state-path")["bridges"] as? [[String: Any]])
        for vectorCase in bridges {
            let name = vectorCase["name"] as? String ?? "?"
            let bridge = vectorCase["bridge"]
            let text: String? = (bridge == nil || bridge is NSNull) ? nil
                : String(data: try JSONSerialization.data(withJSONObject: bridge!), encoding: .utf8)
            let expect = vectorCase["expect"] as! [String: Any]
            let outcome = StateBridge.outcome(StateBridge.parse(text), path: vectorCase["path"] as! String)
            switch (outcome, expect["outcome"] as? String) {
            case (.pending, "pending"), (.truncated, "truncated"), (.unresolved, "unresolved"):
                break
            case (.value(let value), "value"):
                XCTAssertTrue(sameJSON(value, expect["value"]), name)
            default:
                XCTFail("\(name): got \(outcome), expected \(String(describing: expect["outcome"]))")
            }
        }
    }

    func testReceiptIsForThisLaunchOnly() {
        let json = #"{"launchId":"L1","initialState":{"applied":["email"],"rejected":[]},"data":{}}"#
        XCTAssertEqual(StateBridge.receipt(StateBridge.parse(json), launchId: "L1"), .confirmed)
        XCTAssertEqual(StateBridge.receipt(StateBridge.parse(json), launchId: "L2"), .waiting, "an earlier launch's receipt")
        let rejected = #"{"launchId":"L1","initialState":{"applied":[],"rejected":[{"key":"x","reason":"not a data field"}]},"data":{}}"#
        XCTAssertEqual(StateBridge.receipt(StateBridge.parse(rejected), launchId: "L1"),
                       .rejected([StateBridge.Rejection(key: "x", reason: "not a data field")]))
        let none = #"{"launchId":"L1","initialState":null,"data":{}}"#
        XCTAssertEqual(StateBridge.receipt(StateBridge.parse(none), launchId: "L1"), .waiting)
        XCTAssertEqual(StateBridge.receipt(.absent, launchId: "L1"), .waiting)
        XCTAssertEqual(StateBridge.receipt(StateBridge.parse(#"{"truncated":40000}"#), launchId: "L1"), .truncated(bytes: 40000))
    }
}
