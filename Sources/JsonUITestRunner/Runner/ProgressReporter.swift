import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Where a progress line goes (progress.schema.json: one JSON object per line).
///
/// A seam so a plain XCTest can read what the runner emits, and can hand it a
/// sink that throws. The runner's own sink is `OSLogProgressSink`.
protocol ProgressSink {
    func write(_ line: String) throws
}

/// Unified logging, subsystem `com.jsonui.testrunner`, category `progress`,
/// at info, public — what `jui viz` reads with
/// `xcrun simctl spawn <udid> log stream --style ndjson --level info`.
///
/// ⚠️ `privacy: .public` is the record's whole point: without it the line is
/// logged as `<private>` outside a debugger and the reader gets nothing.
struct OSLogProgressSink: ProgressSink {
    private let logger = Logger(subsystem: "com.jsonui.testrunner", category: "progress")

    func write(_ line: String) {
        logger.info("\(line, privacy: .public)")
    }
}

/// The records themselves, built as plain dictionaries with exactly the keys
/// progress.schema.json allows for each event (`additionalProperties: false`
/// plus a per-event `propertyNames` list). Pure: time, run id and device
/// come in as arguments.
enum ProgressRecord {

    /// Longer `file` / `test` / `case` values are cut to this many characters
    /// followed by "…", and the line says `truncated: true`.
    ///
    /// Counted in Unicode scalars (code points), the unit the schema's
    /// `maxLength: 201` counts in — not grapheme clusters, which would let a
    /// 200-"character" string of combining sequences exceed 201 code points,
    /// and not UTF-16 units, which would cut a string of 200 emoji at 100.
    static let maxLength = 200
    static let ellipsis = "\u{2026}"

    enum Event: String {
        case runStart = "run_start"
        case caseStart = "case_start"
        case caseEnd = "case_end"
        case runEnd = "run_end"
    }

    enum Status: String {
        case passed
        case failed
        case skipped
    }

    /// What every line carries.
    struct Common {
        let platform: String
        let run: String
        let t: Int64
    }

    /// Which case a line is about: the same strings results.json writes as
    /// testName / caseName, and the file the runner read.
    struct Case: Equatable {
        let file: String
        let test: String
        let name: String
    }

    static func runStart(_ common: Common, files: Int, device: String?, deviceId: String?) -> [String: Any] {
        var record = base(common, .runStart)
        record["files"] = max(0, files)
        if let device { record["device"] = device }
        if let deviceId { record["deviceId"] = deviceId }
        return record
    }

    static func caseStart(_ common: Common, _ testCase: Case, attempt: Int) -> [String: Any] {
        var record = base(common, .caseStart)
        identify(&record, testCase)
        record["attempt"] = max(1, attempt)
        return record
    }

    static func caseEnd(_ common: Common, _ testCase: Case, attempt: Int, status: Status, durationMs: Int) -> [String: Any] {
        var record = base(common, .caseEnd)
        identify(&record, testCase)
        record["attempt"] = max(0, attempt)
        record["status"] = status.rawValue
        record["durationMs"] = max(0, durationMs)
        return record
    }

    /// The single line of a case that never ran: no case_start, attempt 0,
    /// status skipped, durationMs 0 (the schema pins all three together).
    static func skipped(_ common: Common, _ testCase: Case) -> [String: Any] {
        caseEnd(common, testCase, attempt: 0, status: .skipped, durationMs: 0)
    }

    static func runEnd(_ common: Common, passed: Int, failed: Int, skipped: Int) -> [String: Any] {
        var record = base(common, .runEnd)
        record["passed"] = passed
        record["failed"] = failed
        record["skipped"] = skipped
        return record
    }

    /// One line of JSON, or nil when the record cannot be serialized.
    ///
    /// ⚠️ The validity check is not decoration: `JSONSerialization.data`
    /// raises an Objective-C exception on an invalid object, which Swift
    /// cannot catch — it would end the test process, the one thing emitting
    /// must never do.
    static func line(_ record: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Milliseconds as a JSON integer. A non-finite or negative interval is 0:
    /// `Int(Double.nan)` traps, and a trap in the reporter would end the run.
    static func milliseconds(_ seconds: TimeInterval) -> Int {
        let ms = seconds * 1000
        guard ms.isFinite, ms > 0 else { return 0 }
        guard ms < Double(Int.max) else { return Int.max }
        return Int(ms)
    }

    /// The first 200 code points and "…" when longer, and whether it was cut.
    static func truncate(_ value: String) -> (value: String, truncated: Bool) {
        let scalars = value.unicodeScalars
        guard scalars.count > maxLength else { return (value, false) }
        var cut = String.UnicodeScalarView(scalars.prefix(maxLength))
        cut.append(contentsOf: ellipsis.unicodeScalars)
        return (String(cut), true)
    }

    private static func base(_ common: Common, _ event: Event) -> [String: Any] {
        [
            "v": 1,
            "t": common.t,
            "platform": common.platform,
            "run": common.run,
            "event": event.rawValue,
        ]
    }

    private static func identify(_ record: inout [String: Any], _ testCase: Case) {
        let file = truncate(testCase.file)
        let test = truncate(testCase.test)
        let name = truncate(testCase.name)
        record["file"] = file.value
        record["test"] = test.value
        record["case"] = name.value
        // Present only when true (`const: true`); absent means nothing was cut.
        if file.truncated || test.truncated || name.truncated {
            record["truncated"] = true
        }
    }
}

/// Emits the progress records of a run while it is under way (results.json is
/// written only at the end): run_start, a case_start / case_end pair per
/// attempt, one case_end for a case that never ran, run_end.
///
/// Emitting is always on and never affects the test: every emit swallows its
/// own failure, and a nil sink does nothing.
///
/// Not named `ProgressReporter`: the iOS 27 SDK's Foundation declares a
/// public class of that name, and a test target importing both modules no
/// longer compiles.
final class TestProgressReporter {

    private let sink: ProgressSink?
    private let now: () -> Date
    private let makeRunId: () -> UUID
    /// The run every line carries; a new one per `runStarted`. Each
    /// `run(screenTest:)` / `run(flowTest:)` is one run, because each writes
    /// its own results.json and run_end counts what that file counts.
    private(set) var run: String

    init(
        sink: ProgressSink? = OSLogProgressSink(),
        now: @escaping () -> Date = Date.init,
        makeRunId: @escaping () -> UUID = UUID.init
    ) {
        self.sink = sink
        self.now = now
        self.makeRunId = makeRunId
        self.run = makeRunId().uuidString.lowercased()
    }

    /// The driver's own platform, not `TestRunnerConfig.platform`: that one
    /// selects which gates apply, this one says which driver wrote the line.
    static let platform = "ios"

    /// Start a run. `device` is the simulator's name (SIMULATOR_DEVICE_NAME,
    /// else UIDevice's), `deviceId` its UDID when the environment has one.
    func runStarted(files: Int, environment: [String: String] = ProcessInfo.processInfo.environment) {
        run = makeRunId().uuidString.lowercased()
        let device = environment["SIMULATOR_DEVICE_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.deviceName()
        let deviceId = environment["SIMULATOR_UDID"].flatMap { $0.isEmpty ? nil : $0 }
        emit(ProgressRecord.runStart(common(), files: files, device: device, deviceId: deviceId))
    }

    func caseStarted(_ testCase: ProgressRecord.Case, attempt: Int) {
        emit(ProgressRecord.caseStart(common(), testCase, attempt: attempt))
    }

    func caseEnded(_ testCase: ProgressRecord.Case, attempt: Int, passed: Bool, duration: TimeInterval) {
        emit(ProgressRecord.caseEnd(common(), testCase, attempt: attempt,
                                    status: passed ? .passed : .failed,
                                    durationMs: ProgressRecord.milliseconds(duration)))
    }

    /// A case that never ran (skip / platform / responsive gate).
    func caseSkipped(_ testCase: ProgressRecord.Case) {
        emit(ProgressRecord.skipped(common(), testCase))
    }

    /// A failed row the runner records without running the case — setup or
    /// a launch failed first, or the extra `teardown` row. It is a row of
    /// results.json, so it gets its one attempt here; a pair rather than a
    /// lone case_end because attempt 0 is reserved for "skipped".
    func caseFailedWithoutRunning(_ testCase: ProgressRecord.Case) {
        caseStarted(testCase, attempt: 1)
        caseEnded(testCase, attempt: 1, passed: false, duration: 0)
    }

    /// `CaseRetry.run` with a case_start / case_end pair around every
    /// attempt (attempt 1, 2, ...; the last pair's status is the case's).
    /// The result and the attempt count are CaseRetry's, untouched.
    func retrying<T>(
        _ testCase: ProgressRecord.Case,
        retries: Int,
        isPass: (T) -> Bool,
        attempt: () -> T
    ) -> (result: T, attempts: Int) {
        var number = 0
        return CaseRetry.run(retries: retries, isPass: isPass) { () -> T in
            number += 1
            let started = now()
            caseStarted(testCase, attempt: number)
            let result = attempt()
            caseEnded(testCase, attempt: number, passed: isPass(result),
                      duration: now().timeIntervalSince(started))
            return result
        }
    }

    /// End the run with the counts results.json has for these rows: by the
    /// same status rule ResultsWriter writes (a skipped row is skipped, not
    /// passed, though its `passed` is true), one per row, so a retried case
    /// counts once, by its final attempt.
    func runEnded(rows: [TestCaseResult]) {
        var passed = 0, failed = 0, skipped = 0
        for row in rows {
            switch ResultsWriter.status(for: row) {
            case "skipped": skipped += 1
            case "passed": passed += 1
            default: failed += 1
            }
        }
        emit(ProgressRecord.runEnd(common(), passed: passed, failed: failed, skipped: skipped))
    }

    private func common() -> ProgressRecord.Common {
        ProgressRecord.Common(platform: Self.platform, run: run,
                              t: Int64(ProgressRecord.milliseconds(now().timeIntervalSince1970)))
    }

    private func emit(_ record: [String: Any]) {
        guard let sink, let line = ProgressRecord.line(record) else { return }
        do {
            try sink.write(line)
        } catch {
            // Swallowed on purpose: a progress line never changes a result.
        }
    }

    private static func deviceName() -> String? {
        #if canImport(UIKit) && !os(macOS)
        return UIDevice.current.name
        #else
        return nil
        #endif
    }
}
