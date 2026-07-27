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
            let covering = hittableScreens(in: app, excluding: screenId)
            if covering.isEmpty {
                return "marker-not-displayed: '\(screenId)' exists but is not hittable, and no "
                    + "other screen is displayed either — the transition is probably still "
                    + "animating. markers present: \(present)"
            }
            return "covered-by-screen: '\(screenId)' is present but \(covering) is on top "
                + "(a sheet or fullScreenCover). markers present: \(present)"
        }
        if present.isEmpty {
            return "marker-absent: no screen marker anywhere. Either the app's generated code or "
                + "its SwiftJsonUI pin is stale — rebuild with `jui build` — or this screen's "
                + "generated view is never rendered (the app draws its own view instead), in "
                + "which case declare the id in jui.config.json under test.appOwnedScreens and "
                + "apply the marker by hand."
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

    /// Screen ids OTHER than `screenId` whose markers are reachable.
    ///
    /// This is what tells "another screen took over" apart from "my own app
    /// put something on top of me". A sheet or fullScreenCover is another
    /// screen and carries its own marker; a coach mark, a loading scrim or a
    /// hand-rolled modal carries none.
    static func hittableScreens(in app: XCUIApplication, excluding screenId: String) -> [String] {
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        return (0..<query.count).compactMap { index -> String? in
            let element = query.element(boundBy: index)
            let identifier = element.identifier
            guard identifier.hasPrefix(prefix) else { return nil }
            let id = String(identifier.dropFirst(prefix.count))
            guard id != screenId, element.isHittable else { return nil }
            return id
        }
    }
}
