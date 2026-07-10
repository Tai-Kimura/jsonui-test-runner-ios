import Foundation

// MARK: - Responsive condition (schema: actions.schema.json condition.responsive)

/// Value of a `when.responsive` condition or a case-level `responsive` gate:
/// either a named size-class bucket string from the render-side canonical
/// vocabulary (`compact` / `medium` / `regular` / `landscape` + hyphenated
/// combos like `regular-landscape`), or an explicit size-constraint object.
///
/// Named buckets are resolved the way the iOS renderer (sjui) resolves them —
/// via size classes, never width thresholds (see ResponsiveEvaluator).
/// Constraint objects are the cross-platform width/height escape hatch (pt on
/// iOS) and deliberately do NOT track size classes.
public enum ResponsiveCondition: Codable, Equatable {
    /// Named bucket. Kept as a raw string so a bucket added by a newer schema
    /// than this driver decodes fine and fail-safe evaluates to UNMET (skip),
    /// never run-anyway and never a hard decode error.
    case bucket(String)
    /// Explicit constraint object; present keys are ANDed, min/max inclusive.
    case constraint(ResponsiveConstraint)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self = .bucket(name)
        } else if let constraint = try? container.decode(ResponsiveConstraint.self) {
            self = .constraint(constraint)
        } else {
            throw DecodingError.typeMismatch(
                ResponsiveCondition.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a named bucket string or a constraint object"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bucket(let name):
            try container.encode(name)
        case .constraint(let constraint):
            try container.encode(constraint)
        }
    }
}

/// Explicit size constraint. Units are pt (points) on iOS, read from the
/// app-under-test's main window frame. `orientation` is kept as a raw string
/// ("portrait" / "landscape"); an unknown value never matches (fail-safe skip).
public struct ResponsiveConstraint: Codable, Equatable {
    public let minWidth: Double?
    public let maxWidth: Double?
    public let minHeight: Double?
    public let maxHeight: Double?
    public let orientation: String?

    public init(
        minWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        maxHeight: Double? = nil,
        orientation: String? = nil
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.orientation = orientation
    }
}

// MARK: - Responsive environment (pure inputs, unit-testable without a live app)

/// Size-class value as the evaluator sees it. `unspecified` means the runtime
/// could not resolve a class — every size-class-based bucket is then UNMET
/// (fail-safe skip, never run-anyway at an unknown size).
public enum SizeClassValue: Equatable {
    case compact
    case regular
    case unspecified
}

public enum ResponsiveOrientation: String, Equatable {
    case portrait
    case landscape
}

/// Device idiom as relevant to size-class derivation.
public enum DeviceIdiom: Equatable {
    case phone
    case pad
    case other
}

/// Snapshot of everything responsive evaluation needs, captured once per
/// evaluation by ResponsiveRuntime (live) or built directly in unit tests.
public struct ResponsiveEnvironment: Equatable {
    public let horizontalSizeClass: SizeClassValue
    public let verticalSizeClass: SizeClassValue
    /// App-under-test main window width in pt (current-orientation coordinates)
    public let width: Double
    /// App-under-test main window height in pt (current-orientation coordinates)
    public let height: Double
    public let orientation: ResponsiveOrientation

    public init(
        horizontalSizeClass: SizeClassValue,
        verticalSizeClass: SizeClassValue,
        width: Double,
        height: Double,
        orientation: ResponsiveOrientation
    ) {
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.width = width
        self.height = height
        self.orientation = orientation
    }
}

// MARK: - Evaluator (pure functions)

/// Pure responsive-condition evaluation. Named buckets mirror the sjui
/// renderer's size-class rules exactly (sjui_tools/lib/swiftui/views/
/// responsive_helper.rb:60-79, same in the Dynamic runtime
/// ResponsiveResolver.swift) so `when.responsive: "regular"` gates exactly the
/// layouts the renderer draws as `regular`:
///
///   compact   ⇔ horizontalSizeClass == .compact
///   medium    ⇔ horizontalSizeClass == .compact  (renderer folds medium →
///               compact — "No medium size class on iOS")
///   regular   ⇔ horizontalSizeClass == .regular
///   landscape ⇔ verticalSizeClass == .compact
///   "<tier>-landscape" = tier condition AND landscape condition
///
/// Consequences of faithful mirroring, documented here so test authors pick
/// deliberately:
/// - `medium` and `compact` name the same size-class condition on iOS; which
///   layout is actually on screen depends on which overrides the layout
///   defines (resolver priority regular > medium > compact). A test that must
///   distinguish true 3-tier widths uses a constraint object instead and
///   accepts that it does not track size classes.
/// - `landscape` (verticalSizeClass == .compact) never matches on iPad — the
///   renderer's landscape overrides never apply there either (iPad is
///   vertically regular in both orientations).
public enum ResponsiveEvaluator {

    /// Evaluate a responsive condition against the current environment.
    public static func matches(_ condition: ResponsiveCondition, in env: ResponsiveEnvironment) -> Bool {
        switch condition {
        case .bucket(let name):
            return matchesBucket(name, in: env)
        case .constraint(let constraint):
            return matchesConstraint(constraint, in: env)
        }
    }

    /// Named-bucket match per the sjui size-class rules (see type doc).
    /// Unknown bucket names (newer schema than this driver) are UNMET.
    public static func matchesBucket(_ name: String, in env: ResponsiveEnvironment) -> Bool {
        let landscapeSuffix = "-landscape"
        let requiresLandscape = name == "landscape" || name.hasSuffix(landscapeSuffix)
        if requiresLandscape && env.verticalSizeClass != .compact {
            return false
        }

        // Bare "landscape" has no tier component
        if name == "landscape" {
            return true
        }

        let tier = name.hasSuffix(landscapeSuffix)
            ? String(name.dropLast(landscapeSuffix.count))
            : name

        switch tier {
        case "compact", "medium":
            // medium folds to compact on iOS (renderer rule)
            return env.horizontalSizeClass == .compact
        case "regular":
            return env.horizontalSizeClass == .regular
        default:
            // Fail-safe: a bucket this driver does not know is unmet -> skip
            return false
        }
    }

    /// Constraint-object match: width/height in pt, min/max inclusive,
    /// present keys ANDed. Unknown orientation strings never match.
    public static func matchesConstraint(_ constraint: ResponsiveConstraint, in env: ResponsiveEnvironment) -> Bool {
        if let minWidth = constraint.minWidth, env.width < minWidth { return false }
        if let maxWidth = constraint.maxWidth, env.width > maxWidth { return false }
        if let minHeight = constraint.minHeight, env.height < minHeight { return false }
        if let maxHeight = constraint.maxHeight, env.height > maxHeight { return false }
        if let orientation = constraint.orientation, orientation != env.orientation.rawValue { return false }
        return true
    }

    /// Orientation derived from a size (square counts as landscape, matching
    /// the web driver). Used when the device orientation is unknown/flat.
    public static func deriveOrientation(width: Double, height: Double) -> ResponsiveOrientation {
        return height > width ? .portrait : .landscape
    }

    /// Derive the effective size classes from device idiom + orientation +
    /// window size, per Apple's documented size-class table:
    ///
    /// - iPad (full screen): regular / regular in both orientations.
    /// - iPhone portrait: compact / regular.
    /// - iPhone landscape: vertical compact; horizontal regular only on the
    ///   Plus/Max form factors — approximated as long side >= 896pt (XR / 11 /
    ///   every Pro Max / modern Plus). Known deviation: legacy 736pt-wide Plus
    ///   phones (6+/7+/8+, iOS <= 16) are horizontally regular in landscape
    ///   per Apple's table but report compact here.
    /// - Unknown idiom: unspecified (all size-class buckets fail-safe skip).
    ///
    /// See ResponsiveRuntime for why derivation (not the test-runner process's
    /// UIScreen traits) is the authoritative source at run time.
    public static func deriveSizeClasses(
        idiom: DeviceIdiom,
        orientation: ResponsiveOrientation,
        width: Double,
        height: Double
    ) -> (horizontal: SizeClassValue, vertical: SizeClassValue) {
        switch idiom {
        case .pad:
            // Full-screen iPad is regular/regular in both orientations. iPad
            // Split View / Slide Over would make the AUT's window horizontally
            // compact, which this derivation does not model (documented
            // limitation — the test harness does not drive multitasking).
            return (.regular, .regular)
        case .phone:
            let longSide = max(width, height)
            let horizontal: SizeClassValue =
                (orientation == .landscape && longSide >= 896) ? .regular : .compact
            let vertical: SizeClassValue = orientation == .landscape ? .compact : .regular
            return (horizontal, vertical)
        case .other:
            return (.unspecified, .unspecified)
        }
    }
}
