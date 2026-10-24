import Foundation
import CoreGraphics

/// `within`: the id of an element (normally a collection cell,
/// `<collectionId>_item_<n>`) that a step's target id is looked up inside.
///
/// A Collection whose cells each hold an element with the same id gives the
/// unscoped lookup (the identifier's first match in tree order) the first
/// cell's element every time. With `within`, the container is found by its
/// id first — its first match, as an unscoped id is — and the target is then
/// the first element with the id among the container's descendants.
///
/// The pure half: the wording of the two failures, and the snapshot walk,
/// generic over the node so it is unit-tested without XCUITest. The XCUITest
/// half is `ElementScope`.
enum WithinScope {
    /// The container is not in the tree. A collection cell is in it only
    /// while it is drawn, so a cell scrolled out of the viewport (or never
    /// reached) has no element at all.
    static func containerNotFound(within: String, id: String) -> String {
        "container '\(within)' (within) not found, so '\(id)' was not looked for inside it — "
            + "a collection cell exists in the tree only while it is drawn: scrollUntilVisible to '\(within)' first"
    }

    /// The container is there and holds no element with the target id.
    static func targetNotFound(id: String, within: String) -> String {
        "'\(id)' not found within '\(within)' (the container exists; none of its descendants has the id '\(id)')"
    }

    /// Where the walk ended.
    enum Located: Equatable {
        /// The target's frame and the rectangles that clip it (the root's
        /// frame, then every clipping ancestor, the container's own
        /// ancestors included).
        case found(frame: CGRect, clips: [CGRect])
        case containerMissing
        case targetMissing
    }

    /// The target's frame and clips, the container looked up first when
    /// `within` is given. Without `within` the walk is the unscoped one: the
    /// first node in tree order with the id, or `.targetMissing`.
    ///
    /// The target is searched among the container's DESCENDANTS (the
    /// container itself is not a candidate), as XCUIElement.descendants is.
    static func locate<Node>(
        id: String,
        within: String?,
        root: Node,
        identifier: (Node) -> String,
        children: (Node) -> [Node],
        frame: (Node) -> CGRect,
        clips: (Node) -> Bool
    ) -> Located {
        var ancestors: [Node] = []
        func found(_ node: Node) -> Located {
            let containers = ancestors.filter(clips).map(frame)
            return .found(frame: frame(node), clips: [frame(root)] + containers)
        }
        // First node with `target` in the subtree under `node` (node itself
        // included when `includeSelf`), ancestors tracked on the way down.
        func walk(_ node: Node, target: String, includeSelf: Bool) -> Node? {
            if includeSelf, identifier(node) == target { return node }
            ancestors.append(node)
            for child in children(node) {
                if let hit = walk(child, target: target, includeSelf: true) { return hit }
            }
            ancestors.removeLast()
            return nil
        }

        guard let within else {
            guard let target = walk(root, target: id, includeSelf: true) else { return .targetMissing }
            // `walk` leaves the target's ancestors on the stack when it hits.
            return found(target)
        }
        guard let container = walk(root, target: within, includeSelf: true) else { return .containerMissing }
        guard let target = walk(container, target: id, includeSelf: false) else { return .targetMissing }
        return found(target)
    }

    /// `hidden` (and `when: { hidden }`) over every element with the id in
    /// scope: it holds when none of them is drawn — the web driver's rule
    /// (`els.every(el => !drawn)`). On iOS an element is drawn when it is in
    /// XCUITest's tree (SwiftJsonUI takes a gone / invisible / hidden view out
    /// of it), so a match is drawn by being a match. A missing container
    /// FAILS it (see `missingContainerFails`).
    static func hiddenHolds(containerMissing: Bool, drawn: [Bool]) -> Bool {
        if containerMissing { return false }
        return drawn.allSatisfy { !$0 }
    }

    /// `notVisible` over the target in scope: the negation of `visible`,
    /// except that a missing container FAILS it (see `missingContainerFails`).
    static func notVisibleHolds(containerMissing: Bool, visible: Bool) -> Bool {
        !containerMissing && !visible
    }

    /// A step's or a condition's `within` names a container that is not in
    /// the tree: `visible`, `notVisible`, `hidden` and `count` fail and a
    /// condition is unmet, as on web and Android. A cell that is not drawn
    /// would otherwise pass "this cell's badge is not shown"; to claim the
    /// cell itself is gone, `hidden` is written on the cell's id without
    /// `within`.
    static func missingContainerFails(within: String?, containerExists: Bool) -> Bool {
        within != nil && !containerExists
    }
}
