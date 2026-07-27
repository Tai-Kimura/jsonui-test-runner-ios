import XCTest

/// Screen identity beacon emitted by `sjui build` into generated screen views.
///
/// Tests never spell the marker — they name a screen and the driver resolves
/// it here. Canon: jsonui-cli `shared/core/screen_identity.json`.
enum ScreenMarker {
    static let prefix = "__screen_"

    static func identifier(for screenId: String) -> String {
        "\(prefix)\(screenId)"
    }

    /// Turns a failed screen assertion into one of the canonical failure
    /// classes, so the message says what went wrong rather than just "not
    /// found". The class names the likely CAUSE, not a severity — every one
    /// of them fails the assertion just the same. A missing marker anywhere
    /// points at the build (stale generated code or a stale library pin),
    /// while the previous screen's marker still being the only one present
    /// points at the app or the test: the navigation did not happen.
    static func diagnosis(screenId: String, in app: XCUIApplication) -> String {
        let target = app.descendants(matching: .any)
            .matching(identifier: identifier(for: screenId)).firstMatch
        let present = presentMarkers(in: app)

        if target.exists {
            return "marker-not-displayed: '\(screenId)' exists but is not hittable "
                + "(transition still animating, or it is covered). markers present: \(present)"
        }
        if present.isEmpty {
            return "marker-absent: no screen marker anywhere. The app's generated code or its "
                + "SwiftJsonUI pin is likely stale — rebuild with `jui build`."
        }
        return "previous-screen-only: '\(screenId)' is not present; displayed screens are \(present)"
    }

    /// Screen ids whose markers are currently in the hierarchy.
    private static func presentMarkers(in app: XCUIApplication) -> [String] {
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        return (0..<query.count).compactMap { index in
            let identifier = query.element(boundBy: index).identifier
            return identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : nil
        }
    }
}
