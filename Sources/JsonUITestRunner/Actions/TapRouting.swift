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

/// The one decision `tap`, its ghost-tap retry and the keyboard dismiss key
/// share. Pure, so it is unit-tested with the measured shapes: a PHPicker
/// thumbnail at {{0, 312}, {132.9, 133}} on a 402pt-wide simulator that
/// XCTest reports as not hittable (2026-09-03, iOS 26.4), an iPad dismiss
/// key with a pre-animation frame ~350pt below the screen (2026-07-21).
public enum TapRouting {
    public static func route(isHittable: Bool, frame: CGRect, appFrame: CGRect) -> TapRoute {
        if isHittable { return .element }
        if frame.isNull || frame.isInfinite || frame.isEmpty { return .noFrame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return appFrame.contains(center) ? .frameCenter : .offscreen
    }
}
