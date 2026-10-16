import Foundation

/// A screen's canonical id (jsonui-cli `shared/core/screen_identity.json`):
/// the layout file's basename without `.json`, verbatim, a size-class
/// variant removed (`home@regular` -> `home`).
public enum ScreenIdentity {
    static let variantClasses: Set<String> = ["compact", "medium", "regular"]

    public static func screenId(layoutPath: String) -> String {
        var base = (layoutPath as NSString).lastPathComponent
        if base.hasSuffix(".json") { base = String(base.dropLast(".json".count)) }
        if let at = base.lastIndex(of: "@"), variantClasses.contains(String(base[base.index(after: at)...])) {
            base = String(base[..<at])
        }
        return base
    }
}

/// Which launches a test file makes and what each carries (spec §10.2),
/// decided before anything runs. Pure, so the shared vector
/// `specs/vectors/initial-state-payload.json` drives it directly, and the
/// runner follows it rather than deciding the same things a second time.
public struct InitialStatePlan {
    public enum Before: Equatable {
        /// Once, before the first case (a screen test under `shared`, a flow).
        case file
        /// Before this case (`reopen`).
        case testCase(String)
    }

    public struct Launch {
        public let before: Before
        /// The payload's `screens`, or nil when this launch carries none.
        public let screens: [String: [String: Any]]?
    }

    public struct CaseFailure: Equatable {
        public let caseName: String
        public let code: String
    }

    public struct Warning: Equatable {
        public let code: String
        public let file: String
        public let caseName: String?
    }

    public static let caseNeedsReopen = "case-initial-state-needs-reopen"
    public static let referencedIgnored = "referenced-initial-state-ignored"

    public var launches: [Launch] = []
    public var caseFailures: [CaseFailure] = []
    public var warnings: [Warning] = []

    /// The values of an initialState, nil when there are none: an empty
    /// object is the same as no initialState.
    static func values(_ state: InitialState?) -> [String: Any]? {
        guard let entries = state?.viewModel, !entries.isEmpty else { return nil }
        return entries.mapValues { $0.value }
    }

    /// The file's values with the case's over them, key by key. Shallow: a
    /// case's value replaces the file's whole (objects too), and a case's
    /// null is a value that replaces it.
    static func merged(file: [String: Any]?, testCase: [String: Any]?) -> [String: Any]? {
        var merged = file ?? [:]
        for (key, value) in testCase ?? [:] { merged[key] = value }
        return merged.isEmpty ? nil : merged
    }

    public static func plan(screenTest: ScreenTest) -> InitialStatePlan {
        var plan = InitialStatePlan()
        let screenId = ScreenIdentity.screenId(layoutPath: screenTest.source.layout)
        let fileValues = values(screenTest.initialState)
        let reopen = (screenTest.caseIsolation ?? .shared) == .reopen

        if reopen {
            // Every case that runs opens afresh; a gated one opens nothing.
            for testCase in screenTest.cases where testCase.skip != true {
                let screens = merged(file: fileValues, testCase: values(testCase.initialState))
                    .map { [screenId: $0] }
                plan.launches.append(Launch(before: .testCase(testCase.name), screens: screens))
            }
            return plan
        }

        if screenTest.launch != nil || screenTest.mocks != nil || fileValues != nil {
            plan.launches.append(Launch(before: .file, screens: fileValues.map { [screenId: $0] }))
        }
        // Under shared the screen opens once, before the first case: a case's
        // own initialState has no launch to ride.
        for testCase in screenTest.cases where testCase.skip != true && values(testCase.initialState) != nil {
            plan.caseFailures.append(CaseFailure(caseName: testCase.name, code: caseNeedsReopen))
        }
        return plan
    }

    /// `referenced` resolves a file step's `file` to its screen test (nil when
    /// it cannot be loaded — the step itself reports that when it runs).
    public static func plan(flowTest: FlowTest, referenced: (String) -> ScreenTest?) -> InitialStatePlan {
        var plan = InitialStatePlan()
        let viewModels = (flowTest.initialState?.viewModels ?? [:])
            .compactMapValues { $0.isEmpty ? nil : $0.mapValues { $0.value } }
        let screens = viewModels.isEmpty ? nil : viewModels
        if flowTest.launch != nil || flowTest.mocks != nil || screens != nil {
            plan.launches.append(Launch(before: .file, screens: screens))
        }
        for step in flowTest.steps where step.isFileReference {
            guard let file = step.file, let screenTest = referenced(file) else { continue }
            plan.warnings.append(contentsOf: referencedWarnings(step: step, file: file, screenTest: screenTest))
        }
        return plan
    }

    /// A flow runs a referenced file / case without its initialState — the
    /// flow's one launch has already happened.
    static func referencedWarnings(step: FlowTestStep, file: String, screenTest: ScreenTest) -> [Warning] {
        var warnings: [Warning] = []
        if values(screenTest.initialState) != nil {
            warnings.append(Warning(code: referencedIgnored, file: file, caseName: nil))
        }
        let names: [String]
        if let one = step.case { names = [one] }
        else if let some = step.cases, !some.isEmpty { names = some }
        else { names = screenTest.cases.map(\.name) }
        for name in names {
            guard let testCase = screenTest.cases.first(where: { $0.name == name }),
                  values(testCase.initialState) != nil else { continue }
            warnings.append(Warning(code: referencedIgnored, file: file, caseName: name))
        }
        return warnings
    }

    /// The message a warning prints.
    public static func message(_ warning: Warning) -> String {
        let target = warning.caseName.map { "case '\($0)' of '\(warning.file)'" } ?? "'\(warning.file)'"
        return "initialState of \(target) is not applied inside a flow: the flow's launch has already happened (\(warning.code)). Put the values in the flow's initialState.viewModels."
    }
}

/// The `JSONUI_TEST_INITIAL_STATE` value (spec §10.2).
public enum InitialStatePayload {
    public static func encode(screens: [String: [String: Any]], launchId: String) -> String? {
        let root: [String: Any] = ["version": 1, "launchId": launchId, "screens": screens]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
