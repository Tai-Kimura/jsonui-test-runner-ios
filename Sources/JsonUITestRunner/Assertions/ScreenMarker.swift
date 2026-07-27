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
    /// found". The distinction matters: a missing marker anywhere is stale
    /// generated code or a stale library pin (an infrastructure problem),
    /// while the previous screen's marker still being the only one present
    /// means the navigation genuinely did not happen (a test failure).
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
