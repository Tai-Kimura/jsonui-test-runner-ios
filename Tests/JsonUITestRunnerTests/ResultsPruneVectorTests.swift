import XCTest
@testable import JsonUITestRunner

/// The latest result of every test file stays (2.3.1; measured by 35: rerunning one file 500 times left 1 of 122
/// files with its latest). Fixtures/results-prune.json is a byte copy of jsonui-test-runner
/// specs/vectors/results-prune.json, the rule the three drivers and jui viz share.
final class ResultsPruneVectorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_792_314_000)
    private let day: TimeInterval = 86_400

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "results-prune", withExtension: "json", subdirectory: "Fixtures"))
    }

    private func id(_ i: Int) -> String { String(format: "%08x-0000-4000-8000-%012x", i, i) }
    private func file(_ i: Int) -> String { "tests/screens/s\(i).test.json" }
    private func at(_ offset: TimeInterval, _ i: Int, _ f: String) -> String {
        DefaultResults.fileName(date: now.addingTimeInterval(offset), run: id(i), fileKey8: DefaultResults.fileKey([f]))
    }
    private func latestPerFile(_ names: [String]) -> Int { Set(names.compactMap { DefaultResults.fileKey(ofName: $0) }).count }

    func testTheSharedVectorFileKeysAndEveryPruneCase() throws {
        let vector = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture())) as? [String: Any])
        for k in try XCTUnwrap(vector["fileKeys"] as? [[String: Any]]) {
            let key = try XCTUnwrap(k["key"] as? String)
            XCTAssertEqual(DefaultResults.fileKey(key.components(separatedBy: "\n")), k["fileKey8"] as? String, key)
        }
        let cases = try XCTUnwrap(vector["prune"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 5)
        for c in cases {
            let names = try XCTUnwrap(c["names"] as? [String])
            let nowMs = try XCTUnwrap(c["now"] as? NSNumber).doubleValue
            let got = DefaultResults.namesToPrune(names, now: Date(timeIntervalSince1970: nowMs / 1000),
                                                  maxFiles: try XCTUnwrap(c["maxFiles"] as? Int),
                                                  maxAgeDays: try XCTUnwrap(c["maxAgeDays"] as? Int))
            XCTAssertEqual(got, c["pruned"] as? [String], c["name"] as? String ?? "")
        }
    }

    func test122FilesThenOneRerun500TimesTheOtherKeepTheirLatest() {
        var names = (0..<122).map { at(-day + Double($0) / 1000, $0, file($0)) }
        names += (0..<500).map { at(-day / 2 + Double($0), 1000 + $0, file(0)) }
        let doomed = Set(DefaultResults.namesToPrune(names, now: now))
        let left = names.filter { !doomed.contains($0) }
        XCTAssertEqual(left.count, DefaultResults.maxFiles)
        XCTAssertEqual(latestPerFile(left), 122)
        XCTAssertTrue(left.contains(names.last!))
    }

    func testOneRoundOf600FilesPrunesNoneOfThem() {
        let names = (0..<600).map { at(-60 + Double($0) / 1000, $0, file($0)) }
        XCTAssertEqual(DefaultResults.namesToPrune(names, now: now), [])
    }

    func testAFileNotRunFor20DaysKeepsItsResultItsReplacedOlderOneGoes() {
        let only = at(-20 * day, 1, file(1))
        let replaced = at(-20 * day, 2, file(2))
        let latest = at(-1, 3, file(2))
        XCTAssertEqual(DefaultResults.namesToPrune([only, replaced, latest], now: now), [replaced])
    }

    /// The copy is compared with its source when the source is at hand: $JSONUI_TEST_RUNNER_DIR, this package as
    /// jsonui-test-runner's submodule (drivers/ios), or a sibling checkout. Elsewhere (this repo's CI) it is
    /// skipped, and says so.
    func testTheVectorIsAByteCopyOfJsonUITestRunners() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            ProcessInfo.processInfo.environment["JSONUI_TEST_RUNNER_DIR"].map { URL(fileURLWithPath: $0) },
            package.deletingLastPathComponent().deletingLastPathComponent(),
            package.deletingLastPathComponent().appendingPathComponent("jsonui-test-runner"),
        ].compactMap { $0 }.map { $0.appendingPathComponent("specs/vectors/results-prune.json") }
        guard let source = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("jsonui-test-runner specs/vectors not found: the copy is not compared here")
        }
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: fixture()))
    }
}
