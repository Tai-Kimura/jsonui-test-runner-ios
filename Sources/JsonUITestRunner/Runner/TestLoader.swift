import Foundation

/// Errors that can occur during test loading
public enum TestLoaderError: Error, LocalizedError {
    case fileNotFound(path: String)
    case invalidJSON(path: String, error: String)
    case unsupportedTestType(type: String)
    case bundleResourceNotFound(name: String)

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

    public init() {
        decoder = JSONDecoder()
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
