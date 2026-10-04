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
        platform: String = "ios"
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
            duplicates: duplicates.isEmpty ? nil : duplicates.sorted()
        )
    }

    /// Every element in the application that carries an identifier, from a
    /// single snapshot of the hierarchy (one query, not one per element).
    public static func elements(of app: XCUIApplication) throws -> [(id: String, frame: CGRect)] {
        var found: [(id: String, frame: CGRect)] = []
        func walk(_ snapshot: XCUIElementSnapshot) {
            if !snapshot.identifier.isEmpty {
                found.append((snapshot.identifier, snapshot.frame))
            }
            snapshot.children.forEach(walk)
        }
        walk(try app.snapshot())
        return found
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
