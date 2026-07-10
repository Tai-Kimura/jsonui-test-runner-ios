import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Captures the live responsive environment (size classes / window size /
/// orientation) from the XCUITest runner process for ResponsiveEvaluator.
///
/// ## Size-class source (and why it is a derivation, not UIScreen traits)
///
/// The renderer resolves responsive layout from the app-under-test's SwiftUI
/// `horizontalSizeClass` / `verticalSizeClass` environment. The XCUITest
/// runner process cannot read the AUT's trait environment directly, so two
/// candidate sources were considered:
///
/// 1. `UIScreen.main.traitCollection` in the runner process. REJECTED on
///    evidence: the smoke test (testScreenTraitCollectionSmoke) observed it
///    returning `.unspecified` for BOTH size classes in the test process on
///    the simulator (iPad (A16), iOS 26.5) — screen traits only resolve
///    inside a UIKit app's own trait environment. Even where they resolve,
///    they are per-process values: the runner app is backgrounded while the
///    AUT is frontmost, so its interface orientation — and therefore the
///    orientation-dependent size classes on iPhone — is not guaranteed to
///    track rotations driven by `XCUIDevice.shared.orientation` (the
///    setOrientation action). A stale verticalSizeClass would silently
///    mis-gate every `landscape` bucket right after the action whose entire
///    purpose is to flip it.
///
/// 2. Derivation from device idiom + current orientation + the AUT's main
///    window frame, per Apple's documented size-class table
///    (ResponsiveEvaluator.deriveSizeClasses). All three inputs are
///    rotation-fresh: the window frame comes back from the AUT in
///    current-orientation coordinates, and the orientation is the very value
///    setOrientation just wrote.
///
/// Source 2 is authoritative. Known limits (documented on deriveSizeClasses):
/// iPad Split View / Slide Over is not modeled (the AUT window would be
/// horizontally compact; we report regular — the harness does not drive
/// multitasking), and legacy 736pt Plus phones report horizontally compact in
/// landscape. `UIScreen.main.bounds` is used only as a size fallback when the
/// AUT exposes no window.
public enum ResponsiveRuntime {

    /// Evaluate a responsive condition against the live environment.
    public static func matches(_ condition: ResponsiveCondition, app: XCUIApplication) -> Bool {
        return ResponsiveEvaluator.matches(condition, in: currentEnvironment(app: app))
    }

    /// Snapshot the current responsive environment from the AUT + device.
    public static func currentEnvironment(app: XCUIApplication) -> ResponsiveEnvironment {
        let size = windowSize(app: app)
        let orientation = currentOrientation(width: size.width, height: size.height)
        let classes = ResponsiveEvaluator.deriveSizeClasses(
            idiom: currentIdiom,
            orientation: orientation,
            width: size.width,
            height: size.height
        )
        return ResponsiveEnvironment(
            horizontalSizeClass: classes.horizontal,
            verticalSizeClass: classes.vertical,
            width: size.width,
            height: size.height,
            orientation: orientation
        )
    }

    // MARK: - Live inputs

    /// Width/height in pt from the AUT's main window frame (reported in
    /// current-orientation coordinates), falling back to the screen bounds
    /// when the app exposes no window (e.g. not yet launched).
    private static func windowSize(app: XCUIApplication) -> (width: Double, height: Double) {
        let window = app.windows.firstMatch
        if window.exists {
            let frame = window.frame
            if frame.width > 0 && frame.height > 0 {
                return (Double(frame.width), Double(frame.height))
            }
        }
        #if canImport(UIKit)
        let bounds = UIScreen.main.bounds
        return (Double(bounds.width), Double(bounds.height))
        #else
        return (0, 0)
        #endif
    }

    /// Orientation from XCUIDevice.shared.orientation, falling back to a
    /// width/height comparison when the device reports unknown/flat
    /// (faceUp/faceDown), where interface orientation is not implied.
    private static func currentOrientation(width: Double, height: Double) -> ResponsiveOrientation {
        #if canImport(UIKit)
        switch XCUIDevice.shared.orientation {
        case .portrait, .portraitUpsideDown:
            return .portrait
        case .landscapeLeft, .landscapeRight:
            return .landscape
        default:
            break // .unknown / .faceUp / .faceDown -> derive from the frame
        }
        #endif
        return ResponsiveEvaluator.deriveOrientation(width: width, height: height)
    }

    private static var currentIdiom: DeviceIdiom {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .phone
        case .pad:
            return .pad
        default:
            return .other
        }
        #else
        return .other
        #endif
    }
}
