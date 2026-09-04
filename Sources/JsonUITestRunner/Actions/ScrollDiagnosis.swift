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
/// point inside the part of the container that is ON SCREEN — and it is the
/// bit that was missing, because "covered" and "out of view" are
/// indistinguishable from "on screen but not hittable" alone.
///
/// The first cut of that bit asked the container's FRAME, which is a
/// different rect. A probe built to test the bit found a container taller
/// than the window, where the frame contained a hit point that was off
/// screen, so the bit answered "covered" for an element nothing was
/// covering. Every unit fixture had a viewport nested inside the window, so
/// no test could see it. See `visibleArea(of:in:)`.
public enum ScrollDiagnosis {

    /// How many rects to name before summarising the rest. The list is there
    /// to narrow a guess, not to dump the ancestor chain.
    public static let atPointListLimit = 4

    /// Most elements the hit-point scan will resolve before giving up.
    ///
    /// Each one costs a snapshot resolution and this runs on a failure path,
    /// so it is bounded. Past the bound the scan reports NOTHING rather than
    /// what it managed to see: a partial list reads exactly like a complete
    /// one, and "no other element has that point" is a finding the reader
    /// will act on.
    public static let atPointScanCap = 120

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

    /// The part of a container that is actually on screen.
    ///
    /// A container's frame is NOT its visible area. A scroll view can be
    /// taller than the window — nested inside another scroller, sized to its
    /// own content, or itself scrolled partly off screen — and then its frame
    /// contains points nobody can see or tap. The first version of this
    /// discriminator asked `frame.contains(hitPoint)`, so in that shape it
    /// answered "inside" for a point that was off screen, printed the
    /// covering guesses, and ruled out the one cause that was actually
    /// acting. Measured on a probe: a container 1462 tall in a shorter
    /// window, target at y=1362, nothing in front of it, verdict "something
    /// is drawn in front of it".
    ///
    /// Returns nil when there is no container to ask about, and a null rect
    /// when the container is resolved but no part of it is on screen.
    public static func visibleArea(of viewport: CGRect?, in window: CGRect) -> CGRect? {
        guard let viewport, !viewport.isNull, !viewport.isEmpty else { return nil }
        // No usable window means the clamp cannot be applied; the raw frame
        // is the best available answer rather than a silently empty one.
        guard !window.isNull, !window.isEmpty else { return viewport }
        return viewport.intersection(window)
    }

    /// Hittability is tested at the element's centre, so that is the point
    /// the question is asked about — against what the container can actually
    /// show, not against its frame.
    public static func placement(element: CGRect, viewport: CGRect?, window: CGRect) -> Placement {
        placement(element: element, visible: visibleArea(of: viewport, in: window))
    }

    /// The verdict and the rect printed beside it must be the same quantity,
    /// so both come from one computed visible area rather than from two
    /// calls that could drift apart.
    private static func placement(element: CGRect, visible: CGRect?) -> Placement {
        guard let visible, !element.isNull, !element.isEmpty else {
            return .noViewport
        }
        // A container was resolved, but none of it is on screen. Nothing can
        // be in front of the element here, because nothing here is visible.
        guard !visible.isNull, !visible.isEmpty else { return .beyondViewport }
        let hitPoint = CGPoint(x: element.midX, y: element.midY)
        return visible.contains(hitPoint) ? .withinViewport : .beyondViewport
    }

    /// One element that has the hit point inside its frame.
    ///
    /// Frames only. XCUITest does not expose z-order, so "in front of" is not
    /// available and is never claimed — but "is even at that point" was never
    /// asked either, and it can be. The list this feeds replaced a fixed
    /// sentence that named a bottom bar as a candidate on a screen whose
    /// scroll container reached the window's bottom edge, leaving no room for
    /// one; a reader took that guess for a finding and filed a layout bug.
    public struct AtPoint: Equatable {
        public let label: String
        public let frame: CGRect
        public init(label: String, frame: CGRect) {
            self.label = label
            self.frame = frame
        }
    }

    /// - Parameters:
    ///   - atHitPoint: elements whose frame contains the hit point, target
    ///     excluded. `nil` means the scan did not run — which must not read
    ///     the same as an empty list, because an empty list is a finding.
    ///   - keyboard: the on-screen keyboard's frame, when one is up. The only
    ///     candidate of the five that can be turned into an observation: its
    ///     rect is available and `keyboardIsVisible` already distinguishes a
    ///     real keyboard from the phantom that outlives it.
    public static func message(
        id: String,
        element: CGRect,
        viewport: CGRect?,
        viewportLabel: String,
        appWindow: CGRect,
        atHitPoint: [AtPoint]? = nil,
        keyboard: CGRect? = nil
    ) -> String {
        let visible = visibleArea(of: viewport, in: appWindow)
        let place = placement(element: element, visible: visible)
        let viewportText = viewport.map { "\($0)" } ?? "not resolved"
        // The frame and the part of it on screen are printed separately,
        // because when they differ the difference IS the finding.
        let visibleText = visible.map { $0.isNull || $0.isEmpty ? "none of it on screen" : "\($0)" }
            ?? "not resolved"
        var lines = [
            "scrollUntilVisible '\(id)': scrolled both ways and it is still not hittable",
            "  observed: element \(element), \(viewportLabel) viewport \(viewportText), "
                + "visible part of it \(visibleText), app window \(appWindow); hit point "
                + "\(place == .withinViewport ? "inside" : place == .beyondViewport ? "OUTSIDE" : "unknown against")"
                + " that visible part",
        ]
        let hitPoint = CGPoint(x: element.midX, y: element.midY)
        let keyboardCovers = keyboard.map { !$0.isNull && !$0.isEmpty && $0.contains(hitPoint) } ?? false

        switch place {
        case .withinViewport:
            // The keyboard is the one candidate of the five whose rect can be
            // had, so when it holds the point that stops being a guess.
            if keyboardCovers, let keyboard {
                lines.append("  observed: the keyboard is at that point (keyboard \(keyboard))")
            }
            if let atHitPoint {
                if atHitPoint.isEmpty {
                    // A finding, not an absence of one: nothing is at that
                    // point, so "covered" does not explain it.
                    lines.append("  observed: no other element has that point inside its frame")
                } else {
                    let listed = atHitPoint
                        .sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                        .prefix(atPointListLimit)
                        .map { "\($0.label) \($0.frame)" }
                        .joined(separator: ", ")
                    let more = atHitPoint.count > atPointListLimit
                        ? " (+\(atHitPoint.count - atPointListLimit) more)" : ""
                    lines.append("  observed: \(atHitPoint.count) element(s) have that point inside "
                        + "their frame, smallest first: \(listed)\(more)")
                }
            }
            var guesses = ["an overlay or sheet", "a bar that overlaps the scroll view", "another window"]
            if !keyboardCovers { guesses.insert("the keyboard", at: 1) }
            if atHitPoint?.isEmpty == true {
                lines.append("  candidates: nothing is at that point, so this is unlikely to be "
                    + "covering — hittability may be misreported here (remote-process UI such as a "
                    + "photo picker or a hardware-backed keyboard does that), or the element moved "
                    + "between the frame read and the hit test")
            } else {
                lines.append("  candidates: something is drawn in front of it — "
                    + guesses.joined(separator: ", ")
                    + (atHitPoint == nil
                        ? "" : ". Which of the listed rects is in front is not available: XCUITest does not expose z-order"))
            }
            lines.append("  ruled out: not a scrolling problem; the container is already showing that point")
        case .beyondViewport:
            lines.append("  candidates: the container cannot bring it further (content ends, or it "
                + "lies outside this container), the container's own visible part does not reach "
                + "it (its frame runs past the window, or it is itself scrolled off screen), or "
                + "the wrong container was named")
            lines.append("  ruled out: nothing needs to be covering it — its hit point is not in the "
                + "part of the viewport that is on screen")
        case .noViewport:
            lines.append("  candidates: unknown — no scroll container was resolved, so 'covered' and "
                + "'out of view' cannot be told apart here. Name the container on the step to get that bit")
        }
        lines.append("  continuing; the step that uses it must resolve it")
        return lines.joined(separator: "\n")
    }
}
