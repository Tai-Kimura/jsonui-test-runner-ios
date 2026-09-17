import XCTest
@testable import JsonUITestRunner

/// File-reference resolution in a flow: the base the references resolve
/// against is the FLOW file's directory, and reading a referenced screen
/// test must not move it.
///
/// Before the fix, `load(from:)` set `basePath` unconditionally, so the first
/// `file:` reference moved the base to `screens/<first>/` and the second
/// reference (a different screen) looked under `screens/screens/<second>/`
/// and was "not found". Referencing the SAME screen twice passed by accident
/// (`<base>/<ref>.test.json` happened to exist), which is why the defect
/// stayed invisible until a flow crossed two screens. Same shape in the web
/// and Android drivers (one ticket, three faces).
///
/// `basePath` has no getter here, so the invariant is observed through a
/// reference that ONLY resolves from the flow directory (`gamma` lives in
/// tests/flows/, beside the flow): it is found while the base is the flow's
/// directory and not found once the base has moved to a screen's.
final class TestLoaderFileReferenceBaseTests: XCTestCase {

    private var root: URL!
    private var flowURL: URL!
    private var alphaURL: URL!

    private func screenTest(_ name: String) -> String {
        """
        {"type":"screen","source":{"layout":"layouts/\(name).json"},
         "metadata":{"name":"\(name)"},
         "cases":[{"name":"initial_display","steps":[]}]}
        """
    }

    private func flowTest() -> String {
        """
        {"type":"flow","metadata":{"name":"two screens"},
         "steps":[{"file":"alpha","case":"initial_display"},
                  {"file":"beta","case":"initial_display"}]}
        """
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jtr-basepath-\(UUID().uuidString)")
        let flows = root.appendingPathComponent("tests/flows")
        let alpha = root.appendingPathComponent("tests/screens/alpha")
        let beta = root.appendingPathComponent("tests/screens/beta")
        for dir in [flows, alpha, beta] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        flowURL = flows.appendingPathComponent("two.test.json")
        alphaURL = alpha.appendingPathComponent("alpha.test.json")
        try flowTest().write(to: flowURL, atomically: true, encoding: .utf8)
        try screenTest("alpha").write(to: alphaURL, atomically: true, encoding: .utf8)
        try screenTest("beta").write(to: beta.appendingPathComponent("beta.test.json"), atomically: true, encoding: .utf8)
        // Resolvable ONLY while the base is the flow directory.
        try screenTest("gamma").write(to: flows.appendingPathComponent("gamma.test.json"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // The reported shape: two DIFFERENT screens, in either order.
    func testResolvesASecondDifferentScreenAfterTheFirstWasRead() throws {
        let loader = TestLoader()
        loader.setBasePath(flowURL)
        XCTAssertEqual(try loader.resolveFileReference("alpha").metadata.name, "alpha")
        XCTAssertEqual(try loader.resolveFileReference("beta").metadata.name, "beta")

        let reversed = TestLoader()
        reversed.setBasePath(flowURL)
        XCTAssertEqual(try reversed.resolveFileReference("beta").metadata.name, "beta")
        XCTAssertEqual(try reversed.resolveFileReference("alpha").metadata.name, "alpha")
    }

    // The form that passed before the fix — by accident — has to keep passing.
    func testStillResolvesTheSameScreenReferencedTwice() throws {
        let loader = TestLoader()
        loader.setBasePath(flowURL)
        XCTAssertEqual(try loader.resolveFileReference("alpha").metadata.name, "alpha")
        XCTAssertEqual(try loader.resolveFileReference("alpha").metadata.name, "alpha")
    }

    // The invariant itself: reading a reference is not a load, so a reference
    // that only resolves from the flow directory still resolves afterwards.
    func testLeavesTheBaseAtTheFlowDirectoryAfterResolvingAReference() throws {
        let loader = TestLoader()
        loader.setBasePath(flowURL)
        _ = try loader.resolveFileReference("alpha")
        XCTAssertEqual(try loader.resolveFileReference("gamma").metadata.name, "gamma")
    }

    // The step-level entry the runner actually calls.
    func testResolvesEveryFileStepOfATwoScreenFlowThroughResolveFileReferenceCases() throws {
        let loader = TestLoader()
        loader.setBasePath(flowURL)
        guard case .flow(let flow) = try loader.load(from: flowURL) else {
            return XCTFail("fixture is a flow")
        }
        let names = try flow.steps.flatMap { try loader.resolveFileReferenceCases($0).map(\.name) }
        XCTAssertEqual(names, ["initial_display", "initial_display"])
    }

    // Negative control: the resolver still refuses to guess a base.
    func testRefusesToResolveWhenNoBaseHasBeenSet() {
        XCTAssertThrowsError(try TestLoader().resolveFileReference("alpha")) { error in
            guard case TestLoaderError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    // A TOP-LEVEL load still owns the base — a screen test run on its own
    // resolves against its own directory, so the flow-only reference is gone.
    func testMovesTheBaseOnATopLevelLoad() throws {
        let loader = TestLoader()
        loader.setBasePath(flowURL)
        _ = try loader.load(from: alphaURL)
        XCTAssertThrowsError(try loader.resolveFileReference("gamma"))
    }
}
