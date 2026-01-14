import Foundation

// MARK: - Screen Test

public struct ScreenTest: Codable {
    public let type: String
    public let source: TestSource
    public let metadata: TestMetadata
    public let platform: PlatformTarget?
    public let initialState: InitialState?
    public let setup: [TestStep]?
    public let teardown: [TestStep]?
    public let cases: [TestCase]
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
    public let initialState: InitialState?
    public let steps: [TestStep]
}

// MARK: - Flow Test

public struct FlowTest: Codable {
    public let type: String
    public let sources: [FlowTestSource]
    public let metadata: TestMetadata
    public let platform: PlatformTarget?
    public let initialState: FlowInitialState?
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
    public let screen: String
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

    public var isAction: Bool {
        action != nil
    }

    public var isAssertion: Bool {
        assert != nil
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
