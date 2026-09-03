import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What to say when a scroll finished and the target is still not hittable.
///
/// The first version of this message named its guesses as if they were the
/// finding — "something is probably covering it (a bottom fixed bar, a tab
/// bar, the keyboard)". One of those guesses happened to exist in the app
/// that read it, so a wrong cause was carried across two runs and reported
/// twice before someone read the layout and found the bar was a SIBLING of
/// the scroll view, not on top of it. The element was simply below what the
/// container could show.
///
/// So: the observation is printed as the observation, the guesses are
/// labelled as guesses, and a discriminator decides WHICH set of guesses is
/// worth printing. That discriminator is one bit — is the element's hit
/// point inside the container's viewport — and it is the bit that was
/// missing, because "covered" and "out of view" are indistinguishable from
/// "on screen but not hittable" alone.
public enum ScrollDiagnosis {

    public enum Placement: Equatable {
        /// Inside the viewport that should be showing it, yet not hittable:
        /// something is in front.
        case withinViewport
        /// Outside it: nothing needs to be covering it.
        case beyondViewport
        /// No container was resolved (the whole app was the swipe surface),
        /// so this bit cannot be computed and must not be implied.
        case noViewport
    }

    /// Hittability is tested at the element's centre, so that is the point
    /// the question is asked about.
    public static func placement(element: CGRect, viewport: CGRect?) -> Placement {
        guard let viewport, !viewport.isEmpty, !element.isNull, !element.isEmpty else {
            return .noViewport
        }
        let hitPoint = CGPoint(x: element.midX, y: element.midY)
        return viewport.contains(hitPoint) ? .withinViewport : .beyondViewport
    }

    public static func message(
        id: String,
        element: CGRect,
        viewport: CGRect?,
        viewportLabel: String,
        appWindow: CGRect
    ) -> String {
        let place = placement(element: element, viewport: viewport)
        let viewportText = viewport.map { "\($0)" } ?? "not resolved"
        var lines = [
            "scrollUntilVisible '\(id)': scrolled both ways and it is still not hittable",
            "  observed: element \(element), \(viewportLabel) viewport \(viewportText), "
                + "app window \(appWindow); hit point "
                + "\(place == .withinViewport ? "inside" : place == .beyondViewport ? "OUTSIDE" : "unknown against")"
                + " that viewport",
        ]
        switch place {
        case .withinViewport:
            lines.append("  candidates: something is drawn in front of it — an overlay or sheet, "
                + "the keyboard, a bar that overlaps the scroll view, another window")
            lines.append("  ruled out: not a scrolling problem; the container is already showing that point")
        case .beyondViewport:
            lines.append("  candidates: the container cannot bring it further (content ends, or it "
                + "lies outside this container), or the wrong container was named")
            lines.append("  ruled out: nothing needs to be covering it — its hit point is not in the viewport")
        case .noViewport:
            lines.append("  candidates: unknown — no scroll container was resolved, so 'covered' and "
                + "'out of view' cannot be told apart here. Name the container on the step to get that bit")
        }
        lines.append("  continuing; the step that uses it must resolve it")
        return lines.joined(separator: "\n")
    }
}
