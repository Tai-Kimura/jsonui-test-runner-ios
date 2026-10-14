import XCTest

/// `visible` / `notVisible` and `when: { visible }`: whether an element is in
/// the viewport (VisibleFrame.inViewport), read from one accessibility
/// snapshot of the app — the element, and the frame of every scroll
/// container above it, which XCUIElement has no way to ask for.
///
/// The element is the identifier's first match in tree order, the one
/// `descendants(matching: .any).matching(identifier:).firstMatch` returns.
enum ViewportVisibility {
    /// The element types whose frame is the window onto content that scrolls.
    static let clippingTypes: Set<XCUIElement.ElementType> = [.scrollView, .table, .collectionView, .webView]

    /// The element's frame and the rectangles that clip it, or nil when no
    /// element has the identifier.
    static func locate(id: String, in app: XCUIApplication) -> (frame: CGRect, clips: [CGRect])? {
        guard let root = try? app.snapshot() else { return nil }
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
        guard let found = locate(id: id, in: app) else { return false }
        return VisibleFrame.inViewport(found.frame, clips: found.clips)
    }
}
