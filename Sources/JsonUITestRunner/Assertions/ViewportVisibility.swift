import XCTest

/// `visible` / `notVisible` and `when: { visible }`: whether an element is in
/// the viewport (VisibleFrame.inViewport), read from one accessibility
/// snapshot of the app — the element, and the frame of every scroll
/// container above it, which XCUIElement has no way to ask for.
///
/// The element is the identifier's first match in tree order, the one
/// `descendants(matching: .any).matching(identifier:).firstMatch` returns.
///
/// While a modal is up (sheet, at any detent; fullScreenCover; alert;
/// confirmationDialog) the snapshot holds the modal's elements only — those
/// of the view under it are not in it, although a query still finds them
/// (`exists` is true). So they are not visible here, which is Android's answer:
/// UiAutomator does not find what is under a ModalBottomSheet or a Dialog
/// (measured 2026-10-14, iOS 26.2 / Android API 35).
enum ViewportVisibility {
    /// The element types whose frame is the window onto content that scrolls.
    static let clippingTypes: Set<XCUIElement.ElementType> = [.scrollView, .table, .collectionView, .webView]

    /// The element's frame and the rectangles that clip it, or nil when no
    /// element has the identifier.
    static func locate(id: String, in app: XCUIApplication) -> (frame: CGRect, clips: [CGRect])? {
        guard let root = try? app.snapshot() else { return nil }
        return locate(id: id, in: root)
    }

    static func locate(id: String, in root: XCUIElementSnapshot) -> (frame: CGRect, clips: [CGRect])? {
        var ancestors: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) -> (CGRect, [CGRect])? {
            if node.identifier == id {
                let containers = ancestors.filter { clippingTypes.contains($0.elementType) }.map { $0.frame }
                return (node.frame, [root.frame] + containers)
            }
            ancestors.append(node)
            defer { ancestors.removeLast() }
            for child in node.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(root)
    }

    static func isVisible(id: String, in app: XCUIApplication) -> Bool {
        notVisibleReason(id: id, in: app) == nil
    }

    /// `isVisible`, the target looked up inside `within` when given. A
    /// missing container is not visible.
    static func isVisible(id: String, within: String?, in app: XCUIApplication) -> Bool {
        notVisibleReason(id: id, within: within, in: app) == nil
    }

    /// `notVisibleReason`, the target looked up inside `within` when given
    /// (WithinScope.locate over the same snapshot). Without `within` it is
    /// `notVisibleReason(id:in:)` unchanged.
    static func notVisibleReason(id: String, within: String?, in app: XCUIApplication) -> String? {
        guard let within else { return notVisibleReason(id: id, in: app) }
        guard let root = try? app.snapshot() else { return "could not read the accessibility snapshot" }
        let located = WithinScope.locate(
            id: id, within: within, root: root,
            identifier: { $0.identifier },
            children: { $0.children },
            frame: { $0.frame },
            clips: { clippingTypes.contains($0.elementType) })
        switch located {
        case .found(let frame, let clips):
            return VisibleFrame.inViewport(frame, clips: clips) ? nil : "not in the viewport"
        case .containerMissing:
            // In the query but not the snapshot: under a modal, as above.
            return ElementScope.container(within, in: app).exists
                ? ModalCover.reason(cover(in: app, root: root))
                : WithinScope.containerNotFound(within: within, id: id)
        case .targetMissing:
            return ElementScope.element(id: id, within: within, in: app).exists
                ? ModalCover.reason(cover(in: app, root: root))
                : WithinScope.targetNotFound(id: id, within: within)
        }
    }

    /// nil when visible; otherwise why not, in the words the web driver uses.
    ///
    /// Not in the snapshot has two causes that used to share "does not
    /// exist": nothing has the identifier, or a modal is up and the element
    /// is under it (the query still finds it). Measured 2026-10-15: a 2FA
    /// title under iOS's "Save Password?" sheet failed `visible` with "does
    /// not exist" while it was in the tree, and the reader went looking for a
    /// navigation failure. The query is asked only when the snapshot has no
    /// match, so a visible element costs nothing more.
    static func notVisibleReason(id: String, in app: XCUIApplication) -> String? {
        guard let root = try? app.snapshot() else { return "could not read the accessibility snapshot" }
        guard let found = locate(id: id, in: root) else {
            let exists = app.descendants(matching: .any).matching(identifier: id).firstMatch.exists
            return exists ? ModalCover.reason(cover(in: app, root: root)) : "does not exist"
        }
        return VisibleFrame.inViewport(found.frame, clips: found.clips) ? nil : "not in the viewport"
    }

    /// What the element is under. The query first: under iOS's "Save
    /// Password?" sheet the snapshot held no labelled element at all — not
    /// even the sheet (measured 2026-10-15, iOS 27.0) — while
    /// `app.sheets.firstMatch` had it with its label. Then the snapshot, for
    /// a presented JsonUI screen's marker.
    static func cover(in app: XCUIApplication, root: XCUIElementSnapshot) -> ModalCover.Candidate? {
        let alert = app.alerts.firstMatch
        if alert.exists { return .alert(label: alert.label) }
        let sheet = app.sheets.firstMatch
        if sheet.exists { return .sheet(label: sheet.label) }
        return covering(root)
    }

    /// What the snapshot shows instead of the element: the first alert or
    /// sheet, else the first screen marker, in tree order.
    static func covering(_ root: XCUIElementSnapshot) -> ModalCover.Candidate? {
        var marker: ModalCover.Candidate?
        func walk(_ node: XCUIElementSnapshot) -> ModalCover.Candidate? {
            switch node.elementType {
            case .alert: return .alert(label: node.label)
            case .sheet: return .sheet(label: node.label)
            default: break
            }
            if marker == nil, node.identifier.hasPrefix(ScreenMarker.prefix) {
                marker = .screen(String(node.identifier.dropFirst(ScreenMarker.prefix.count)))
            }
            for child in node.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(root) ?? marker
    }
}

/// How `visible` names what an element is under. Pure, so the wording is
/// unit-tested; the snapshot walk that feeds it is `ViewportVisibility.covering`.
enum ModalCover {
    enum Candidate: Equatable {
        case alert(label: String)
        case sheet(label: String)
        /// A presented screen (its JsonUI screen marker), when no alert or
        /// sheet is in the snapshot — a SwiftUI sheet or cover shows up so.
        case screen(String)
    }

    static func reason(_ cover: Candidate?) -> String {
        switch cover {
        case .alert(let label):
            return label.isEmpty ? "under a modal (alert)" : "under a modal ('\(label)')"
        case .sheet(let label):
            return label.isEmpty ? "under a modal (sheet)" : "under a modal ('\(label)')"
        case .screen(let id):
            return "under a modal (screen '\(id)')"
        case nil:
            return "under a modal"
        }
    }
}
