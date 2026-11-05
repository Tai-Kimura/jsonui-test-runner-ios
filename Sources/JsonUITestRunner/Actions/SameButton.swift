import XCTest

/// Which element a button name means, when the query for it matches several.
///
/// On iOS 27 a privacy prompt exposes each of its buttons twice: a Button
/// holding a Button with the same identifier, label and frame (measured
/// 2026-11-05, iOS 27.2: camera, microphone, photos, contacts, calendar,
/// reminders, tracking; on iOS 26.5 one Button each; the notification and
/// location prompts have one Button each on both). It is one button on the
/// screen, but XCUITest treats the name as ambiguous: `tap()` records
/// "Multiple matching elements found" and stops the test, and `isHittable`
/// answers false without saying why.
///
/// `firstMatch` alone would settle that and also settle two different
/// buttons with one name, which is a test that cannot say what it means. So
/// only the nesting is settled: every match has to be the same button, and
/// the others have to sit inside one of them. Anything else stays ambiguous.
public enum SameButton {

    /// The parts of an element snapshot the decision reads.
    public struct Node: Equatable {
        public var isButton: Bool
        public var identifier: String
        public var label: String
        public var frame: CGRect
        public var children: [Node]

        public init(isButton: Bool = true, identifier: String, label: String, frame: CGRect, children: [Node] = []) {
            self.isButton = isButton
            self.identifier = identifier
            self.label = label
            self.frame = frame
            self.children = children
        }

        func isSameButton(as other: Node) -> Bool {
            isButton && other.isButton
                && identifier == other.identifier
                && label == other.label
                && frame == other.frame
        }

        func copiesInside(of head: Node) -> Int {
            children.reduce(0) { $0 + ($1.isSameButton(as: head) ? 1 : 0) + $1.copiesInside(of: head) }
        }
    }

    public enum Reading: Equatable {
        case absent
        /// One button on the screen, however many elements it is exposed as.
        case one
        /// This many matches that are not one button.
        case different(Int)
    }

    /// `matches` is what the query matched, each with its subtree.
    public static func read(_ matches: [Node]) -> Reading {
        if matches.isEmpty { return .absent }
        if matches.count == 1 { return .one }
        let nested = matches.contains { head in
            matches.allSatisfy { $0.isSameButton(as: head) }
                && head.copiesInside(of: head) == matches.count - 1
        }
        return nested ? .one : .different(matches.count)
    }

    /// Whether a privacy prompt says it is about something other than the
    /// photo library. iOS 27 names them ("kTCCServiceCamera-alert"), so
    /// addMedia does not grant the camera on its way to the photos prompt.
    /// iOS 26 and the notification and location prompts have no identifier,
    /// and an empty one says nothing (measured 2026-11-05).
    public static func isAnotherServicesPrompt(_ identifier: String) -> Bool {
        identifier.hasPrefix("kTCCService") && !identifier.hasPrefix("kTCCServicePhotos")
    }
}

extension SameButton.Node {
    init(_ snapshot: XCUIElementSnapshot) {
        self.init(
            isButton: snapshot.elementType == .button,
            identifier: snapshot.identifier,
            label: snapshot.label,
            frame: snapshot.frame,
            children: snapshot.children.map { SameButton.Node($0) })
    }
}

/// What a button name in a query came to.
enum ButtonPick {
    case absent
    case button(XCUIElement)
    case different(Int)
}

extension XCUIElementQuery {
    /// The button called `name` (identifier or label, as the subscript reads
    /// it) under this query.
    func pickButton(_ name: String) -> ButtonPick {
        let matches = matching(identifier: name)
        let count = matches.count
        if count == 0 { return .absent }
        if count == 1 { return .button(matches.firstMatch) }
        let read = matches.snapshotsBoundByIndex()
        // One left while it was read: what is on the screen is moving, so
        // the next read decides. `firstMatch` on what remains is not a
        // decision about the buttons that were there.
        guard read.count == count else { return .different(count) }
        switch SameButton.read(read.map { SameButton.Node($0) }) {
        case .absent: return .absent
        case .one: return .button(matches.firstMatch)
        case .different(let n): return .different(n)
        }
    }
}
