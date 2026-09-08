import XCTest
@testable import JsonUITestRunner

/// Run-scoped orientation: the sidecar, the tier, and the declared/observed pair.
///
/// Before this, the only orientation anywhere was the `setOrientation` action —
/// a rotation performed mid-test — so a tablet lane ran in whatever orientation
/// the device booted in and nothing recorded which one that was.
///
/// ⚠️ These arms are all on the pure half. The half that cannot be tested here
/// is named rather than pretended: `apply` and `observe` need a live
/// `XCUIDevice`/`XCUIApplication`, so no arm in this file proves that a
/// rotation happened. What they do prove is what gets asked for and what gets
/// reported, which is where the Android defect lived — its mapping was wrong,
/// not its plumbing.
final class RunOrientationTests: XCTestCase {

    // MARK: - Sidecar

    private func writeSidecar(_ json: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! json.write(
            to: dir.appendingPathComponent(RunDefaults.sidecarFilename),
            atomically: true, encoding: .utf8)
        return dir
    }

    func testATableIsRead() {
        let dir = writeSidecar("""
        {"schemaVersion": 1, "orientation": {"regular": "landscape"}}
        """)
        XCTAssertEqual(RunDefaults.load(from: dir), .table(["regular": "landscape"]))
    }

    func testAnEmptyTableIsNotTheSameAsNoFile() {
        // The distinction the sidecar exists for. The CLI writes the file on
        // EVERY install, so an empty table means "nothing declared" while a
        // missing file means "installed by a CLI without this feature".
        let dir = writeSidecar("""
        {"schemaVersion": 1, "orientation": {}}
        """)
        XCTAssertEqual(RunDefaults.load(from: dir), .table([:]))

        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(RunDefaults.load(from: empty), .absent)
    }

    func testAFutureSchemaVersionIsRefusedRatherThanGuessedAt() {
        let dir = writeSidecar("""
        {"schemaVersion": 99, "orientation": {"regular": "landscape"}}
        """)
        XCTAssertEqual(RunDefaults.load(from: dir), .unknownVersion(99))
        // And it answers nothing, rather than answering from a shape it does
        // not understand.
        XCTAssertNil(RunDefaults.load(from: dir).orientation(forTier: "regular"))
    }

    func testUnreadableIsItsOwnAnswer() {
        let dir = writeSidecar("not json at all")
        guard case .unreadable = RunDefaults.load(from: dir) else {
            return XCTFail("expected .unreadable, got \(RunDefaults.load(from: dir))")
        }
    }

    func testEveryNonTableCaseNamesItself() {
        // A run that applied no default must be able to say WHY. Folded into
        // one silent "no default", "old install" and "nothing declared" and
        // "file is corrupt" become the same report.
        let dir = writeSidecar("nope")
        XCTAssertNotNil(RunDefaults.load(from: dir).reason)
        XCTAssertNotNil(RunDefaults.Load.absent.reason)
        XCTAssertNotNil(RunDefaults.Load.unknownVersion(2).reason)
        XCTAssertNil(RunDefaults.Load.table([:]).reason)
    }

    func testAnOrientationValueThisDriverDoesNotKnowIsDropped() {
        // Carrying it would leave the device as it booted while the report
        // claimed a default was honoured.
        let dir = writeSidecar("""
        {"schemaVersion": 1, "orientation": {"regular": "sideways", "compact": "portrait"}}
        """)
        XCTAssertEqual(RunDefaults.load(from: dir), .table(["compact": "portrait"]))
    }

    // MARK: - Tier

    func testRegularReadsTheRegularRow() {
        XCTAssertEqual(
            OrientationRuntime.tier(horizontalSizeClass: .regular,
                                    declaredTiers: ["regular", "compact"]),
            "regular")
    }

    func testCompactPrefersCompactOverMedium() {
        // Fixed order, so a table declaring BOTH resolves the same way every
        // run rather than depending on which key was seen first.
        XCTAssertEqual(
            OrientationRuntime.tier(horizontalSizeClass: .compact,
                                    declaredTiers: ["compact", "medium"]),
            "compact")
    }

    func testCompactFallsBackToMediumBecauseMediumFoldsIntoCompactOnIOS() {
        // `ResponsiveEvaluator` matches BOTH `compact` and `medium` against
        // horizontalSizeClass == .compact. A project that declared only
        // `medium` meant it for this device, and ignoring it would drop a
        // declaration the responsive gate honours.
        XCTAssertEqual(
            OrientationRuntime.tier(horizontalSizeClass: .compact,
                                    declaredTiers: ["medium"]),
            "medium")
    }

    func testAnUnresolvedSizeClassReadsNoRow() {
        // Fail-safe, matching the responsive gate: at an unknown size no
        // bucket is met, so no default is applied and nothing is guessed.
        XCTAssertNil(
            OrientationRuntime.tier(horizontalSizeClass: .unspecified,
                                    declaredTiers: ["compact", "regular"]))
    }

    // MARK: - Resolution

    func testTheFileWinsOverTheRunDefault() {
        XCTAssertEqual(
            OrientationRuntime.resolveDeclared(
                fileOrientation: "portrait",
                defaults: .table(["regular": "landscape"]),
                tier: "regular"),
            .portrait)
    }

    func testTheRunDefaultAnswersWhenTheFileSaysNothing() {
        XCTAssertEqual(
            OrientationRuntime.resolveDeclared(
                fileOrientation: nil,
                defaults: .table(["regular": "landscape"]),
                tier: "regular"),
            .landscape)
    }

    func testNothingDeclaredResolvesToNilNotToPortrait() {
        // Nil is a real state — the device is left as it booted. Defaulting to
        // portrait here would report an orientation nobody chose, which is the
        // shape of the defect this feature exists to end.
        XCTAssertNil(
            OrientationRuntime.resolveDeclared(
                fileOrientation: nil, defaults: .table([:]), tier: "regular"))
        XCTAssertNil(
            OrientationRuntime.resolveDeclared(
                fileOrientation: nil, defaults: .absent, tier: "regular"))
        XCTAssertNil(
            OrientationRuntime.resolveDeclared(
                fileOrientation: nil,
                defaults: .table(["regular": "landscape"]), tier: nil))
    }

    func testAnUnknownFileValueDoesNotSilentlyFallThroughToTheDefault() {
        // A typo in the file must not quietly hand the decision to config —
        // the run would then execute in an orientation the file did not ask
        // for, with nothing saying so.
        XCTAssertNil(
            OrientationRuntime.resolveDeclared(
                fileOrientation: "sideways",
                defaults: .table(["regular": "landscape"]),
                tier: "regular"))
    }
}

/// What reaches the results file, and what must not.
final class OrientationReportingTests: XCTestCase {

    private func row(_ result: TestCaseResult) -> [String: Any] {
        let run = TestRunResult(testName: "T", caseResults: [result], totalDuration: 0)
        let payload = ResultsWriter.resultsJSON([run], platform: "ios")
        let suites = payload["suites"] as! [[String: Any]]
        return (suites[0]["results"] as! [[String: Any]])[0]
    }

    func testBothFieldsReachTheRow() {
        let entry = row(TestCaseResult(
            name: "c", passed: true, duration: 0,
            declaredOrientation: .landscape, observedOrientation: .landscape))
        XCTAssertEqual(entry["declaredOrientation"] as? String, "landscape")
        XCTAssertEqual(entry["observedOrientation"] as? String, "landscape")
    }

    func testADisagreementIsReportedRatherThanReconciled() {
        // The case the pair exists for. One field, or a field derived from the
        // other, would make this row indistinguishable from a run that did
        // what it was told.
        let entry = row(TestCaseResult(
            name: "c", passed: true, duration: 0,
            declaredOrientation: .portrait, observedOrientation: .landscape))
        XCTAssertEqual(entry["declaredOrientation"] as? String, "portrait")
        XCTAssertEqual(entry["observedOrientation"] as? String, "landscape")
    }

    func testObservedIsEmittedEvenWhenNothingWasDeclared() {
        // "Which orientation did this run in" is worth recording whether or
        // not anyone asked for it — its absence from the record is the state
        // this feature exists to end. `declared` stays absent, because a
        // default nobody chose must not appear as a choice.
        let entry = row(TestCaseResult(
            name: "c", passed: true, duration: 0,
            declaredOrientation: nil, observedOrientation: .portrait))
        XCTAssertNil(entry["declaredOrientation"])
        XCTAssertEqual(entry["observedOrientation"] as? String, "portrait")
    }

    func testNeitherIsEmittedOnASkippedRow() {
        // A case that did not run has no orientation to report — the same rule
        // `attempts` follows.
        let entry = row(TestCaseResult(
            name: "c", passed: true, duration: 0, skipped: true,
            declaredOrientation: .landscape, observedOrientation: .landscape))
        XCTAssertNil(entry["declaredOrientation"])
        XCTAssertNil(entry["observedOrientation"])
    }

    func testTheRetryStampKeepsTheOrientationPair() {
        // ⚠️ `stamping(attempts:)` names every field it copies, so anything
        // added after it was written is dropped unless it is added there too —
        // silently, and only on cases that needed a retry, which is the
        // hardest population to notice a gap in.
        let stamped = TestCaseResult(
            name: "c", passed: true, duration: 0,
            declaredOrientation: .landscape, observedOrientation: .portrait
        ).stamping(attempts: 2)
        XCTAssertEqual(stamped.declaredOrientation, .landscape)
        XCTAssertEqual(stamped.observedOrientation, .portrait)
        XCTAssertEqual(stamped.attempts, 2)
    }

    func testTheOrientationStampKeepsTheAttemptsCount() {
        // The other direction of the same trap: the orientation stamp runs
        // after the retry stamp, so it must not drop what that one wrote.
        let stamped = TestCaseResult(
            name: "c", passed: true, duration: 0, attempts: 3
        ).stamping(declared: .portrait, observed: .portrait)
        XCTAssertEqual(stamped.attempts, 3)
        XCTAssertEqual(stamped.declaredOrientation, .portrait)
    }

    // MARK: - Per-case declaration

    func testACaseWithNoRotationInheritsTheRunValue() {
        XCTAssertEqual(
            OrientationRuntime.declaredForCase(steps: [], runDeclared: .landscape),
            .landscape)
    }
}
