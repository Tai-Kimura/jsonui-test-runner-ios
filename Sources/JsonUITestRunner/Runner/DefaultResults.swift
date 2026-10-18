import CryptoKit
import Foundation

/// The file operations the default results write uses. A seam so a plain
/// XCTest can point the write at a temporary folder and can make every step
/// fail.
protocol ResultsFilePort {
    func createDirectory(at url: URL) throws
    func write(_ data: Data, to url: URL) throws
    /// Atomic rename that replaces `destination` (rename(2)).
    func rename(_ source: URL, to destination: URL) throws
    /// Names (not paths) of the folder's direct entries. Never recurses.
    func entries(of folder: URL) throws -> [String]
    func remove(_ url: URL) throws
}

struct FileManagerResultsPort: ResultsFilePort {
    struct RenameFailed: Error { let code: Int32 }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    func rename(_ source: URL, to destination: URL) throws {
        if Foundation.rename(source.path, destination.path) != 0 {
            throw RenameFailed(code: errno)
        }
    }

    func entries(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// Prints a notice once per kind. One instance per process in the runner
/// (`shared`); a test makes its own so the "once" does not leak across tests.
final class NoticeOnce {
    static let shared = NoticeOnce()

    private let lock = NSLock()
    private var seen: Set<String> = []
    private let sink: (String) -> Void

    init(sink: @escaping (String) -> Void = { print($0) }) {
        self.sink = sink
    }

    func notice(kind: String, _ message: @autoclosure () -> String) {
        lock.lock()
        let first = seen.insert(kind).inserted
        lock.unlock()
        if first { sink(message()) }
    }
}

/// Results of a run when `resultsPath` is not set: one new file per run, in a
/// per-app folder on the host, so `jui viz` can read past runs
/// (jsonui-test-runner, default results location spec, 2026-10-18).
///
/// `<base>/ios/<app-segment>/<UTC yyyyMMdd'T'HHmmss.SSS'Z'>-<run>.json`
///
/// - base = `$JSONUI_TEST_RESULTS_DIR` when it is an absolute path, else
///   `$SIMULATOR_HOST_HOME/.local/state/jsonui-test/results`. XDG_STATE_HOME is
///   not honoured: the simulator cannot see the host's value.
///   JSONUI_TEST_RESULTS_DIR is a host-side variable: it reaches this process
///   only when passed to xcodebuild as `TEST_RUNNER_JSONUI_TEST_RESULTS_DIR`.
///   It has no effect on the Android device side, which writes to a fixed
///   on-device folder.
/// - Not on a simulator, or SIMULATOR_HOST_HOME missing/empty: nothing is
///   written (real devices are out of scope).
/// - app = the runner's `Bundle.main.bundleIdentifier`
///   (`<uitest bundle id>.xctrunner`), else `unknown`.
///
/// Never changes a result: every step swallows its own failure, and each kind
/// of failure prints one notice per process.
enum DefaultResults {

    static let resultsDirVariable = "JSONUI_TEST_RESULTS_DIR"
    static let hostHomeVariable = "SIMULATOR_HOST_HOME"
    static let platformFolder = "ios"
    static let maxAgeDays = 14
    static let maxFiles = 500

    /// The only names pruning may delete. The dot-prefixed temporary file a
    /// write goes through does not match. Group 1 is the file key; a name of
    /// the earlier shape (2.1.0, no key) still matches, without it.
    static let namePattern =
        #"^\d{8}T\d{6}\.\d{3}Z-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:-([0-9a-f]{8}))?\.json$"#
    private static let nameRegex = try! NSRegularExpression(pattern: namePattern)

    /// Everything the write reads from outside, so a test never touches the
    /// real HOME.
    struct Context {
        var environment: [String: String]
        var isSimulator: Bool
        var app: String
        var now: () -> Date
        var files: ResultsFilePort
        var notices: NoticeOnce

        static var live: Context {
            #if targetEnvironment(simulator)
            let simulator = true
            #else
            let simulator = false
            #endif
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            return Context(
                environment: ProcessInfo.processInfo.environment,
                isSimulator: simulator,
                app: bundleId.isEmpty ? "unknown" : bundleId,
                now: Date.init,
                files: FileManagerResultsPort(),
                notices: .shared
            )
        }
    }

    // MARK: - Entry point

    /// What the runner calls at the end of each run. `resultsPath` set: the
    /// old write, unchanged (same file, overwritten, no new keys) and no
    /// default write. Unset: the default write.
    static func writeRun(
        _ result: TestRunResult,
        resultsPath: URL?,
        platform: String,
        run: String,
        file: String,
        context: Context = .live
    ) {
        if let path = resultsPath {
            try? ResultsWriter.write([result], to: path, platform: platform)
            return
        }
        writeDefault(result, platform: platform, run: run, file: file, context: context)
    }

    /// The default write. Returns the file it wrote, nil when it wrote none.
    @discardableResult
    static func writeDefault(
        _ result: TestRunResult,
        platform: String,
        run: String,
        file: String,
        context: Context
    ) -> URL? {
        guard let base = baseDirectory(environment: context.environment, isSimulator: context.isSimulator) else {
            return nil
        }
        let folder = self.folder(base: base, app: context.app)
        let date = context.now()
        let name = fileName(date: date, run: run, fileKey8: fileKey([file]))
        let target = folder.appendingPathComponent(name)
        let temporary = folder.appendingPathComponent(".\(name).tmp")
        let files = context.files

        do {
            try files.createDirectory(at: folder)
        } catch {
            context.notices.notice(kind: "folder",
                "JsonUITestRunner: results not written: cannot create \(folder.path) (\(error)). Set resultsPath, or TEST_RUNNER_\(resultsDirVariable) to a writable absolute path.")
            return nil
        }

        var payload = ResultsWriter.resultsJSON([result], platform: platform, generatedAt: date)
        payload["run"] = run
        payload["app"] = context.app
        if var suites = payload["suites"] as? [[String: Any]], !suites.isEmpty {
            suites[0]["file"] = file
            payload["suites"] = suites
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try files.write(data, to: temporary)
        } catch {
            context.notices.notice(kind: "write",
                "JsonUITestRunner: results not written to \(folder.path) (\(error)).")
            try? files.remove(temporary)
            return nil
        }

        do {
            try files.rename(temporary, to: target)
        } catch {
            context.notices.notice(kind: "rename",
                "JsonUITestRunner: results not written to \(folder.path): rename failed (\(error)).")
            try? files.remove(temporary)
            return nil
        }

        prune(folder: folder, now: date, files: files, notices: context.notices)
        return target
    }

    // MARK: - Location

    static func baseDirectory(environment: [String: String], isSimulator: Bool) -> URL? {
        guard isSimulator,
              let home = environment[hostHomeVariable], !home.isEmpty else {
            return nil
        }
        if let explicit = environment[resultsDirVariable], explicit.hasPrefix("/") {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".local/state/jsonui-test/results", isDirectory: true)
    }

    static func folder(base: URL, app: String) -> URL {
        base.appendingPathComponent(platformFolder, isDirectory: true)
            .appendingPathComponent(sanitize(app), isDirectory: true)
    }

    /// Every char outside `[A-Za-z0-9._-]` becomes `_`; empty or all dots
    /// becomes `unknown` (the same rule as Android `ArtifactPaths.sanitize`).
    static func sanitize(_ app: String) -> String {
        let mapped = String(app.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", ".", "_", "-":
                return Character(scalar)
            default:
                return "_"
            }
        })
        if mapped.isEmpty || mapped.allSatisfy({ $0 == "." }) { return "unknown" }
        return mapped
    }

    // MARK: - Names

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter
    }

    /// `<UTC yyyyMMdd'T'HHmmss.SSS'Z'>-<run>-<fileKey8>.json` — name order is time order.
    static func fileName(date: Date, run: String, fileKey8: String) -> String {
        "\(formatter().string(from: date))-\(run)-\(fileKey8).json"
    }

    /// The run's file key in a name: the first 8 hex digits of SHA-256 over
    /// the UTF-8 of its test files (distinct, sorted, joined with a newline),
    /// so pruning tells one test file's results from another's by name alone.
    /// jsonui-test-runner specs/vectors/results-prune.json.
    static func fileKey(_ files: [String]) -> String {
        let key = Array(Set(files)).sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    static func isResultsFileName(_ name: String) -> Bool {
        nameRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// The file key a matching name carries; "" for a name of the earlier shape; nil when it does not match.
    static func fileKey(ofName name: String) -> String? {
        guard let match = nameRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return nil }
        guard let range = Range(match.range(at: 1), in: name) else { return "" }
        return String(name[range])
    }

    /// The time a results file name carries (its first 19 characters).
    static func timestamp(ofName name: String) -> Date? {
        guard name.count >= 19 else { return nil }
        return formatter().date(from: String(name.prefix(19)))
    }

    // MARK: - Pruning

    /// The names pruning deletes from one folder, in name order. The newest
    /// name of each file key is always kept: a test file not rerun keeps its
    /// latest result however old, and however many other files ran since.
    /// The rest — older names of the same key, and names of the earlier
    /// shape — go when older than `maxAgeDays`, then oldest first until at
    /// most `maxFiles` names remain (a folder of more test files than that
    /// keeps them all). Names not matching `namePattern` are never chosen.
    static func namesToPrune(_ names: [String], now: Date, maxFiles: Int = maxFiles, maxAgeDays: Int = maxAgeDays) -> [String] {
        let matching = Array(Set(names.filter(isResultsFileName))).sorted()
        var latest: [String: String] = [:]
        for name in matching {
            if let key = fileKey(ofName: name), !key.isEmpty { latest[key] = name }   // sorted: the last is the newest
        }
        let kept = Set(latest.values)
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        let replaced = matching.filter { !kept.contains($0) }
        var doomed = Set(replaced.filter { name in timestamp(ofName: name).map { $0 < cutoff } ?? false })
        var remaining = matching.count - doomed.count
        for name in replaced where remaining > maxFiles {
            if doomed.insert(name).inserted { remaining -= 1 }
        }
        return matching.filter { doomed.contains($0) }
    }

    /// In this one folder only, delete `namesToPrune`. Nothing else is
    /// touched; nothing recurses.
    static func prune(folder: URL, now: Date, files: ResultsFilePort, notices: NoticeOnce) {
        let names: [String]
        do {
            names = try files.entries(of: folder)
        } catch {
            notices.notice(kind: "prune", "JsonUITestRunner: old results not pruned in \(folder.path) (\(error)).")
            return
        }
        for name in namesToPrune(names, now: now) {
            do {
                try files.remove(folder.appendingPathComponent(name))
            } catch {
                notices.notice(kind: "prune", "JsonUITestRunner: old results not pruned in \(folder.path) (\(error)).")
            }
        }
    }
}
