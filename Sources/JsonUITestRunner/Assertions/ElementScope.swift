import XCTest

/// The one resolution of a step's target id, used by every action,
/// assertion and condition that targets an element by id (see
/// `WithinScope` for what `within` means).
///
/// Without `within` every query here is exactly the one the executors made
/// before: `app.descendants(matching:).matching(identifier:)`.
enum ElementScope {
    /// One look, no waiting.
    enum Look {
        case found(XCUIElement)
        /// `within` was given and no element has its id.
        case containerMissing
        /// The target is not there (inside the container, when given).
        case targetMissing
    }

    /// The container `within` names (its first match), unwaited.
    static func container(_ within: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: within).firstMatch
    }

    /// Every element of `type` with `id` in scope: under the container's
    /// descendants when `within` is given, else the app's. A query under a
    /// container that is not there matches nothing.
    static func query(
        id: String, within: String?, type: XCUIElement.ElementType = .any, in app: XCUIApplication
    ) -> XCUIElementQuery {
        guard let within else { return app.descendants(matching: type).matching(identifier: id) }
        return container(within, in: app).descendants(matching: type).matching(identifier: id)
    }

    /// The first element with `id` in scope, unwaited.
    static func element(id: String, within: String?, in app: XCUIApplication) -> XCUIElement {
        query(id: id, within: within, in: app).firstMatch
    }

    /// One look at the target.
    static func look(id: String, within: String?, in app: XCUIApplication) -> Look {
        if let within, !container(within, in: app).exists { return .containerMissing }
        let element = element(id: id, within: within, in: app)
        return element.exists ? .found(element) : .targetMissing
    }

    /// The number of elements with `id` in scope; nil when the container is
    /// missing (there is nothing to count in).
    static func count(id: String, within: String?, in app: XCUIApplication) -> Int? {
        if let within, !container(within, in: app).exists { return nil }
        return query(id: id, within: within, in: app).count
    }

    /// Why a look found nothing, in the assertions' words: "does not exist"
    /// without `within` (unchanged), the `WithinScope` messages with it.
    static func reason(_ look: Look, id: String, within: String?) -> String? {
        switch look {
        case .found:
            return nil
        case .containerMissing:
            return WithinScope.containerNotFound(within: within ?? "", id: id)
        case .targetMissing:
            guard let within else { return "does not exist" }
            return WithinScope.targetNotFound(id: id, within: within)
        }
    }

    /// Wait for the target. Without `within`: the target's own
    /// `waitForExistence(timeout:)`, as the executors did. With it: the
    /// container first, then the target inside it, both inside one deadline
    /// (the target gets at least one look).
    static func wait(id: String, within: String?, timeout: TimeInterval, in app: XCUIApplication) -> Look {
        guard let within else {
            let element = element(id: id, within: nil, in: app)
            return element.waitForExistence(timeout: timeout) ? .found(element) : .targetMissing
        }
        let deadline = Date().addingTimeInterval(timeout)
        let box = container(within, in: app)
        guard box.waitForExistence(timeout: timeout) else { return .containerMissing }
        let element = box.descendants(matching: .any).matching(identifier: id).firstMatch
        let remaining = max(deadline.timeIntervalSinceNow, 0)
        if element.exists || (remaining > 0 && element.waitForExistence(timeout: remaining)) {
            return .found(element)
        }
        return box.exists ? .targetMissing : .containerMissing
    }

    /// The `hidden` predicate: none of the elements with the id in scope is
    /// drawn (WithinScope.hiddenHolds). A missing container fails it.
    static func isHidden(id: String, within: String?, in app: XCUIApplication) -> Bool {
        guard let total = count(id: id, within: within, in: app) else {
            return WithinScope.hiddenHolds(containerMissing: true, drawn: [])
        }
        // Every match is in XCUITest's tree, and being in the tree is what
        // "drawn" is on iOS (see `hiddenHolds`); all of them are judged, not
        // the first.
        return WithinScope.hiddenHolds(containerMissing: false, drawn: Array(repeating: true, count: total))
    }
}
