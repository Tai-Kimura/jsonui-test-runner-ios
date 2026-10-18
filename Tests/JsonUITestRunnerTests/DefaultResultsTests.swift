import XCTest
@testable import JsonUITestRunner

/// Results with no `resultsPath`: one new file per run in
/// `<base>/ios/<app>/`, named `<UTC time>-<run>.json`, pruned to 14 days and
/// 500 files (default results location spec, 2026-10-18).
///
/// Every test injects base, home, app and time through `DefaultResults.Context`
/// and writes under its own temporary folder — none touches the real HOME.
final class DefaultResultsTests: XCTestCase {

    private var root: URL!
    private var home: URL!
    private var printed: [String] = []

    /// 2026-10-18T18:17:00.123Z
    private let fixedNow = Date(timeIntervalSince1970: 1_792_347_420.123)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefaultResultsTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        printed = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func context(
        environment: [String: String]? = nil,
        isSimulator: Bool = true,
        app: String = "com.example.AppUITests.xctrunner",
        now: Date? = nil,
        files: ResultsFilePort = FileManagerResultsPort()
    ) -> DefaultResults.Context {
        let at = now ?? fixedNow
        return DefaultResults.Context(
            environment: environment ?? ["SIMULATOR_HOST_HOME": home.path],
            isSimulator: isSimulator,
            app: app,
            now: { at },
            files: files,
            notices: NoticeOnce(sink: { [weak self] in self?.printed.append($0) })
        )
    }

    private var defaultFolder: URL {
        home.appendingPathComponent(".local/state/jsonui-test/results/ios/com.example.AppUITests.xctrunner")
    }

    private func result(_ name: String = "login") -> TestRunResult {
        TestRunResult(
            testName: name,
            caseResults: [
                TestCaseResult(name: "a", passed: true, duration: 0.1),
                TestCaseResult(name: "b", passed: false, duration: 0.2)
            ],
            totalDuration: 0.3
        )
    }

    private func newRun() -> String { UUID().uuidString.lowercased() }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: 1. resultsPath unset -> a file in the default folder

    func testNoResultsPathWritesOneFileInTheDefaultFolder() throws {
        let run = newRun()
        DefaultResults.writeRun(result(), resultsPath: nil, platform: "ios", run: run,
                                file: "screens/login.test.json", context: context())

        let files = names(in: defaultFolder)
        XCTAssertEqual(files, ["20261018T181700.123Z-\(run)-\(DefaultResults.fileKey(["screens/login.test.json"])).json"],
                       "one file named by its run and its test file, no leftover .tmp")
        let only = try XCTUnwrap(files.first)
        let payload = try json(defaultFolder.appendingPathComponent(only))
        XCTAssertEqual(payload["run"] as? String, run)
        XCTAssertEqual(payload["app"] as? String, "com.example.AppUITests.xctrunner")
        XCTAssertEqual(payload["format"] as? String, "jsonui-test-results")
        XCTAssertEqual(payload["version"] as? Int, 1)
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertEqual(payload["generatedAt"] as? String, "2026-10-18T18:17:00Z")
        let suites = try XCTUnwrap(payload["suites"] as? [[String: Any]])
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0]["file"] as? String, "screens/login.test.json")
        XCTAssertEqual(suites[0]["suiteName"] as? String, "login")
        XCTAssertEqual((suites[0]["results"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(Set(payload.keys),
                       ["format", "version", "platform", "generatedAt", "suites", "run", "app"])
    }

    func testTheAppSegmentIsSanitizedButTheAppKeyIsNot() throws {
        let app = "com.example/odd app"
        let written = try XCTUnwrap(DefaultResults.writeDefault(
            result(), platform: "ios", run: newRun(), file: "inline", context: context(app: app)))
        XCTAssertEqual(written.deletingLastPathComponent().lastPathComponent, "com.example_odd_app")
        XCTAssertEqual(try json(written)["app"] as? String, app)
    }

    func testAnAbsoluteResultsDirIsTheBaseARelativeOneIsIgnored() throws {
        let explicit = root.appendingPathComponent("explicit")
        let a = try XCTUnwrap(DefaultResults.writeDefault(
            result(), platform: "ios", run: newRun(), file: "inline",
            context: context(environment: ["SIMULATOR_HOST_HOME": home.path,
                                           "JSONUI_TEST_RESULTS_DIR": explicit.path])))
        XCTAssertEqual(a.deletingLastPathComponent().path,
                       explicit.appendingPathComponent("ios/com.example.AppUITests.xctrunner").path)

        let b = try XCTUnwrap(DefaultResults.writeDefault(
            result(), platform: "ios", run: newRun(), file: "inline",
            context: context(environment: ["SIMULATOR_HOST_HOME": home.path,
                                           "JSONUI_TEST_RESULTS_DIR": "relative/dir"])))
        XCTAssertEqual(b.deletingLastPathComponent().path, defaultFolder.path)
    }

    func testNotOnASimulatorOrWithoutHostHomeNothingIsWritten() {
        XCTAssertNil(DefaultResults.writeDefault(result(), platform: "ios", run: newRun(), file: "inline",
                                                 context: context(isSimulator: false)))
        XCTAssertNil(DefaultResults.writeDefault(result(), platform: "ios", run: newRun(), file: "inline",
                                                 context: context(environment: [:])))
        XCTAssertNil(DefaultResults.writeDefault(result(), platform: "ios", run: newRun(), file: "inline",
                                                 context: context(environment: ["SIMULATOR_HOST_HOME": ""])))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".local").path))
        XCTAssertEqual(printed, [], "out of scope, not a failure")
    }

    /// Records every file operation, and performs none.
    private final class RecordingPort: ResultsFilePort {
        var calls: [String] = []
        func createDirectory(at url: URL) throws { calls.append("mkdir \(url.path)") }
        func write(_ data: Data, to url: URL) throws { calls.append("write \(url.path)") }
        func rename(_ s: URL, to d: URL) throws { calls.append("rename \(d.path)") }
        func entries(of f: URL) throws -> [String] { calls.append("ls \(f.path)"); return [] }
        func remove(_ url: URL) throws { calls.append("rm \(url.path)") }
    }

    /// Real devices are out of scope: off a simulator, nothing is written
    /// anywhere — even with a host home and an explicit results dir present —
    /// and the run is the same run. Through `writeRun`, the runner's entry.
    func testOffASimulatorTheRunnerEntryTouchesNoFile() {
        let port = RecordingPort()
        let original = result()
        DefaultResults.writeRun(
            original, resultsPath: nil, platform: "ios", run: newRun(), file: "inline",
            context: context(environment: ["SIMULATOR_HOST_HOME": home.path,
                                           "JSONUI_TEST_RESULTS_DIR": root.appendingPathComponent("explicit").path],
                             isSimulator: false, files: port))
        XCTAssertEqual(port.calls, [], "no file operation at all")
        XCTAssertEqual(printed, [], "no notice either")
        XCTAssertEqual(original.passedCount, 1)
        XCTAssertEqual(original.failedCount, 1)
        XCTAssertEqual(names(in: root), ["home"])

        // Control: the same call on a simulator does reach the port.
        DefaultResults.writeRun(
            original, resultsPath: nil, platform: "ios", run: newRun(), file: "inline",
            context: context(isSimulator: true, files: port))
        XCTAssertFalse(port.calls.isEmpty)
    }

    // MARK: 2. two runs -> two files

    func testTwoRunsWriteTwoFiles() throws {
        let first = newRun(), second = newRun()
        DefaultResults.writeRun(result("one"), resultsPath: nil, platform: "ios", run: first,
                                file: "inline", context: context())
        DefaultResults.writeRun(result("two"), resultsPath: nil, platform: "ios", run: second,
                                file: "inline", context: context())
        let files = names(in: defaultFolder)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(try files.map { try json(defaultFolder.appendingPathComponent($0))["run"] as? String }),
                       [first, second])
    }

    // MARK: 3. pruning

    /// One test file rerun: every file here is a result of "inline", so the newest 500 by name stay.
    func testPruningKeepsTheNewest500AndDropsOnlyOldMatchingFiles() throws {
        let inline = DefaultResults.fileKey(["inline"])
        let fm = FileManager.default
        try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        let sibling = defaultFolder.deletingLastPathComponent().appendingPathComponent("com.other.xctrunner")
        try fm.createDirectory(at: sibling, withIntermediateDirectories: true)

        func touch(_ folder: URL, _ name: String) {
            fm.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("{}".utf8))
        }
        // 501 recent files, one second apart before now.
        var recent: [String] = []
        for i in 1...501 {
            let name = DefaultResults.fileName(date: fixedNow.addingTimeInterval(-Double(i)), run: newRun(), fileKey8: inline)
            recent.append(name)
            touch(defaultFolder, name)
        }
        let old = DefaultResults.fileName(date: fixedNow.addingTimeInterval(-15 * 86_400), run: newRun(), fileKey8: inline)
        touch(defaultFolder, old)
        // Non-matching names that would sort oldest / look old if the
        // pattern were ignored.
        let strangers = ["00000000-notes.json",
                         "20000101T000000.000Z-not-a-uuid.json",
                         ".20000101T000000.000Z-\(newRun()).json.tmp",
                         "README.txt"]
        for name in strangers { touch(defaultFolder, name) }
        try fm.createDirectory(at: defaultFolder.appendingPathComponent("20000101T000000.000Z-\(newRun()).json"),
                               withIntermediateDirectories: false)
        let siblingOld = DefaultResults.fileName(date: fixedNow.addingTimeInterval(-30 * 86_400), run: newRun(), fileKey8: inline)
        touch(sibling, siblingOld)

        let written = try XCTUnwrap(DefaultResults.writeDefault(
            result(), platform: "ios", run: newRun(), file: "inline", context: context()))

        let after = Set(names(in: defaultFolder))
        let matching = after.filter(DefaultResults.isResultsFileName)
        XCTAssertEqual(matching.count, 500)
        XCTAssertTrue(after.contains(written.lastPathComponent))
        XCTAssertFalse(after.contains(old), "older than 14 days")
        // 501 recent + 1 new = 502 after the old one goes: the two oldest recent go.
        XCTAssertFalse(after.contains(recent[500]))
        XCTAssertFalse(after.contains(recent[499]))
        XCTAssertTrue(after.contains(recent[498]))
        for name in strangers { XCTAssertTrue(after.contains(name), "non-matching \(name) untouched") }
        XCTAssertEqual(names(in: sibling), [siblingOld], "another app's folder untouched")
    }

    // MARK: 4. resultsPath set -> old behaviour

    func testResultsPathSetKeepsTheOldFileAndWritesNoDefaultFile() throws {
        let path = root.appendingPathComponent("out/results.json")
        DefaultResults.writeRun(result(), resultsPath: path, platform: "ios", run: newRun(),
                                file: "screens/login.test.json", context: context())
        DefaultResults.writeRun(result("second"), resultsPath: path, platform: "ios", run: newRun(),
                                file: "screens/login.test.json", context: context())

        let payload = try json(path)
        XCTAssertEqual(Set(payload.keys), ["format", "version", "platform", "generatedAt", "suites"])
        let suites = try XCTUnwrap(payload["suites"] as? [[String: Any]])
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0]["suiteName"] as? String, "second", "overwritten, as before")
        XCTAssertNil(suites[0]["file"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".local").path))
    }

    // MARK: 5. name format, pattern, sanitize

    func testNameFormatRoundTripsThroughThePattern() {
        let run = "3f2a0b1c-0d1e-4f20-8a3b-4c5d6e7f8091"
        let name = DefaultResults.fileName(date: fixedNow, run: run, fileKey8: "abcd1234")
        XCTAssertEqual(name, "20261018T181700.123Z-\(run)-abcd1234.json")
        XCTAssertTrue(DefaultResults.isResultsFileName(name))
        XCTAssertEqual(DefaultResults.fileKey(ofName: name), "abcd1234")
        // the earlier shape (2.1.0) still matches, without a key
        XCTAssertEqual(DefaultResults.fileKey(ofName: "20261018T181700.123Z-\(run).json"), "")
        XCTAssertNil(DefaultResults.fileKey(ofName: "notes.json"))
        XCTAssertEqual(DefaultResults.timestamp(ofName: name)!.timeIntervalSince1970,
                       fixedNow.timeIntervalSince1970, accuracy: 0.0005)

        XCTAssertFalse(DefaultResults.isResultsFileName(".\(name).tmp"))
        XCTAssertFalse(DefaultResults.isResultsFileName("20261018T181700.123Z-\(run.uppercased()).json"))
        XCTAssertFalse(DefaultResults.isResultsFileName("20261018T181700Z-\(run).json"))
        XCTAssertFalse(DefaultResults.isResultsFileName("\(name).bak"))
        XCTAssertFalse(DefaultResults.isResultsFileName("x\(name)"))
    }

    func testSanitize() {
        XCTAssertEqual(DefaultResults.sanitize("com.example.App-UI_Tests.xctrunner"),
                       "com.example.App-UI_Tests.xctrunner")
        XCTAssertEqual(DefaultResults.sanitize("a b/c:d"), "a_b_c_d")
        XCTAssertEqual(DefaultResults.sanitize("日本"), "__")
        XCTAssertEqual(DefaultResults.sanitize(""), "unknown")
        XCTAssertEqual(DefaultResults.sanitize("."), "unknown")
        XCTAssertEqual(DefaultResults.sanitize(".."), "unknown")
        XCTAssertEqual(DefaultResults.sanitize("..a"), "..a")
    }

    // MARK: Failure arm

    private struct Refused: Error {}

    private final class FailingPort: ResultsFilePort {
        var failCreate = false, failWrite = false, failRename = false, failList = false
        let real = FileManagerResultsPort()
        func createDirectory(at url: URL) throws { if failCreate { throw Refused() }; try real.createDirectory(at: url) }
        func write(_ data: Data, to url: URL) throws { if failWrite { throw Refused() }; try real.write(data, to: url) }
        func rename(_ s: URL, to d: URL) throws { if failRename { throw Refused() }; try real.rename(s, to: d) }
        func entries(of f: URL) throws -> [String] { if failList { throw Refused() }; return try real.entries(of: f) }
        func remove(_ url: URL) throws { try real.remove(url) }
    }

    /// A failing write port leaves the run exactly as a working one does
    /// (no throw, same result value) and prints one notice per kind.
    func testAFailingWriteNeverEscapesAndNoticesOncePerKind() throws {
        for configure in [{ (p: FailingPort) in p.failCreate = true },
                          { (p: FailingPort) in p.failWrite = true },
                          { (p: FailingPort) in p.failRename = true }] {
            printed = []
            let port = FailingPort()
            configure(port)
            let ctx = context(files: port)
            let original = result()
            for _ in 0..<3 {
                DefaultResults.writeRun(original, resultsPath: nil, platform: "ios", run: newRun(),
                                        file: "inline", context: ctx)
                XCTAssertNil(DefaultResults.writeDefault(original, platform: "ios", run: newRun(),
                                                         file: "inline", context: ctx))
            }
            XCTAssertEqual(original.passedCount, 1)
            XCTAssertEqual(original.failedCount, 1)
            XCTAssertEqual(printed.count, 1, "one notice per kind: \(printed)")
            XCTAssertEqual(names(in: defaultFolder).filter { !$0.hasPrefix(".") }, [], "nothing half-written")
            XCTAssertEqual(names(in: defaultFolder).filter { $0.hasPrefix(".") }, [], "tmp cleaned up")
        }

        printed = []
        let listing = FailingPort()
        listing.failList = true
        XCTAssertNotNil(DefaultResults.writeDefault(result(), platform: "ios", run: newRun(),
                                                    file: "inline", context: context(files: listing)))
        XCTAssertEqual(printed.count, 1, "a prune failure is noticed, the write stands")
    }
}
