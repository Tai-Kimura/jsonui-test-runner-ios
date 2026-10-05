import XCTest

/// Where each element that carries an identifier was drawn, relative to the
/// element with the root id — jsonui-cli's conformance `frames` record
/// (conformance/frames.schema.json; RESULTS_SCHEMA.md, section `frames`).
///
/// Conformance compared each platform's screenshots with that platform's own
/// past, and never one platform's geometry with another's: Android drew the
/// align*View targets at 0 / 85 where iOS and web drew them at 120 / 145, and
/// the run was green from the first bake (jsonui-cli ticket
/// conformance-passes-a-wrong-layout-geometry-is-never-compared-across-
/// platforms). A frames record per screenshot is what a cross-platform
/// comparison reads.
///
/// - Units are points, as XCUIElement.frame reports them — the numbers a
///   layout JSON declares. Every value is rounded to 2 decimals.
/// - Every frame is relative to the root element's origin, which removes the
///   status bar and the safe area; `root` keeps the root's own frame as read.
/// - An identifier found on more than one element goes in `duplicates` and
///   stays out of `frames`: which element it names cannot be told.
/// - What was not found is absent. The reader takes the declared ids from the
///   layout, so a missing id is never written as a zero frame.
/// - The frames are read one identifier at a time (`elements(of:ids:)`), never
///   from a hierarchy snapshot, which draws the home indicator into the next
///   screenshot.
public enum FrameRecorder {

    public struct Frame: Codable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct Record: Codable, Equatable {
        public let schemaVersion: Int
        public let fixture: String
        public let platform: String
        public let source: String
        public let root: Frame
        public let frames: [String: Frame]
        /// Omitted when no identifier was found twice.
        public let duplicates: [String]?
        /// Ids read from their own element because no `frame:<id>` measuring
        /// element was found (`layoutElements(of:ids:)`). Omitted when none.
        /// jsonui-cli's gate fails on any: the frame is not the layout box.
        public let fallbacks: [String]?
    }

    public enum RecordError: Error, Equatable, CustomStringConvertible {
        /// No element carries the root id, so nothing can be made relative.
        case rootNotFound(String)
        /// More than one element carries the root id.
        case rootDuplicated(String, count: Int)

        public var description: String {
            switch self {
            case .rootNotFound(let id): return "no element carries the root id \"\(id)\""
            case .rootDuplicated(let id, let count): return "\(count) elements carry the root id \"\(id)\""
            }
        }
    }

    public static let schemaVersion = 1
    public static let source = "xcuielement-frame"
    /// The source when the frames come from the `frame:<id>` measuring
    /// elements (SwiftJsonUI's jsonUIConformanceFrame), the layout boxes.
    public static let layoutProbeSource = "xcuielement-layout-probe"
    /// The identifier prefix of a measuring element.
    public static let layoutProbePrefix = "frame:"

    /// The record for these elements: `(identifier, frame in points)` as read,
    /// in any order. Elements with an empty identifier are not recorded.
    ///
    /// `rootFrame`: the root's frame when the caller knows it better than the
    /// element carrying the root id does. On SwiftUI that element's frame is
    /// the box around its children, not the frame the layout gave it — a
    /// matchParent root holding a 50 x 50 anchor at 120 / 120 and a 200 x 200
    /// target at 0 / 120 reads as 200 x 200 at 0 / 120 (measured on
    /// SwiftJsonUI's ConformanceHost, iOS 26.5), so every frame relative to it
    /// was off by 120. When `rootFrame` is given, the element carrying the
    /// root id is not read, and `frames[rootId]` is `rootFrame` at 0 / 0.
    public static func record(
        fixture: String,
        elements: [(id: String, frame: CGRect)],
        rootId: String = "root",
        rootFrame: CGRect? = nil,
        platform: String = "ios",
        source: String = FrameRecorder.source,
        fallbacks: [String] = []
    ) throws -> Record {
        var byId: [String: [CGRect]] = [:]
        for element in elements where !element.id.isEmpty {
            if rootFrame != nil && element.id == rootId { continue }
            byId[element.id, default: []].append(element.frame)
        }
        if let rootFrame { byId[rootId] = [rootFrame] }
        guard let roots = byId[rootId] else { throw RecordError.rootNotFound(rootId) }
        guard roots.count == 1, let root = roots.first else {
            throw RecordError.rootDuplicated(rootId, count: roots.count)
        }

        var frames: [String: Frame] = [:]
        var duplicates: [String] = []
        for (id, found) in byId {
            if found.count > 1 {
                duplicates.append(id)
                continue
            }
            frames[id] = relative(found[0], to: root)
        }
        return Record(
            schemaVersion: schemaVersion,
            fixture: fixture,
            platform: platform,
            source: source,
            root: rounded(root),
            frames: frames,
            duplicates: duplicates.isEmpty ? nil : duplicates.sorted(),
            fallbacks: fallbacks.isEmpty ? nil : Array(Set(fallbacks)).sorted()
        )
    }

    /// The frames of the elements carrying these identifiers: one query per
    /// identifier, every element that answers it (so a duplicate is seen and
    /// named by `record`). An identifier no element carries is absent.
    ///
    /// Not app.snapshot(): reading the whole hierarchy in one snapshot made
    /// the simulator draw its home indicator, which the conformance
    /// screenshots never show, so 110 of 178 pictures taken after it moved
    /// (pixel-measured on SwiftJsonUI's ConformanceHost, iOS 26.5; a sleep of
    /// the snapshot's 3.8 ms left all 178 identical, so it is the snapshot,
    /// not the time). One query per identifier, as a `waitFor` makes, left
    /// all 178 identical, at a median 114.5 ms per fixture.
    public static func elements(of app: XCUIApplication, ids: [String]) -> [(id: String, frame: CGRect)] {
        var found: [(id: String, frame: CGRect)] = []
        for id in Set(ids) where !id.isEmpty {
            let query = app.descendants(matching: .any).matching(identifier: id)
            for index in 0..<query.count {
                found.append((id, query.element(boundBy: index).frame))
            }
        }
        return found
    }

    /// The layout boxes of these identifiers: the `frame:<id>` measuring
    /// element where the host made one, else the id's own element, named in
    /// `fallbacks`. XCUIElement.frame of the id's own element is the extent
    /// of what was drawn, not the layout box: a background touching the top
    /// paints into the safe area and reads 62 taller, and a container with no
    /// background reads as the union of its children (SwiftJsonUI
    /// ConformanceHost, iOS 26.5, 2026-10-05). One query per identifier, as
    /// `elements(of:ids:)`.
    public static func layoutElements(of app: XCUIApplication, ids: [String]) -> (elements: [(id: String, frame: CGRect)], fallbacks: [String]) {
        var found: [(id: String, frame: CGRect)] = []
        var fallbacks: [String] = []
        for id in Set(ids) where !id.isEmpty {
            let probe = app.descendants(matching: .any).matching(identifier: layoutProbePrefix + id)
            if probe.count > 0 {
                for index in 0..<probe.count { found.append((id, probe.element(boundBy: index).frame)) }
                continue
            }
            let own = app.descendants(matching: .any).matching(identifier: id)
            if own.count > 0 { fallbacks.append(id) }
            for index in 0..<own.count { found.append((id, own.element(boundBy: index).frame)) }
        }
        return (found, fallbacks)
    }

    /// The record as JSON, keys sorted so two runs of the same drawing write
    /// the same bytes.
    public static func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(record)
    }

    static func relative(_ frame: CGRect, to root: CGRect) -> Frame {
        Frame(
            x: round2(frame.minX - root.minX),
            y: round2(frame.minY - root.minY),
            width: round2(frame.width),
            height: round2(frame.height)
        )
    }

    static func rounded(_ frame: CGRect) -> Frame {
        Frame(x: round2(frame.minX), y: round2(frame.minY), width: round2(frame.width), height: round2(frame.height))
    }

    static func round2(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }
}
