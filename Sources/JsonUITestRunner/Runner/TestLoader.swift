import Foundation

/// Errors that can occur during test loading
public enum TestLoaderError: Error, LocalizedError {
    case fileNotFound(path: String)
    case invalidJSON(path: String, error: String)
    case unsupportedTestType(type: String)
    case bundleResourceNotFound(name: String)
    case caseNotFound(caseName: String, file: String)
    case notAScreenTest(file: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Test file not found: \(path)"
        case .invalidJSON(let path, let error):
            return "Invalid JSON in \(path): \(error)"
        case .unsupportedTestType(let type):
            return "Unsupported test type: \(type)"
        case .bundleResourceNotFound(let name):
            return "Resource not found in bundle: \(name)"
        case .caseNotFound(let caseName, let file):
            return "Test case '\(caseName)' not found in file: \(file)"
        case .notAScreenTest(let file):
            return "File reference must point to a screen test: \(file)"
        }
    }
}

/// Represents loaded test content
public enum LoadedTest {
    case screen(ScreenTest)
    case flow(FlowTest)

    public var name: String {
        switch self {
        case .screen(let test):
            return test.metadata.name
        case .flow(let test):
            return test.metadata.name
        }
    }
}

/// Loads test JSON files
public class TestLoader {

    private let decoder: JSONDecoder
    private var basePath: URL?

    public init() {
        decoder = JSONDecoder()
    }

    /// Set base path for resolving relative file references
    public func setBasePath(_ url: URL) {
        basePath = url.deletingLastPathComponent()
    }

    /// Load a test from a file path
    public func load(from path: String) throws -> LoadedTest {
        let url = URL(fileURLWithPath: path)
        return try load(from: url)
    }

    /// Load a test from a URL
    public func load(from url: URL) throws -> LoadedTest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestLoaderError.fileNotFound(path: url.path)
        }

        // Store base path for file reference resolution
        basePath = url.deletingLastPathComponent()

        do {
            let data = try Data(contentsOf: url)
            return try parse(data: data, sourcePath: url.path)
        } catch let error as DecodingError {
            throw TestLoaderError.invalidJSON(path: url.path, error: error.localizedDescription)
        }
    }

    /// Load a test from bundle resources
    public func loadFromBundle(name: String, bundle: Bundle = .main) throws -> LoadedTest {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw TestLoaderError.bundleResourceNotFound(name: name)
        }

        return try load(from: url)
    }

    /// Load all tests from a directory
    public func loadAll(from directory: String) throws -> [LoadedTest] {
        let url = URL(fileURLWithPath: directory)
        return try loadAll(from: url)
    }

    /// Load all tests from a directory URL
    public func loadAll(from directory: URL) throws -> [LoadedTest] {
        var tests: [LoadedTest] = []

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return tests
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension == "json" && fileURL.lastPathComponent.contains(".test.") {
                do {
                    let test = try load(from: fileURL)
                    tests.append(test)
                } catch {
                    print("Warning: Failed to load \(fileURL.path): \(error.localizedDescription)")
                }
            }
        }

        return tests
    }

    /// Load all tests from bundle
    public func loadAllFromBundle(bundle: Bundle = .main) throws -> [LoadedTest] {
        guard let resourcePath = bundle.resourcePath else {
            return []
        }

        let resourceURL = URL(fileURLWithPath: resourcePath)
        return try loadAll(from: resourceURL)
    }

    // MARK: - Private Methods

    private func parse(data: Data, sourcePath: String) throws -> LoadedTest {
        // First, determine the test type
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            throw TestLoaderError.invalidJSON(path: sourcePath, error: "Missing 'type' field")
        }

        switch type {
        case "screen":
            let screenTest = try decoder.decode(ScreenTest.self, from: data)
            return .screen(screenTest)
        case "flow":
            let flowTest = try decoder.decode(FlowTest.self, from: data)
            return .flow(flowTest)
        default:
            throw TestLoaderError.unsupportedTestType(type: type)
        }
    }
}

// MARK: - Test Filtering

extension TestLoader {

    /// Filter tests by platform
    public func filter(tests: [LoadedTest], for platform: String) -> [LoadedTest] {
        return tests.filter { test in
            switch test {
            case .screen(let screenTest):
                if let platformTarget = screenTest.platform {
                    return platformTarget.includes(platform)
                }
                return true
            case .flow(let flowTest):
                if let platformTarget = flowTest.platform {
                    return platformTarget.includes(platform)
                }
                return true
            }
        }
    }

    /// Filter tests by tags
    public func filter(tests: [LoadedTest], withTags tags: [String]) -> [LoadedTest] {
        return tests.filter { test in
            let testTags: [String]?
            switch test {
            case .screen(let screenTest):
                testTags = screenTest.metadata.tags
            case .flow(let flowTest):
                testTags = flowTest.metadata.tags
            }

            guard let existingTags = testTags else {
                return false
            }

            return !Set(tags).isDisjoint(with: Set(existingTags))
        }
    }
}

// MARK: - File Reference Resolution

extension TestLoader {

    /// Resolve a file reference to a ScreenTest
    public func resolveFileReference(_ fileRef: String) throws -> ScreenTest {
        let url = try resolveFileReferenceURL(fileRef)
        let loadedTest = try load(from: url)

        guard case .screen(let screenTest) = loadedTest else {
            throw TestLoaderError.notAScreenTest(file: fileRef)
        }

        return screenTest
    }

    /// Resolve a file reference to test cases with args substitution
    public func resolveFileReferenceCases(_ step: FlowTestStep) throws -> [TestCase] {
        guard let fileRef = step.file else {
            return []
        }

        let screenTest = try resolveFileReference(fileRef)
        let flowArgs = step.args ?? [:]

        // If specific case is requested
        if let caseName = step.case {
            guard let testCase = screenTest.cases.first(where: { $0.name == caseName }) else {
                throw TestLoaderError.caseNotFound(caseName: caseName, file: fileRef)
            }
            return [applyArgsSubstitution(to: testCase, flowArgs: flowArgs)]
        }

        // If specific cases are requested
        if let caseNames = step.cases, !caseNames.isEmpty {
            var result: [TestCase] = []
            for caseName in caseNames {
                guard let testCase = screenTest.cases.first(where: { $0.name == caseName }) else {
                    throw TestLoaderError.caseNotFound(caseName: caseName, file: fileRef)
                }
                result.append(applyArgsSubstitution(to: testCase, flowArgs: flowArgs))
            }
            return result
        }

        // Return all cases if no specific case requested
        return screenTest.cases.map { applyArgsSubstitution(to: $0, flowArgs: flowArgs) }
    }

    /// Apply args substitution to a test case
    /// Merges screen default args with flow override args, then substitutes @{varName} placeholders
    public func applyArgsSubstitution(to testCase: TestCase, flowArgs: [String: AnyCodable] = [:]) -> TestCase {
        // Merge screen default args with flow override args
        var mergedArgs: [String: Any] = [:]
        if let screenArgs = testCase.args {
            for (key, value) in screenArgs {
                mergedArgs[key] = value.value
            }
        }
        for (key, value) in flowArgs {
            mergedArgs[key] = value.value
        }

        // If no args, return original test case
        if mergedArgs.isEmpty {
            return testCase
        }

        // Apply substitution to steps
        let substitutedSteps = testCase.steps.map { substituteArgs(in: $0, args: mergedArgs) }

        // Create new TestCase with substituted steps
        return TestCase(
            name: testCase.name,
            description: testCase.description,
            skip: testCase.skip,
            platform: testCase.platform,
            responsive: testCase.responsive,
            initialState: testCase.initialState,
            steps: substitutedSteps,
            args: testCase.args
        )
    }

    /// Substitute @{varName} placeholders in a TestStep, preserving ALL other
    /// fields (dropping e.g. `when` here would silently disable a step's
    /// platform/responsive gate on args-substituted referenced cases).
    /// Nested control-step `steps` are substituted recursively.
    private func substituteArgs(in step: TestStep, args: [String: Any]) -> TestStep {
        return TestStep(
            action: step.action,
            assert: step.assert,
            id: substituteArgsInOptionalString(step.id, args: args),
            ids: step.ids?.map { substituteArgsInString($0, args: args) },
            text: substituteArgsInOptionalString(step.text, args: args),
            value: substituteArgsInOptionalString(step.value, args: args),
            direction: step.direction,
            duration: step.duration,
            timeout: step.timeout,
            ms: step.ms,
            name: step.name,
            equals: substituteArgsInAnyCodable(step.equals, args: args),
            contains: substituteArgsInOptionalString(step.contains, args: args),
            path: step.path,
            amount: step.amount,
            button: substituteArgsInOptionalString(step.button, args: args),
            label: substituteArgsInOptionalString(step.label, args: args),
            index: step.index,
            optional: step.optional,
            when: step.when,
            retryTapIfNoChange: step.retryTapIfNoChange,
            container: substituteArgsInOptionalString(step.container, args: args),
            variable: step.variable,
            times: step.times,
            while: step.while,
            steps: step.steps?.map { substituteArgs(in: $0, args: args) },
            maxRetries: step.maxRetries,
            latitude: step.latitude,
            longitude: step.longitude,
            paths: step.paths,
            cropId: substituteArgsInOptionalString(step.cropId, args: args),
            threshold: step.threshold,
            mocks: step.mocks,
            orientation: step.orientation
        )
    }

    /// Substitute @{varName} placeholders in an optional string
    private func substituteArgsInOptionalString(_ string: String?, args: [String: Any]) -> String? {
        guard let string = string else { return nil }
        return substituteArgsInString(string, args: args)
    }

    /// Substitute @{varName} placeholders in a string
    private func substituteArgsInString(_ string: String, args: [String: Any]) -> String {
        var result = string
        // Pattern: @{varName}
        let pattern = #"@\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return string
        }

        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = regex.matches(in: string, range: range)

        // Replace from end to start to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let varNameRange = Range(match.range(at: 1), in: result) else {
                continue
            }

            let varName = String(result[varNameRange])
            if let value = args[varName] {
                let replacement = stringValue(from: value)
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        return result
    }

    /// Substitute @{varName} placeholders in AnyCodable (only for string values)
    private func substituteArgsInAnyCodable(_ anyCodable: AnyCodable?, args: [String: Any]) -> AnyCodable? {
        guard let anyCodable = anyCodable else { return nil }
        if let stringValue = anyCodable.stringValue {
            let substituted = substituteArgsInString(stringValue, args: args)
            return AnyCodable(substituted)
        }
        return anyCodable
    }

    /// Convert Any value to String for substitution
    private func stringValue(from value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let bool as Bool:
            return String(bool)
        default:
            return String(describing: value)
        }
    }

    /// Resolve a file reference path to a URL
    private func resolveFileReferenceURL(_ fileRef: String) throws -> URL {
        guard let base = basePath else {
            throw TestLoaderError.fileNotFound(path: fileRef)
        }

        // Parent of basePath (e.g., tests/ when basePath is tests/flows/)
        let parentBase = base.deletingLastPathComponent()

        // Try different locations and file extensions
        // Priority: ../screens/ (sibling directory) first, then same directory
        let candidates = [
            parentBase.appendingPathComponent("screens/\(fileRef)/\(fileRef).test.json"),
            parentBase.appendingPathComponent("screens/\(fileRef)/\(fileRef).json"),
            parentBase.appendingPathComponent("screens/\(fileRef).test.json"),
            parentBase.appendingPathComponent("screens/\(fileRef).json"),
            base.appendingPathComponent("\(fileRef).test.json"),
            base.appendingPathComponent("\(fileRef).json"),
            base.appendingPathComponent(fileRef)
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw TestLoaderError.fileNotFound(path: fileRef)
    }
}
