import Foundation

/// Run-scoped defaults installed beside the tests (`jsonui-test-run.json`).
///
/// The CLI cannot resolve a default orientation at install time: one installed
/// bundle is executed by every lane — phone and tablet run the same files
/// against different devices — so a resolved value would be right for at most
/// one of them. What it installs instead is the TABLE: tier -> orientation is
/// a statement about form factors, and the driver reads the row for the tier
/// it resolves at run time.
///
/// The file is written on EVERY install, including when it declares nothing.
/// That is the point, and it is why the states below are separate: a sidecar
/// written only when a default exists would make "nothing was declared" and
/// "installed by a CLI too old to have this feature" one observation on the
/// device. `x-requires-driver` cannot separate them here either, because this
/// driver's version is not readable from a project tree.
public enum RunDefaults {

    /// The name the CLI writes at the root of the installed bundle.
    public static let sidecarFilename = "jsonui-test-run.json"

    /// The only shape this driver claims to understand.
    public static let supportedSchemaVersion = 1

    /// What the sidecar said, or why nothing could be read from it.
    ///
    /// ⚠️ Four cases, deliberately not folded into "empty table". Folded, a
    /// driver reading a file it does not understand would behave exactly like
    /// one reading a file that declares nothing, and the run would report a
    /// default it never applied — in the orientation nobody chose, with every
    /// assertion still passing.
    public enum Load: Equatable {
        /// The file was there and understood. May still declare no tiers.
        case table([String: String])
        /// No sidecar at the expected path — an install by a CLI without it.
        case absent
        /// Present but unreadable (not JSON, or not an object).
        case unreadable(String)
        /// Present and readable, but written by a newer CLI than this driver.
        case unknownVersion(Int)

        /// The declared orientation for `tier`, or nil. Only `.table` can
        /// answer; every other case is "no answer", never "no default".
        public func orientation(forTier tier: String) -> String? {
            guard case .table(let table) = self else { return nil }
            return table[tier]
        }

        /// Tiers this table actually declares. Empty for every non-`.table`
        /// case, which is what makes the tier fallback fail closed: with no
        /// table there is nothing to fall back to.
        public var declaredTiers: Set<String> {
            guard case .table(let table) = self else { return [] }
            return Set(table.keys)
        }

        /// One line for the results/report, naming which of the four it was.
        public var reason: String? {
            switch self {
            case .table: return nil
            case .absent:
                return "no \(RunDefaults.sidecarFilename) beside the tests — "
                     + "installed by a CLI that does not write one"
            case .unreadable(let why):
                return "\(RunDefaults.sidecarFilename) could not be read: \(why)"
            case .unknownVersion(let version):
                return "\(RunDefaults.sidecarFilename) declares schemaVersion "
                     + "\(version); this driver understands "
                     + "\(RunDefaults.supportedSchemaVersion)"
            }
        }
    }

    /// Read the sidecar from a directory.
    public static func load(from directory: URL) -> Load {
        let url = directory.appendingPathComponent(sidecarFilename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .absent
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return .unreadable("not a JSON object")
        }
        // A missing version is version 1: the first CLI to write this file
        // wrote the key, so absence means a hand-written or truncated file
        // rather than an older shape. Treated as understood, because a
        // conservative reject here would turn a typo into silence.
        let version = root["schemaVersion"] as? Int ?? supportedSchemaVersion
        guard version == supportedSchemaVersion else {
            return .unknownVersion(version)
        }
        // Only string values survive. A value this driver does not recognise
        // is dropped rather than carried: applying it would leave the device
        // as it booted while the report claimed a default was honoured.
        var table: [String: String] = [:]
        if let block = root["orientation"] as? [String: Any] {
            for (tier, value) in block {
                if let value = value as? String,
                   Orientation(rawValue: value) != nil {
                    table[tier] = value
                }
            }
        }
        return .table(table)
    }

    /// Read the sidecar from the bundle the tests were loaded from.
    public static func load(bundle: Bundle = .main) -> Load {
        guard let resourcePath = bundle.resourcePath else {
            return .unreadable("bundle has no resource path")
        }
        return load(from: URL(fileURLWithPath: resourcePath))
    }
}

/// The two orientations the test vocabulary has. Separate from
/// `ResponsiveOrientation` on purpose: that one is an OBSERVATION derived from
/// the window, this one is a DECLARATION read from a file, and the pair only
/// carries information while the two can disagree.
public enum Orientation: String, Equatable {
    case portrait
    case landscape
}
