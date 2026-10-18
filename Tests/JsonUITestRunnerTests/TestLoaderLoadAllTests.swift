import XCTest
@testable import JsonUITestRunner

/// `loadAll(from:)` tries every matching file and, when any of them cannot be
/// loaded, throws ONE error naming every failed path. It used to print a
/// warning and skip the file, so a broken test file left the run silently.
final class TestLoaderLoadAllTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loadAll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ body: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: url)
        return url
    }

    private func screen(_ name: String) -> String {
        """
        { "type": "screen", "source": { "layout": "layouts/x.json" },
          "metadata": { "name": "\(name)" },
          "cases": [ { "name": "c", "steps": [ { "action": "wait", "ms": 1 } ] } ] }
        """
    }

    func testEveryBrokenFileIsNamedInOneError() throws {
        _ = try write("good.test.json", screen("good"))
        let notJSON = try write("broken.test.json", "{ this is not json")
        let badType = try write("nested/odd.test.json", #"{ "type": "nope" }"#)

        XCTAssertThrowsError(try TestLoader().loadAll(from: dir)) { error in
            guard case TestLoaderError.unreadableFiles(let failures) = error else {
                return XCTFail("expected unreadableFiles, got \(error)")
            }
            XCTAssertEqual(
                Set(failures.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }),
                Set([notJSON, badType].map { $0.resolvingSymlinksInPath().path })
            )
            XCTAssertTrue(failures.allSatisfy { !$0.reason.isEmpty })
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("broken.test.json"), text)
            XCTAssertTrue(text.contains("odd.test.json"), text)
            XCTAssertTrue(text.contains("Unsupported test type: nope"), text)
            XCTAssertFalse(text.contains("good.test.json"), text)
        }
    }

    func testACleanDirectoryReturnsEveryTest() throws {
        _ = try write("a.test.json", screen("a"))
        _ = try write("sub/b.test.json", screen("b"))
        _ = try write("ignored.json", "{ not a test file, not matched")

        let tests = try TestLoader().loadAll(from: dir)
        XCTAssertEqual(Set(tests.map(\.name)), ["a", "b"])
    }
}
