import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where a tap goes once an element has been accepted by existence and frame.
public enum TapRoute: Equatable {
    /// XCTest agrees the element is hittable: tap the element itself.
    case element
    /// Hittability is broken (remote-process UI such as PHPicker, iPad
    /// keyboard keys) but the frame is a real on-screen rect: tap its center.
    case frameCenter
    /// Not hittable and the frame's center lies outside the app window: the
    /// reported frame is not a place a finger can reach.
    case offscreen
    /// Not hittable and no frame at all: nothing to aim at.
    case noFrame
    /// Not hittable, and the frame's center lies inside the on-screen
    /// software keyboard: a coordinate tap there types a key (measured
    /// 2026-10-15, iPhone 17 / iOS 27.0: a sign-in button under a keyboard
    /// that came back after typeText, the tap typed one more character into
    /// the password field and the button was never pressed).
    case underKeyboard
}

/// Whether a scroll target is where the next step can act on it.
///
/// `exists && !frame.isEmpty` is not that question: an XCUITest element keeps
/// existing, with a real frame, while it sits far outside the viewport, so
/// `scrollUntilVisible` reported success without swiping once (measured
/// 2026-09-04: a section at y=1155 on an 874pt-tall window, 281pt below the
/// last visible row, ended the step immediately). Until 1.9.2 the following
/// `tap` hid it, because XCUIElement.tap() resolves an element by scrolling
/// it into view first; 1.9.3 refused that shape before tapping and the
/// no-op scroll became a failure.
///
/// 1.9.4 stopped on "hittable OR the frame intersects the window", taking
/// intersection as a stand-in for hittability. It is not one: intersecting
/// the window says nothing about being COVERED. Measured 2026-09-04 on a
/// screen with a bottom fixed bar — the bar spans 818..874, the scroll
/// stopped with the target at 818..850 exactly underneath it, and the
/// frame-center tap landed on the bar and opened another screen. One more
/// swipe would have brought the target clear.
///
/// So hittability — which IS the hit test, "visible and nothing on top" —
/// decides when to stop. Intersection keeps only its honest job: telling a
/// failed search whether the target was on screen all along (a covering
/// bar) or never arrived, which is the difference between two very
/// different repairs.
public enum ScrollVisibility {
    /// The stop condition. Deliberately not "or it intersects the window":
    /// see above, that is how a scroll came to rest under a fixed bar.
    public static func canStopScrolling(isHittable: Bool) -> Bool {
        isHittable
    }

    /// Diagnostic only. Whether any of the frame is inside the window —
    /// intersection, not "the center is inside", because an element taller
    /// than the viewport is on screen while its center is not.
    public static func onScreen(isHittable: Bool, frame: CGRect, appFrame: CGRect) -> Bool {
        if isHittable { return true }
        if frame.isNull || frame.isInfinite || frame.isEmpty { return false }
        return appFrame.intersects(frame)
    }
}

/// A target in a scroll view that has come to rest under the navigation bar.
///
/// `isHittable` does not answer this. A scroll view runs up behind the bar, and
/// measured 2026-11-06 (iPhone 17, iOS 27.2, keyboard up, bar at 62..116): a
/// SelectBox centred at y 30, 45 or 65 reported isHittable true, no scroll to
/// visible ran, and tap, doubleTap, selectOption and input all landed on the
/// bar and pressed nothing. At y 55 and 75 it reported false; from y 85 the tap
/// reached the box. Without a navigation bar the same box was pressable from
/// y 30 to 85, and under a tab bar isHittable answered false. So the band is the
/// navigation bar's, from the window's top to the bar's bottom, whatever
/// isHittable says.
///
/// A keyboard makes this common: the band left to see in is about 370pt, one
/// swipe travels further than that, and the scroll comes to rest past the
/// target. The target can be under the bar then, with nothing else to say so.
///
/// Only a target inside a scroll container counts. A button of the bar itself
/// is inside the band and is the thing to press.
public enum TopBarCover {
    /// Whether the target's centre is in the bar's band. `bar` is nil when
    /// the screen has no navigation bar.
    public static func covers(_ frame: CGRect, bar: CGRect?, inScroller: Bool) -> Bool {
        guard inScroller, let bar, !bar.isEmpty, !bar.isNull else { return false }
        if frame.isNull || frame.isInfinite || frame.isEmpty { return false }
        return frame.midY < bar.maxY && frame.midX >= bar.minX && frame.midX <= bar.maxX
    }

    /// Where a target can be seen and pressed: below the bar, above whatever
    /// ends first of the scroller, the keyboard and the window.
    public static func band(bar: CGRect?, scroller: CGRect, keyboard: CGRect?, window: CGRect) -> CGRect {
        let top = max(bar?.maxY ?? scroller.minY, scroller.minY, window.minY)
        var bottom = min(scroller.maxY, window.maxY)
        if let keyboard, !keyboard.isNull, !keyboard.isEmpty { bottom = min(bottom, keyboard.minY) }
        return CGRect(x: scroller.minX, y: top, width: scroller.width, height: max(0, bottom - top))
    }

    /// One drag that moves the target towards the band's middle, without
    /// leaving the band: nil when the target's centre is already inside it, or
    /// there is no band to drag in. Longer ways take several drags.
    public static func drag(for frame: CGRect, in band: CGRect, margin: CGFloat = 12) -> (from: CGFloat, to: CGFloat)? {
        guard band.height > margin * 2 + 20 else { return nil }
        if frame.midY >= band.minY && frame.midY <= band.maxY { return nil }
        let room = band.height - margin * 2
        let wanted = band.midY - frame.midY
        let travel = min(abs(wanted), room)
        if wanted > 0 { return (band.minY + margin, band.minY + margin + travel) }
        return (band.maxY - margin, band.maxY - margin - travel)
    }
}

/// The one decision `tap`, its ghost-tap retry and the keyboard dismiss key
/// share. Pure, so it is unit-tested with the measured shapes: a PHPicker
/// thumbnail at {{0, 312}, {132.9, 133}} on a 402pt-wide simulator that
/// XCTest reports as not hittable (2026-09-03, iOS 26.4), an iPad dismiss
/// key with a pre-animation frame ~350pt below the screen (2026-07-21).
///
/// `keyboard` is the on-screen keyboard's frame, nil when none is up. Only
/// the coordinate route consults it: a hittable element is in front of the
/// keyboard by definition, and the off-screen route taps the element, not a
/// point. The keyboard's own keys never pass one — the dismiss-key path asks
/// without it, because aiming inside the keyboard is that path's job.
public enum TapRouting {
    public static func route(
        isHittable: Bool, frame: CGRect, appFrame: CGRect, keyboard: CGRect? = nil
    ) -> TapRoute {
        if isHittable { return .element }
        if frame.isNull || frame.isInfinite || frame.isEmpty { return .noFrame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard appFrame.contains(center) else { return .offscreen }
        if let keyboard, !keyboard.isNull, !keyboard.isEmpty, keyboard.contains(center) {
            return .underKeyboard
        }
        return .frameCenter
    }
}

/// Whether a frame has a visible area: at least 1pt on BOTH sides.
///
/// SwiftJsonUI gives every accessibility container a 0.5pt anchor child (an
/// `.overlay` Color.clear marked `.accessibilityElement(children: .ignore)`),
/// so a container with nothing in it still reports a frame — measured on iOS
/// 26.5: an empty flow Collection read {16,131}{0.667 x 0.667} (the 0.5pt
/// rounded to pixels), isHittable true, so `visible` was true for a box that
/// draws nothing. Android does not find such an element visible (its drawn
/// box is 0 x 0), and by the user's ruling (2026-10-06) neither does this
/// driver: a frame under 1pt on either side is not visible. `exists` is
/// unaffected — the element is still there.
public enum VisibleFrame {
    /// The smallest side, in points, that counts as something drawn.
    public static let minimumSide: CGFloat = 1

    public static func hasArea(_ frame: CGRect) -> Bool {
        if frame.isNull || frame.isInfinite { return false }
        return frame.width >= minimumSide && frame.height >= minimumSide
    }

    /// The part of `frame` that the viewport shows: `frame` cut by every
    /// rectangle that clips it — the app's frame and each scroll container
    /// it sits in. `.null` when nothing of it is shown.
    public static func shownPart(of frame: CGRect, clips: [CGRect]) -> CGRect {
        if frame.isNull || frame.isInfinite { return .null }
        return clips.reduce(frame) { part, clip in part.isNull ? part : part.intersection(clip) }
    }

    /// `visible` / `notVisible`: some of the element is in the viewport — at
    /// least 1pt each way of it is inside the app's frame and inside every
    /// scroll container it sits in. Not "its centre": Android (the baseline,
    /// UiAutomator's isVisibleToUser) calls a Label visible when only 5dp of
    /// it shows at the bottom of a ScrollView, its centre outside (measured
    /// 2026-10-14, KotlinJsonUI 2.43.12). Until this, iOS read the frame
    /// alone, so a Label scrolled out of a 200pt ScrollView was `visible` —
    /// and, not being hittable, `notVisible` too.
    public static func inViewport(_ frame: CGRect, clips: [CGRect]) -> Bool {
        hasArea(shownPart(of: frame, clips: clips))
    }
}
