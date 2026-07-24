import XCTest
@testable import JsonUITestRunner
#if canImport(UIKit)
import UIKit
#endif

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
        XCTAssertEqual(flowTest.sources?.count, 2)
        XCTAssertEqual(flowTest.metadata.name, "Login Flow Test")
        XCTAssertEqual(flowTest.steps.count, 2)
        XCTAssertEqual(flowTest.steps[0].screen, "Login")
        XCTAssertEqual(flowTest.steps[0].action, "tap")
        XCTAssertEqual(flowTest.steps[1].screen, "Home")
        XCTAssertEqual(flowTest.steps[1].assert, "visible")
    }

    // Regression: test-flow-file-level-mocks-silently-ignored — FlowTest had no
    // `mocks` field, so a file-level mocks map was dropped at decode and the
    // runner never applied it. Pin the field so the map survives decoding.
    func testFlowTestFileLevelMocksParsing() throws {
        let json = """
        {
            "type": "flow",
            "metadata": { "name": "Flow With Mocks" },
            "mocks": { "listOrders": "real_id", "getOrder": "real_id" },
            "steps": [ { "screen": "Home", "action": "tap", "id": "start_button" } ]
        }
        """.data(using: .utf8)!

        let flowTest = try JSONDecoder().decode(FlowTest.self, from: json)
        XCTAssertEqual(flowTest.mocks?["listOrders"], "real_id")
        XCTAssertEqual(flowTest.mocks?["getOrder"], "real_id")
    }

    func testFlowTestAbsentMocksIsNil() throws {
        let json = """
        {
            "type": "flow",
            "metadata": { "name": "Flow No Mocks" },
            "steps": [ { "screen": "Home", "action": "tap", "id": "start_button" } ]
        }
        """.data(using: .utf8)!

        let flowTest = try JSONDecoder().decode(FlowTest.self, from: json)
        XCTAssertNil(flowTest.mocks)
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

    func testArgsSubstitutionInSteps() throws {
        // Covers the String / String? substitution overloads that became
        // ambiguous under the Swift 6 toolchain (optional variant renamed to
        // substituteArgsInOptionalString): id/text/value/contains/button/label
        // are optional, elements of ids are non-optional.
        let json = """
        {
            "name": "Substitution Case",
            "args": { "userName": "alice", "row": 2 },
            "steps": [
                { "action": "input", "id": "field_@{userName}", "value": "hello @{userName}" },
                { "action": "tap", "ids": ["btn_@{userName}", "btn_@{row}"] },
                { "assert": "text", "id": "label", "contains": "@{userName}" },
                { "action": "tap", "button": "@{userName}", "label": "@{userName}", "text": "@{userName}" }
            ]
        }
        """.data(using: .utf8)!

        let testCase = try JSONDecoder().decode(TestCase.self, from: json)
        let loader = TestLoader()
        let substituted = loader.applyArgsSubstitution(to: testCase)

        XCTAssertEqual(substituted.steps[0].id, "field_alice")
        XCTAssertEqual(substituted.steps[0].value, "hello alice")
        XCTAssertEqual(substituted.steps[1].ids, ["btn_alice", "btn_2"])
        XCTAssertEqual(substituted.steps[2].contains, "alice")
        XCTAssertEqual(substituted.steps[3].button, "alice")
        XCTAssertEqual(substituted.steps[3].label, "alice")
        XCTAssertEqual(substituted.steps[3].text, "alice")
        // Untouched fields survive
        XCTAssertEqual(substituted.steps[2].assert, "text")
        XCTAssertEqual(substituted.steps[2].id, "label")
    }

    func testWhenConditionCapturesUnknownKeys() throws {
        // Known keys only -> nothing unknown, condition evaluates normally.
        // `responsive` is a known key since Phase 2.
        let knownJson = """
        { "visible": "sidebar", "platform": "ios", "responsive": "regular" }
        """.data(using: .utf8)!
        let known = try JSONDecoder().decode(WhenCondition.self, from: knownJson)
        XCTAssertTrue(known.unknownKeys.isEmpty)
        XCTAssertEqual(known.visible, "sidebar")
        XCTAssertEqual(known.responsive, .bucket("regular"))

        // A future key is captured instead of being silently dropped by
        // Codable (fail-safe skip contract)
        let unknownJson = """
        { "visible": "sidebar", "futureKey": { "minWidth": 768 } }
        """.data(using: .utf8)!
        let unknown = try JSONDecoder().decode(WhenCondition.self, from: unknownJson)
        XCTAssertEqual(unknown.unknownKeys, ["futureKey"])
        XCTAssertEqual(unknown.visible, "sidebar")
    }

    // MARK: - Responsive decoding

    func testWhenConditionDecodesResponsive() throws {
        // Named bucket
        let namedJson = """
        { "responsive": "compact-landscape" }
        """.data(using: .utf8)!
        let named = try JSONDecoder().decode(WhenCondition.self, from: namedJson)
        XCTAssertEqual(named.responsive, .bucket("compact-landscape"))

        // Constraint object
        let constraintJson = """
        { "responsive": { "minWidth": 768, "maxWidth": 1024, "orientation": "portrait" } }
        """.data(using: .utf8)!
        let constrained = try JSONDecoder().decode(WhenCondition.self, from: constraintJson)
        XCTAssertEqual(
            constrained.responsive,
            .constraint(ResponsiveConstraint(minWidth: 768, maxWidth: 1024, orientation: "portrait"))
        )
    }

    func testCaseLevelResponsiveDecodesTyped() throws {
        // Named-bucket form
        let namedJson = """
        {
            "name": "Regular Only",
            "responsive": "regular",
            "steps": [ { "assert": "visible", "id": "sidebar" } ]
        }
        """.data(using: .utf8)!
        let named = try JSONDecoder().decode(TestCase.self, from: namedJson)
        XCTAssertEqual(named.responsive, .bucket("regular"))

        // Constraint-object form
        let objectJson = """
        {
            "name": "Wide Only",
            "responsive": { "minWidth": 768, "minHeight": 600 },
            "steps": []
        }
        """.data(using: .utf8)!
        let object = try JSONDecoder().decode(TestCase.self, from: objectJson)
        XCTAssertEqual(object.responsive, .constraint(ResponsiveConstraint(minWidth: 768, minHeight: 600)))

        // Absent stays nil (case runs normally)
        let plainJson = """
        { "name": "Plain", "steps": [] }
        """.data(using: .utf8)!
        let plain = try JSONDecoder().decode(TestCase.self, from: plainJson)
        XCTAssertNil(plain.responsive)
    }

    func testSetOrientationStepDecoding() throws {
        let json = """
        { "action": "setOrientation", "orientation": "landscape" }
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(TestStep.self, from: json)
        XCTAssertEqual(step.action, "setOrientation")
        XCTAssertEqual(step.orientation, "landscape")
    }

    // MARK: - Responsive evaluation (pure functions, no live app)

    private func env(
        h: SizeClassValue,
        v: SizeClassValue,
        width: Double = 390,
        height: Double = 844,
        orientation: ResponsiveOrientation = .portrait
    ) -> ResponsiveEnvironment {
        ResponsiveEnvironment(
            horizontalSizeClass: h,
            verticalSizeClass: v,
            width: width,
            height: height,
            orientation: orientation
        )
    }

    func testBucketMatchingMirrorsSjuiSizeClassRules() {
        // iPhone portrait: wC hR
        let phonePortrait = env(h: .compact, v: .regular)
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("compact", in: phonePortrait))
        // medium folds to compact on iOS (renderer rule)
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("medium", in: phonePortrait))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("regular", in: phonePortrait))
        // landscape <=> verticalSizeClass == .compact
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("landscape", in: phonePortrait))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("compact-landscape", in: phonePortrait))

        // iPhone landscape (non-Max): wC hC
        let phoneLandscape = env(h: .compact, v: .compact, width: 844, height: 390, orientation: .landscape)
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("landscape", in: phoneLandscape))
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("compact", in: phoneLandscape))
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("compact-landscape", in: phoneLandscape))
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("medium-landscape", in: phoneLandscape))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("regular-landscape", in: phoneLandscape))

        // iPad (any orientation): wR hR — landscape bucket NEVER matches
        // (faithful to the renderer: vertical stays regular on iPad)
        let pad = env(h: .regular, v: .regular, width: 1180, height: 820, orientation: .landscape)
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("regular", in: pad))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("compact", in: pad))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("medium", in: pad))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("landscape", in: pad))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("regular-landscape", in: pad))

        // iPhone Max landscape: wR hC — regular-landscape matches
        let maxLandscape = env(h: .regular, v: .compact, width: 932, height: 430, orientation: .landscape)
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("regular", in: maxLandscape))
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("regular-landscape", in: maxLandscape))
        XCTAssertTrue(ResponsiveEvaluator.matchesBucket("landscape", in: maxLandscape))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("compact-landscape", in: maxLandscape))
    }

    func testBucketMatchingFailSafe() {
        let phonePortrait = env(h: .compact, v: .regular)
        // Unknown bucket (newer schema than this driver) is UNMET -> skip,
        // never run-anyway. "expanded" is the canonical wrong name.
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("expanded", in: phonePortrait))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("expanded-landscape", in: env(h: .compact, v: .compact)))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("", in: phonePortrait))

        // Unresolvable size classes -> every size-class bucket is UNMET
        let unknown = env(h: .unspecified, v: .unspecified)
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("compact", in: unknown))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("medium", in: unknown))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("regular", in: unknown))
        XCTAssertFalse(ResponsiveEvaluator.matchesBucket("landscape", in: unknown))
    }

    func testConstraintMatchingInclusiveBounds() {
        let ipadPortrait = env(h: .regular, v: .regular, width: 820, height: 1180, orientation: .portrait)

        // Inclusive min/max: the boundary value matches
        XCTAssertTrue(ResponsiveEvaluator.matchesConstraint(ResponsiveConstraint(minWidth: 820), in: ipadPortrait))
        XCTAssertTrue(ResponsiveEvaluator.matchesConstraint(ResponsiveConstraint(maxWidth: 820), in: ipadPortrait))
        XCTAssertFalse(ResponsiveEvaluator.matchesConstraint(ResponsiveConstraint(minWidth: 821), in: ipadPortrait))
        XCTAssertFalse(ResponsiveEvaluator.matchesConstraint(ResponsiveConstraint(maxWidth: 819), in: ipadPortrait))
        XCTAssertTrue(ResponsiveEvaluator.matchesConstraint(ResponsiveConstraint(minHeight: 1180, maxHeight: 1180), in: ipadPortrait))

        // Present keys AND together
        XCTAssertTrue(ResponsiveEvaluator.matchesConstraint(
            ResponsiveConstraint(minWidth: 768, maxWidth: 1024, orientation: "portrait"),
            in: ipadPortrait
        ))
        XCTAssertFalse(ResponsiveEvaluator.matchesConstraint(
            ResponsiveConstraint(minWidth: 768, orientation: "landscape"),
            in: ipadPortrait
        ))

        // Unknown orientation value never matches (fail-safe)
        XCTAssertFalse(ResponsiveEvaluator.matchesConstraint(ResponsiveConstraint(orientation: "sideways"), in: ipadPortrait))
    }

    func testResponsiveConditionMatchesDispatch() {
        let phoneLandscape = env(h: .compact, v: .compact, width: 844, height: 390, orientation: .landscape)
        XCTAssertTrue(ResponsiveEvaluator.matches(.bucket("landscape"), in: phoneLandscape))
        XCTAssertFalse(ResponsiveEvaluator.matches(.bucket("regular"), in: phoneLandscape))
        XCTAssertTrue(ResponsiveEvaluator.matches(
            .constraint(ResponsiveConstraint(minWidth: 800, orientation: "landscape")),
            in: phoneLandscape
        ))
        XCTAssertFalse(ResponsiveEvaluator.matches(
            .constraint(ResponsiveConstraint(minWidth: 900)),
            in: phoneLandscape
        ))
    }

    func testDeriveOrientation() {
        XCTAssertEqual(ResponsiveEvaluator.deriveOrientation(width: 390, height: 844), .portrait)
        XCTAssertEqual(ResponsiveEvaluator.deriveOrientation(width: 844, height: 390), .landscape)
        // Square counts as landscape (matches the web driver)
        XCTAssertEqual(ResponsiveEvaluator.deriveOrientation(width: 500, height: 500), .landscape)
    }

    func testDeriveSizeClasses() {
        // iPad: regular/regular in both orientations (fullscreen)
        XCTAssertEqual(
            ResponsiveEvaluator.deriveSizeClasses(idiom: .pad, orientation: .portrait, width: 820, height: 1180).horizontal,
            .regular
        )
        let padLandscape = ResponsiveEvaluator.deriveSizeClasses(idiom: .pad, orientation: .landscape, width: 1180, height: 820)
        XCTAssertEqual(padLandscape.horizontal, .regular)
        XCTAssertEqual(padLandscape.vertical, .regular)

        // iPhone portrait: compact/regular
        let phonePortrait = ResponsiveEvaluator.deriveSizeClasses(idiom: .phone, orientation: .portrait, width: 430, height: 932)
        XCTAssertEqual(phonePortrait.horizontal, .compact)
        XCTAssertEqual(phonePortrait.vertical, .regular)

        // Small iPhone landscape: compact/compact
        let smallLandscape = ResponsiveEvaluator.deriveSizeClasses(idiom: .phone, orientation: .landscape, width: 852, height: 393)
        XCTAssertEqual(smallLandscape.horizontal, .compact)
        XCTAssertEqual(smallLandscape.vertical, .compact)

        // Max-class iPhone landscape: regular/compact
        let maxLandscape = ResponsiveEvaluator.deriveSizeClasses(idiom: .phone, orientation: .landscape, width: 932, height: 430)
        XCTAssertEqual(maxLandscape.horizontal, .regular)
        XCTAssertEqual(maxLandscape.vertical, .compact)

        // Unknown idiom: unspecified -> all size-class buckets fail-safe skip
        let other = ResponsiveEvaluator.deriveSizeClasses(idiom: .other, orientation: .portrait, width: 800, height: 600)
        XCTAssertEqual(other.horizontal, .unspecified)
        XCTAssertEqual(other.vertical, .unspecified)
    }

    #if canImport(UIKit)
    /// Smoke test for the size-class source decision (see ResponsiveRuntime).
    ///
    /// Empirical result on the simulator (iPad (A16), iOS 26.5): in the test
    /// process, `UIScreen.main.traitCollection` returns `.unspecified` for
    /// BOTH size classes — it is NOT a usable source outside a UIKit app's
    /// own trait environment. That observation is why the runtime derives
    /// size classes from idiom + orientation + window frame instead. This
    /// test pins the two halves of that decision:
    /// - the derivation always resolves (never .unspecified) on phone/pad;
    /// - if a future host process DOES resolve screen traits, they must agree
    ///   with the derivation table (guards the table against drift).
    func testScreenTraitCollectionSmoke() throws {
        let idiom: DeviceIdiom
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: idiom = .phone
        case .pad: idiom = .pad
        default: throw XCTSkip("size-class table only modeled for phone/pad idioms")
        }

        let bounds = UIScreen.main.bounds
        let orientation = ResponsiveEvaluator.deriveOrientation(
            width: Double(bounds.width),
            height: Double(bounds.height)
        )
        let derived = ResponsiveEvaluator.deriveSizeClasses(
            idiom: idiom,
            orientation: orientation,
            width: Double(bounds.width),
            height: Double(bounds.height)
        )

        // The derivation must always resolve on phone/pad idioms — this is
        // what makes named-bucket gating usable at all from the runner process.
        XCTAssertNotEqual(derived.horizontal, .unspecified)
        XCTAssertNotEqual(derived.vertical, .unspecified)

        // Where the process's screen traits DO resolve, they must agree with
        // the derivation table. (Observed .unspecified in the SwiftPM test
        // host — the cross-check is then vacuous, which is itself the
        // documented justification for not using UIScreen as the source.)
        func toValue(_ sizeClass: UIUserInterfaceSizeClass) -> SizeClassValue? {
            switch sizeClass {
            case .compact: return .compact
            case .regular: return .regular
            default: return nil
            }
        }
        let traits = UIScreen.main.traitCollection
        if let horizontal = toValue(traits.horizontalSizeClass) {
            XCTAssertEqual(derived.horizontal, horizontal)
        }
        if let vertical = toValue(traits.verticalSizeClass) {
            XCTAssertEqual(derived.vertical, vertical)
        }
    }
    #endif

    // MARK: - Results skipReason emission

    func testResultsWriterEmitsSkipReason() throws {
        let run = TestRunResult(
            testName: "Suite",
            caseResults: [
                TestCaseResult(name: "platform gated", passed: true, duration: 0, skipped: true, skipReason: .platform),
                TestCaseResult(name: "responsive gated", passed: true, duration: 0, skipped: true, skipReason: .responsive),
                TestCaseResult(name: "plain skip", passed: true, duration: 0, skipped: true),
                TestCaseResult(name: "ran", passed: true, duration: 0.5)
            ],
            totalDuration: 0.5
        )

        let payload = ResultsWriter.resultsJSON([run], platform: "ios")
        let suites = payload["suites"] as? [[String: Any]]
        let results = suites?.first?["results"] as? [[String: Any]]
        XCTAssertEqual(results?.count, 4)

        XCTAssertEqual(results?[0]["status"] as? String, "skipped")
        XCTAssertEqual(results?[0]["skipReason"] as? String, "platform")
        XCTAssertEqual(results?[1]["status"] as? String, "skipped")
        XCTAssertEqual(results?[1]["skipReason"] as? String, "responsive")
        // Plain `skip: true` carries no reason
        XCTAssertEqual(results?[2]["status"] as? String, "skipped")
        XCTAssertNil(results?[2]["skipReason"])
        XCTAssertEqual(results?[3]["status"] as? String, "passed")
        XCTAssertNil(results?[3]["skipReason"])
    }

    func testArgsSubstitutionFlowOverridesScreenDefaults() throws {
        let json = """
        {
            "name": "Override Case",
            "args": { "userName": "default" },
            "steps": [
                { "assert": "text", "id": "greeting", "equals": "Hi @{userName}" }
            ]
        }
        """.data(using: .utf8)!

        let testCase = try JSONDecoder().decode(TestCase.self, from: json)
        let loader = TestLoader()
        let substituted = loader.applyArgsSubstitution(
            to: testCase,
            flowArgs: ["userName": AnyCodable("bob")]
        )

        XCTAssertEqual(substituted.steps[0].equals?.stringValue, "Hi bob")
    }

    // MARK: - addMedia helpers

    func testMediaResourceTypeMatrix() {
        // Same matrix as the Android driver: png/jpg/jpeg/gif photo, mp4 video.
        XCTAssertEqual(XCUITestActionExecutor.mediaResourceType(forExtension: "png"), .photo)
        XCTAssertEqual(XCUITestActionExecutor.mediaResourceType(forExtension: "JPG"), .photo)
        XCTAssertEqual(XCUITestActionExecutor.mediaResourceType(forExtension: "jpeg"), .photo)
        XCTAssertEqual(XCUITestActionExecutor.mediaResourceType(forExtension: "gif"), .photo)
        XCTAssertEqual(XCUITestActionExecutor.mediaResourceType(forExtension: "mp4"), .video)
        XCTAssertNil(XCUITestActionExecutor.mediaResourceType(forExtension: "pdf"))
        XCTAssertNil(XCUITestActionExecutor.mediaResourceType(forExtension: ""))
    }

    func testResolveMediaURLFlattensToBasename() throws {
        // A directory acts as a resource bundle root; media installed by the
        // CLI is flattened there, so "fixtures/red.png" must fall back to
        // the basename "red.png" at the bundle root.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-resolve-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("red.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        guard let bundle = Bundle(url: dir) else {
            return XCTFail("could not open temp dir as a bundle")
        }

        let executor = XCUITestActionExecutor()
        XCTAssertEqual(try executor.resolveMediaURL(path: "red.png", bundle: bundle).lastPathComponent, "red.png")
        XCTAssertEqual(try executor.resolveMediaURL(path: "fixtures/red.png", bundle: bundle).lastPathComponent, "red.png")
        XCTAssertEqual(try executor.resolveMediaURL(path: file.path, bundle: bundle).path, file.path)
        XCTAssertThrowsError(try executor.resolveMediaURL(path: "missing.png", bundle: bundle))
        XCTAssertThrowsError(try executor.resolveMediaURL(path: "/nonexistent/abs.png", bundle: bundle))

        // media/ subdir (CLI install layout under a preserved folder reference)
        let mediaDir = dir.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: mediaDir.appendingPathComponent("anim.gif"))
        XCTAssertEqual(
            try executor.resolveMediaURL(path: "anim.gif", bundle: bundle).path,
            mediaDir.appendingPathComponent("anim.gif").path
        )
    }
}
