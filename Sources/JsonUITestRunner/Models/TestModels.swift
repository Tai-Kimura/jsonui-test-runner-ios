import Foundation

// MARK: - Runtime Variable Store

/// Shared store for runtime variables written by `readText` and resolved as @{name}
/// at step-execution time. Lives for the duration of one runner invocation.
public final class VariableStore {
    private var values: [String: String] = [:]

    public init() {}

    public func set(_ name: String, to value: String) {
        values[name] = value
    }

    public func get(_ name: String) -> String? {
        values[name]
    }

    public var asDictionary: [String: Any] {
        values
    }

    public var isEmpty: Bool {
        values.isEmpty
    }
}

// MARK: - Screen Test

public struct ScreenTest: Codable {
    public let type: String
    public let source: TestSource
    public let metadata: TestMetadata
    public let platform: PlatformTarget?
    public let initialState: InitialState?
    public let launch: LaunchConfig?
    /// API mock scenario set applied (and the app relaunched) before the cases run
    public let mocks: [String: String]?
    public let setup: [TestStep]?
    public let teardown: [TestStep]?
    public let cases: [TestCase]
}

// MARK: - Launch Configuration

public struct LaunchConfig: Codable {
    /// Clear app data before launch (JSONUI_TEST_CLEAR_STATE env contract)
    public let clearState: Bool?
    /// Permission grants applied before launch (name -> allow|deny|unset)
    public let permissions: [String: String]?
    /// Launch arguments passed to the app (launchEnvironment JSONUI_TEST_ARGS)
    public let arguments: [String: AnyCodable]?
}

// MARK: - Condition (for `when` and `repeat.while`)

public struct WhenCondition: Codable {
    /// Instant check: element is currently visible
    public let visible: String?
    /// Instant check: element is currently absent or invisible
    public let notVisible: String?
    /// Current platform matches
    public let platform: PlatformTarget?
    /// ViewModel state matches (requires a state provider)
    public let state: StateCondition?
    /// Current size matches (named size-class bucket or constraint object),
    /// evaluated against the live device/window size at step time
    public let responsive: ResponsiveCondition?
    /// Condition keys present in the JSON that this driver cannot evaluate
    /// (written against a newer schema than this driver). Codable would
    /// silently drop them and the condition would run-anyway on the keys it
    /// does know — the fail-safe rule instead treats any unknown key as UNMET,
    /// so the gated step is skipped (never run-anyway, never a hard error).
    public let unknownKeys: [String]

    /// Condition keys this driver knows how to evaluate.
    private static let knownKeys: Set<String> = ["visible", "notVisible", "platform", "state", "responsive"]

    private enum CodingKeys: String, CodingKey {
        case visible
        case notVisible
        case platform
        case state
        case responsive
    }

    /// Free-form string key used to enumerate the condition's raw key set.
    private struct RawCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.visible = try container.decodeIfPresent(String.self, forKey: .visible)
        self.notVisible = try container.decodeIfPresent(String.self, forKey: .notVisible)
        self.platform = try container.decodeIfPresent(PlatformTarget.self, forKey: .platform)
        self.state = try container.decodeIfPresent(StateCondition.self, forKey: .state)
        self.responsive = try container.decodeIfPresent(ResponsiveCondition.self, forKey: .responsive)

        // Capture the full key set via a raw keyed container and record every
        // key outside the known set (values stay undecoded on purpose).
        let rawContainer = try decoder.container(keyedBy: RawCodingKey.self)
        self.unknownKeys = rawContainer.allKeys
            .map { $0.stringValue }
            .filter { !Self.knownKeys.contains($0) }
            .sorted()
    }
}

public struct StateCondition: Codable {
    public let path: String
    public let equals: AnyCodable
}

public struct TestSource: Codable {
    public let layout: String
    public let spec: String?
}

public struct TestMetadata: Codable {
    public let name: String
    public let description: String?
    public let generatedAt: String?
    public let generatedBy: String?
    public let tags: [String]?
}

public struct InitialState: Codable {
    public let viewModel: [String: AnyCodable]?
}

public struct TestCase: Codable {
    public let name: String
    public let description: String?
    public let skip: Bool?
    public let platform: PlatformTarget?
    /// Case-level responsive gate (named bucket string or constraint object),
    /// evaluated against the live device/window size before the case runs —
    /// unmet -> the case is skipped with skipReason "responsive"
    public let responsive: ResponsiveCondition?
    public let initialState: InitialState?
    public let steps: [TestStep]
    /// Default argument values for @{varName} substitution
    public let args: [String: AnyCodable]?
}

// MARK: - Flow Test

public struct FlowTest: Codable {
    public let type: String
    public let sources: [FlowTestSource]?  // Now optional (not needed when using file references)
    public let metadata: TestMetadata
    public let platform: PlatformTarget?
    public let initialState: FlowInitialState?
    public let launch: LaunchConfig?
    // File-level mock scenarios (operationId -> scenario) applied before the
    // first launch, so startup fetches run under the selected scenarios.
    // Parity with ScreenTest.mocks; step-level setMocks handles mid-flow switches.
    public let mocks: [String: String]?
    public let setup: [FlowTestStep]?
    public let teardown: [FlowTestStep]?
    public let steps: [FlowTestStep]
    public let checkpoints: [Checkpoint]?
}

public struct FlowTestSource: Codable {
    public let layout: String
    public let spec: String?
    public let alias: String?
}

public struct FlowInitialState: Codable {
    public let screen: String?
    public let viewModels: [String: [String: AnyCodable]]?
}

public struct FlowTestStep: Codable {
    // For inline steps
    public let screen: String?
    public let action: String?
    public let assert: String?
    public let id: String?
    public let ids: [String]?
    public let text: String?
    public let value: String?
    public let direction: String?
    public let duration: Int?
    public let timeout: Int?
    public let ms: Int?
    public let name: String?
    public let equals: AnyCodable?
    public let contains: String?
    public let path: String?
    public let amount: Int?
    public let button: String?
    public let label: String?
    public let index: Int?

    // Advanced feature fields (common step attributes + new actions)
    public let optional: Bool?
    public let when: WhenCondition?
    public let retryTapIfNoChange: Bool?
    public let container: String?
    public let variable: String?
    public let times: Int?
    public let `while`: WhenCondition?
    public let maxRetries: Int?
    public let latitude: Double?
    public let longitude: Double?
    public let paths: [String]?
    public let cropId: String?
    public let threshold: Double?
    /// Scenario map for the setMocks action (operationId -> scenario)
    public let mocks: [String: String]?
    /// Target orientation for the setOrientation action (portrait|landscape)
    public let orientation: String?

    // For file reference steps
    public let file: String?
    public let `case`: String?
    public let cases: [String]?
    /// Arguments to override screen test default args (for file reference steps)
    public let args: [String: AnyCodable]?

    // For block steps (grouped inline actions)
    public let block: String?
    public let description: String?
    public let descriptionFile: String?
    public let steps: [FlowTestStep]?

    /// Whether this is a file reference step
    public var isFileReference: Bool {
        file != nil
    }

    /// Whether this is a block step
    public var isBlockStep: Bool {
        block != nil
    }

    /// Whether this is an inline action/assertion step
    public var isInlineStep: Bool {
        screen != nil && (action != nil || assert != nil)
    }
}

public struct Checkpoint: Codable {
    public let name: String
    public let afterStep: Int
    public let screenshot: Bool?
}

// MARK: - Test Step (for Screen Tests)

public struct TestStep: Codable {
    public let action: String?
    public let assert: String?
    public let id: String?
    public let ids: [String]?
    public let text: String?
    public let value: String?
    public let direction: String?
    public let duration: Int?
    public let timeout: Int?
    public let ms: Int?
    public let name: String?
    public let equals: AnyCodable?
    public let contains: String?
    public let path: String?
    public let amount: Int?
    public let button: String?
    public let label: String?
    public let index: Int?

    // Advanced feature fields (common step attributes + new actions)
    public let optional: Bool?
    public let when: WhenCondition?
    public let retryTapIfNoChange: Bool?
    public let container: String?
    public let variable: String?
    public let times: Int?
    public let `while`: WhenCondition?
    /// Nested steps for repeat/retry control actions
    public let steps: [TestStep]?
    public let maxRetries: Int?
    public let latitude: Double?
    public let longitude: Double?
    public let paths: [String]?
    public let cropId: String?
    public let threshold: Double?
    /// Scenario map for the setMocks action (operationId -> scenario)
    public let mocks: [String: String]?
    /// Target orientation for the setOrientation action (portrait|landscape)
    public let orientation: String?

    public init(
        action: String? = nil,
        assert: String? = nil,
        id: String? = nil,
        ids: [String]? = nil,
        text: String? = nil,
        value: String? = nil,
        direction: String? = nil,
        duration: Int? = nil,
        timeout: Int? = nil,
        ms: Int? = nil,
        name: String? = nil,
        equals: AnyCodable? = nil,
        contains: String? = nil,
        path: String? = nil,
        amount: Int? = nil,
        button: String? = nil,
        label: String? = nil,
        index: Int? = nil,
        optional: Bool? = nil,
        when: WhenCondition? = nil,
        retryTapIfNoChange: Bool? = nil,
        container: String? = nil,
        variable: String? = nil,
        times: Int? = nil,
        while whileCondition: WhenCondition? = nil,
        steps: [TestStep]? = nil,
        maxRetries: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        paths: [String]? = nil,
        cropId: String? = nil,
        threshold: Double? = nil,
        mocks: [String: String]? = nil,
        orientation: String? = nil
    ) {
        self.action = action
        self.assert = assert
        self.id = id
        self.ids = ids
        self.text = text
        self.value = value
        self.direction = direction
        self.duration = duration
        self.timeout = timeout
        self.ms = ms
        self.name = name
        self.equals = equals
        self.contains = contains
        self.path = path
        self.amount = amount
        self.button = button
        self.label = label
        self.index = index
        self.optional = optional
        self.when = when
        self.retryTapIfNoChange = retryTapIfNoChange
        self.container = container
        self.variable = variable
        self.times = times
        self.while = whileCondition
        self.steps = steps
        self.maxRetries = maxRetries
        self.latitude = latitude
        self.longitude = longitude
        self.paths = paths
        self.cropId = cropId
        self.threshold = threshold
        self.mocks = mocks
        self.orientation = orientation
    }

    public var isAction: Bool {
        action != nil
    }

    public var isAssertion: Bool {
        assert != nil
    }

    /// Timeout as a TimeInterval (seconds), falling back to the provided default
    public func timeoutInterval(default defaultTimeout: TimeInterval) -> TimeInterval {
        if let timeout = timeout {
            return TimeInterval(timeout) / 1000.0
        }
        return defaultTimeout
    }
}

// MARK: - AnyCodable value equality

public extension AnyCodable {
    /// Structural equality used by state assertions/conditions
    func isEqual(to other: AnyCodable) -> Bool {
        if let a = boolValue, let b = other.boolValue { return a == b }
        if let a = intValue, let b = other.intValue { return a == b }
        if let a = doubleValue, let b = other.doubleValue { return abs(a - b) < 0.0001 }
        if let a = stringValue, let b = other.stringValue { return a == b }
        return String(describing: value) == String(describing: other.value)
    }
}

// MARK: - Platform Target

public enum PlatformTarget: Codable {
    case single(String)
    case multiple([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            self = .single(single)
        } else if let multiple = try? container.decode([String].self) {
            self = .multiple(multiple)
        } else {
            throw DecodingError.typeMismatch(
                PlatformTarget.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or [String]")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .multiple(let values):
            try container.encode(values)
        }
    }

    public func includes(_ platform: String) -> Bool {
        switch self {
        case .single(let value):
            return value == platform || value == "all"
        case .multiple(let values):
            return values.contains(platform)
        }
    }
}

// MARK: - AnyCodable (for dynamic values)

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }

    public var boolValue: Bool? {
        value as? Bool
    }

    public var intValue: Int? {
        value as? Int
    }

    public var doubleValue: Double? {
        value as? Double
    }

    public var stringValue: String? {
        value as? String
    }
}
