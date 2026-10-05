import XCTest
@testable import JsonUITestRunner

/// The frames record jsonui-cli's conformance gate compares across platforms
/// (conformance/frames.schema.json). These pin the conversion: relative to
/// the root's origin, rounded to 2 decimals, duplicates named and left out,
/// nothing invented for what was not found.
final class FrameRecorderTests: XCTestCase {

    // alignTopView__static as iOS draws it: the root below a 62pt top inset,
    // a 50 x 50 anchor at 120 / 120 inside it, the target aligned to its top.
    private let drawn: [(id: String, frame: CGRect)] = [
        ("root", CGRect(x: 0, y: 62, width: 402, height: 778)),
        ("anchor", CGRect(x: 120, y: 182, width: 50, height: 50)),
        ("target", CGRect(x: 0, y: 182, width: 200, height: 200)),
    ]

    func testFramesAreRelativeToTheRootsOrigin() throws {
        let record = try FrameRecorder.record(fixture: "common/alignTopView__static", elements: drawn)
        XCTAssertEqual(record.frames["root"], FrameRecorder.Frame(x: 0, y: 0, width: 402, height: 778))
        XCTAssertEqual(record.frames["anchor"], FrameRecorder.Frame(x: 120, y: 120, width: 50, height: 50))
        XCTAssertEqual(record.frames["target"], FrameRecorder.Frame(x: 0, y: 120, width: 200, height: 200))
        // The root keeps its frame as read, for reading a failure.
        XCTAssertEqual(record.root, FrameRecorder.Frame(x: 0, y: 62, width: 402, height: 778))
        XCTAssertEqual(record.schemaVersion, 1)
        XCTAssertEqual(record.platform, "ios")
        XCTAssertEqual(record.source, "xcuielement-frame")
        XCTAssertNil(record.duplicates)
    }

    func testValuesAreRoundedToTwoDecimals() throws {
        let record = try FrameRecorder.record(fixture: "f", elements: [
            ("root", CGRect(x: 0.333333, y: 61.666666, width: 402, height: 778)),
            ("a", CGRect(x: 10.004999, y: 70.0, width: 33.333333, height: 0.125)),
        ])
        XCTAssertEqual(record.frames["a"], FrameRecorder.Frame(x: 9.67, y: 8.33, width: 33.33, height: 0.13))
        XCTAssertEqual(record.root, FrameRecorder.Frame(x: 0.33, y: 61.67, width: 402, height: 778))
    }

    func testAnIdFoundTwiceIsNamedAndNotRecorded() throws {
        let record = try FrameRecorder.record(fixture: "f", elements: drawn + [
            ("target", CGRect(x: 5, y: 190, width: 10, height: 10)),
        ])
        XCTAssertEqual(record.duplicates, ["target"])
        XCTAssertNil(record.frames["target"])
        XCTAssertNotNil(record.frames["anchor"])
    }

    func testWhatWasNotFoundIsAbsentAndAnEmptyIdIsNotRecorded() throws {
        let record = try FrameRecorder.record(fixture: "f", elements: [
            ("root", CGRect(x: 0, y: 0, width: 10, height: 10)),
            ("", CGRect(x: 1, y: 1, width: 1, height: 1)),
        ])
        XCTAssertEqual(Set(record.frames.keys), ["root"])
    }

    func testARootThatIsMissingOrDuplicatedIsAnError() {
        XCTAssertThrowsError(try FrameRecorder.record(fixture: "f", elements: [("a", .zero)])) {
            XCTAssertEqual($0 as? FrameRecorder.RecordError, .rootNotFound("root"))
        }
        XCTAssertThrowsError(try FrameRecorder.record(fixture: "f", elements: drawn + [("root", .zero)])) {
            XCTAssertEqual($0 as? FrameRecorder.RecordError, .rootDuplicated("root", count: 2))
        }
    }

    /// A root frame the caller read elsewhere replaces the element carrying
    /// the root id — on SwiftUI the box around the root's children (here the
    /// union of anchor and target, 200 x 200 at 0 / 182), not its frame.
    func testAGivenRootFrameReplacesTheElementCarryingTheRootId() throws {
        let asSwiftUIReportsIt = drawn.map { $0.id == "root" ? ("root", CGRect(x: 0, y: 182, width: 200, height: 200)) : $0 }
        let wrong = try FrameRecorder.record(fixture: "f", elements: asSwiftUIReportsIt)
        XCTAssertEqual(wrong.frames["anchor"], FrameRecorder.Frame(x: 120, y: 0, width: 50, height: 50))

        let record = try FrameRecorder.record(fixture: "f", elements: asSwiftUIReportsIt,
                                              rootFrame: CGRect(x: 0, y: 62, width: 402, height: 778))
        XCTAssertEqual(record.frames["anchor"], FrameRecorder.Frame(x: 120, y: 120, width: 50, height: 50))
        XCTAssertEqual(record.frames["root"], FrameRecorder.Frame(x: 0, y: 0, width: 402, height: 778))
        XCTAssertEqual(record.root, FrameRecorder.Frame(x: 0, y: 62, width: 402, height: 778))
        XCTAssertNil(record.duplicates)
        // With a root frame given, no element needs to carry the root id.
        XCTAssertNoThrow(try FrameRecorder.record(fixture: "f", elements: [("a", .zero)], rootFrame: .zero))
    }

    /// The keys are frames.schema.json's: required schemaVersion / fixture /
    /// platform / source / root / frames, each frame x / y / width / height,
    /// and `duplicates` only when there is one.
    func testTheJSONHasTheSchemasKeys() throws {
        let plain = try JSONSerialization.jsonObject(
            with: FrameRecorder.encode(FrameRecorder.record(fixture: "f", elements: drawn))) as! [String: Any]
        XCTAssertEqual(Set(plain.keys), ["schemaVersion", "fixture", "platform", "source", "root", "frames"])
        let anchor = (plain["frames"] as! [String: Any])["anchor"] as! [String: Any]
        XCTAssertEqual(Set(anchor.keys), ["x", "y", "width", "height"])

        let withDuplicate = try JSONSerialization.jsonObject(
            with: FrameRecorder.encode(FrameRecorder.record(fixture: "f", elements: drawn + [("anchor", .zero)]))) as! [String: Any]
        XCTAssertEqual(withDuplicate["duplicates"] as? [String], ["anchor"])
    }

    /// The layout-probe source is written as given, and `fallbacks` only when
    /// an id was read from its own element (frames.schema.json `fallbacks`).
    func testTheSourceAndTheFallbacksAreWrittenAsGiven() throws {
        let probed = try JSONSerialization.jsonObject(
            with: FrameRecorder.encode(FrameRecorder.record(
                fixture: "f", elements: drawn, source: FrameRecorder.layoutProbeSource))) as! [String: Any]
        XCTAssertEqual(probed["source"] as? String, "xcuielement-layout-probe")
        XCTAssertNil(probed["fallbacks"])

        let fellBack = try JSONSerialization.jsonObject(
            with: FrameRecorder.encode(FrameRecorder.record(
                fixture: "f", elements: drawn, source: FrameRecorder.layoutProbeSource,
                fallbacks: ["target", "anchor", "target"]))) as! [String: Any]
        XCTAssertEqual(fellBack["fallbacks"] as? [String], ["anchor", "target"])
        XCTAssertEqual(FrameRecorder.layoutProbePrefix, "frame:")
    }
}
