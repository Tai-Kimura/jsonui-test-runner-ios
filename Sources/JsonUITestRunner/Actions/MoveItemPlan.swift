import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// moveItem: where the finger presses and where it releases, or why the step fails before anything moves
/// (jsonui-test-runner schemas/actions.schema.json moveItemAction, specs/vectors/move-item.json — Fixtures).
///
/// The press is the handle's centre when the step gives `handle`, else the from row's centre; the release is in the
/// press's column, over the to row at 3/4 of its height going down and 1/4 going up — never on a centre, which the
/// libraries' reorder rule (jsonui-cli shared/core/reorder_vectors.json) does not count as passed and iOS 27's own
/// reorderContainer does. Released where there is no row, iOS 27's reorderContainer cancels the move, so the
/// release is always over a row (support 1's measurement on iOS 18.6 / 26.5 / 27.2, 2026-11-13).
public enum MoveItemPlan {
    /// press 1.0 s (the libraries' own drag begins at 0.5 s; List's onMove takes 0.3 s), hold 0.5 s before release
    public static let pressSeconds: TimeInterval = 1.0
    public static let holdSeconds: TimeInterval = 0.5
    /// A press or release nearer the viewport's top or bottom than this lets a list scroll by itself under the held
    /// finger: measured on iOS 27.2 (iPhone 17, List with onMove, window 874 pt with the 34 pt home indicator), a
    /// release 129 pt above the window's bottom landed on `to`, one 55 pt above it two rows further (the vectors'
    /// edgeMargin).
    public static let edgeMargin: CGFloat = 100

    public enum Outcome: Equatable {
        case gesture(press: CGPoint, release: CGPoint)
        case fail(String)
    }

    /// `rows`: address -> the frames found for it (none: not drawn; two or more: the address repeats).
    /// `handle`: nil when the step gives no handle; .some(nil) when it gives one and none was found in the from row.
    public static func plan(id: String, from: Int, to: Int, section: Int = 0, viewport: CGRect,
                            rows: [String: [CGRect]], handle: CGRect?? = nil) -> Outcome {
        if from == to { return .fail("same") }
        if section != 0 { return .fail("section") }
        func row(_ n: Int) -> Result<CGRect, Failure> {
            let address = "\(id)_item_\(n)"
            let found = rows[address] ?? []
            if found.count > 1 { return .failure(Failure("ambiguous:\(address)")) }
            guard let frame = found.first else { return .failure(Failure("missing:\(address)")) }
            if frame.minX < viewport.minX || frame.minY < viewport.minY
                || frame.maxX > viewport.maxX || frame.maxY > viewport.maxY {
                return .failure(Failure("offscreen:\(address)"))
            }
            return .success(frame)
        }
        let fromRow: CGRect, toRow: CGRect
        switch row(from) { case .success(let f): fromRow = f; case .failure(let e): return .fail(e.reason) }
        switch row(to) { case .success(let f): toRow = f; case .failure(let e): return .fail(e.reason) }
        let press: CGPoint
        switch handle {
        case .none: press = CGPoint(x: fromRow.midX, y: fromRow.midY)
        case .some(.none): return .fail("no-handle")
        case .some(.some(let grip)): press = CGPoint(x: grip.midX, y: grip.midY)
        }
        let release = CGPoint(x: press.x, y: toRow.minY + toRow.height * (to > from ? 0.75 : 0.25))
        func near(_ y: CGFloat) -> Bool { y - viewport.minY < edgeMargin || viewport.maxY - y < edgeMargin }
        if near(press.y) { return .fail("edge:\(id)_item_\(from)") }
        if near(release.y) { return .fail("edge:\(id)_item_\(to)") }
        return .gesture(press: press, release: release)
    }

    struct Failure: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// The sentence a failed plan gives the step (the web and Android drivers say the same).
    public static func sentence(_ reason: String, from: Int, handle: String?) -> String {
        let parts = reason.split(separator: ":", maxSplits: 1).map(String.init)
        let address = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "same": return "moveItem: 'from' and 'to' are the same row (\(from)): nothing to move"
        case "section": return "moveItem moves within section 0 (v1)"
        case "ambiguous":
            return "moveItem: '\(address)' is more than one element (a Collection of several sections: v1 moves within a single section)"
        case "missing": return "moveItem: '\(address)' was not found"
        case "offscreen":
            return "moveItem: '\(address)' is not on screen (scroll it into view first, e.g. scrollUntilVisible; the drag does not scroll)"
        case "edge":
            return "moveItem: '\(address)' is too near the screen's top or bottom (within \(Int(edgeMargin)): a list scrolls by itself there under a held finger); scroll it towards the middle first"
        case "no-handle": return "moveItem: the handle '\(handle ?? "")' was not found inside the row (from \(from))"
        default: return "moveItem: \(reason)"
        }
    }
}
