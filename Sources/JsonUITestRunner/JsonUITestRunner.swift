// JsonUITestRunner
// Cross-platform UI test runner for JsonUI libraries

@_exported import XCTest

/// Public API entry point
public enum JsonUITest {

    /// Load a test from a file path
    public static func load(from path: String) throws -> LoadedTest {
        let loader = TestLoader()
        return try loader.load(from: path)
    }

    /// Load a test from bundle resources
    public static func loadFromBundle(name: String, bundle: Bundle = .main) throws -> LoadedTest {
        let loader = TestLoader()
        return try loader.loadFromBundle(name: name, bundle: bundle)
    }

    /// Load all tests from a directory
    public static func loadAll(from directory: String) throws -> [LoadedTest] {
        let loader = TestLoader()
        return try loader.loadAll(from: directory)
    }

    /// Create a test runner
    public static func createRunner(
        app: XCUIApplication,
        config: TestRunnerConfig = TestRunnerConfig(),
        stateProvider: ViewModelStateProvider? = nil
    ) -> JsonUITestRunner {
        return JsonUITestRunner(app: app, config: config, stateProvider: stateProvider)
    }
}
