import Foundation
#if canImport(XCTest)
import XCTest
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Resolving, applying and observing the orientation a run executes in.
///
/// Precedence, highest first:
///
///     a `setOrientation` step   the rotation it performs, while it lasts
///     the file's `orientation`  the whole file
///     the run default           the row for this device's tier
///
/// The run default is applied ONCE, when the run starts, before the readiness
/// gate and before `setup`. Applied later, the readiness gate and every setup
/// step would have run in whatever orientation the device booted in, and the
/// run would not be the run the file asked for.
public enum OrientationRuntime {

    // MARK: - Tier

    /// The sidecar tier this device reads, or nil when the size class is
    /// unresolved.
    ///
    /// ⚠️ `medium` folds into `compact` on iOS — the renderer rule this
    /// driver's `responsive` buckets already follow (`ResponsiveEvaluator`
    /// matches both against `horizontalSizeClass == .compact`). So a compact
    /// device reads `compact` and falls back to `medium`: a project that
    /// declared only `medium` meant it for this device, and ignoring it would
    /// silently drop a declaration that `responsive` honours. The order is
    /// fixed rather than "whichever is present" so that a table declaring BOTH
    /// resolves the same way on every run.
    public static func tier(
        horizontalSizeClass: SizeClassValue,
        declaredTiers: Set<String>
    ) -> String? {
        switch horizontalSizeClass {
        case .regular:
            return "regular"
        case .compact:
            if declaredTiers.contains("compact") { return "compact" }
            if declaredTiers.contains("medium") { return "medium" }
            return "compact"
        case .unspecified:
            // Fail-safe, matching the responsive gate: at an unknown size no
            // bucket is met, so no default is applied and the run says so
            // rather than guessing a tier.
            return nil
        }
    }

    // MARK: - Resolution

    /// What this run should be in: the file's declaration, else the run
    /// default for this tier, else nothing.
    ///
    /// Returns nil when nothing declared one. Nil is NOT "portrait": a device
    /// left in the orientation it booted in is a real and different state, and
    /// reporting a default nobody chose is how the original defect stayed
    /// invisible.
    public static func resolveDeclared(
        fileOrientation: String?,
        defaults: RunDefaults.Load,
        tier: String?
    ) -> Orientation? {
        // ⚠️ A file that declares the key AT ALL has spoken, even if what it
        // said is not a value this driver knows. Falling through to the config
        // default would run the file in an orientation it did not ask for,
        // with nothing saying so — the same silence as no declaration, but
        // reached from a typo. The CLI validates this value before install, so
        // this branch is defence in depth rather than the expected path.
        if let fileOrientation {
            return Orientation(rawValue: fileOrientation)
        }
        guard let tier, let value = defaults.orientation(forTier: tier) else {
            return nil
        }
        return Orientation(rawValue: value)
    }

    /// What this case asked for: the last `setOrientation` it performs, else
    /// the run-scoped value.
    ///
    /// The LAST one, not the first: a case that rotates and rotates back
    /// declared the orientation it ended in, which is also the one `observed`
    /// is measured against. Steps are read rather than the executor being
    /// instrumented, so the answer is the same whether or not the case reached
    /// that step — a case that failed before rotating reports the orientation
    /// it asked for and the one it was actually in, and the pair disagreeing
    /// is exactly the signal worth keeping.
    public static func declaredForCase(
        steps: [TestStep], runDeclared: Orientation?
    ) -> Orientation? {
        for step in steps.reversed() where step.action == "setOrientation" {
            if let raw = step.orientation, let value = Orientation(rawValue: raw) {
                return value
            }
        }
        return runDeclared
    }

    // MARK: - Application

    #if canImport(XCTest) && canImport(UIKit)
    /// Rotate the device to `orientation`. Absolute, never relative: the value
    /// names the result, and `XCUIDevice.orientation` takes an absolute
    /// interface orientation, so there is no "natural" for this to be relative
    /// to. (The Android driver had exactly that defect — both of its arms were
    /// natural-relative, so on a tablet whose natural orientation is landscape
    /// they inverted.)
    public static func apply(_ orientation: Orientation) {
        switch orientation {
        case .portrait:
            XCUIDevice.shared.orientation = .portrait
        case .landscape:
            // One deterministic pick; the test vocabulary does not distinguish
            // left from right. Matches `setOrientation`.
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    /// The orientation the device is ACTUALLY in.
    ///
    /// ⚠️ Asked of the device, never derived from what was declared. Derived,
    /// the pair `declaredOrientation` / `observedOrientation` would agree by
    /// construction and measure nothing — and the disagreement is the whole
    /// reason both are reported. Routed through `ResponsiveRuntime` so this
    /// answer and the `responsive` gate's answer cannot drift apart: a case
    /// gated on `orientation: portrait` and a row reporting landscape would be
    /// two truths about one device.
    public static func observe(app: XCUIApplication) -> Orientation? {
        let env = ResponsiveRuntime.currentEnvironment(app: app)
        return Orientation(rawValue: env.orientation.rawValue)
    }
    #endif
}
