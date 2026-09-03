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
