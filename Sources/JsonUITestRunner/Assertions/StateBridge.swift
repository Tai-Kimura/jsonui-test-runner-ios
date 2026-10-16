import XCTest

/// Reading a screen's state bridge (spec §10.4–10.5): the leaf
/// `__state_<screenId>` whose accessibility value is
/// `{launchId, initialState: {applied, rejected} | null, data}`, or
/// `{"truncated": <bytes>}` past 32 KB.
///
/// The parsing, the path rule and the receipt judgement are pure and driven
/// by the shared vector `specs/vectors/state-path.json`; only `read` touches
/// XCUITest.
public enum StateBridge {
    public static let prefix = "__state_"

    public static func identifier(_ screenId: String) -> String { "\(prefix)\(screenId)" }

    public struct Rejection: Equatable {
        public let key: String
        public let reason: String
    }

    public struct Receipt: Equatable {
        public let applied: [String]
        public let rejected: [Rejection]
    }

    public enum Reading {
        /// No leaf: the screen is not showing, or its library has no bridge.
        case absent
        /// Over the size limit; nothing in it can be read.
        case truncated(bytes: Int)
        /// A leaf whose value is not a bridge (no `data`).
        case malformed
        case bridge(launchId: String?, receipt: Receipt?, data: [String: Any])
    }

    public static func parse(_ value: String?) -> Reading {
        guard let value, let raw = value.data(using: .utf8) else { return .absent }
        guard let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return .malformed }
        if let bytes = root["truncated"] as? NSNumber { return .truncated(bytes: bytes.intValue) }
        guard let data = root["data"] as? [String: Any] else { return .malformed }
        var receipt: Receipt?
        if let initialState = root["initialState"] as? [String: Any] {
            let rejected = (initialState["rejected"] as? [[String: Any]] ?? []).compactMap { entry -> Rejection? in
                guard let key = entry["key"] as? String else { return nil }
                return Rejection(key: key, reason: entry["reason"] as? String ?? "")
            }
            receipt = Receipt(applied: initialState["applied"] as? [String] ?? [], rejected: rejected)
        }
        return .bridge(launchId: root["launchId"] as? String, receipt: receipt, data: data)
    }

    /// The bridge of `screenId` as the app publishes it now.
    public static func read(_ screenId: String, in app: XCUIApplication) -> Reading {
        let leaf = app.descendants(matching: .any).matching(identifier: identifier(screenId)).firstMatch
        guard leaf.exists else { return .absent }
        return parse(leaf.value as? String)
    }

    // MARK: - path

    public enum PathResult {
        /// The value at the path; `NSNull()` for a key that holds null.
        case value(Any)
        case unresolved
    }

    /// `a.b.0.c`: on an object a segment is a key (case-sensitive, digits
    /// included); on an array a segment of decimal digits with no leading
    /// zero is an index from 0. An empty segment, and any step into a scalar
    /// or null, does not resolve.
    public static func resolve(_ path: String, in data: [String: Any]) -> PathResult {
        let segments = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !segments.isEmpty, !segments.contains("") else { return .unresolved }
        var current: Any = data
        for segment in segments {
            if let object = current as? [String: Any] {
                guard let next = object[segment] else { return .unresolved }
                current = next
            } else if let array = current as? [Any] {
                guard isIndex(segment), let index = Int(segment), index < array.count else { return .unresolved }
                current = array[index]
            } else {
                return .unresolved
            }
        }
        return .value(current)
    }

    static func isIndex(_ segment: String) -> Bool {
        guard !segment.isEmpty, segment.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        return segment == "0" || !segment.hasPrefix("0")
    }

    // MARK: - what a `state` read concludes

    public enum Outcome {
        /// Keep waiting: no bridge (or a malformed one) yet.
        case pending
        /// Fail at once: the bridge is over its size limit.
        case truncated(bytes: Int)
        case value(Any)
        /// The bridge is there and the path does not resolve (yet).
        case unresolved
    }

    public static func outcome(_ reading: Reading, path: String) -> Outcome {
        switch reading {
        case .absent, .malformed:
            return .pending
        case .truncated(let bytes):
            return .truncated(bytes: bytes)
        case .bridge(_, _, let data):
            switch resolve(path, in: data) {
            case .value(let value): return .value(value)
            case .unresolved: return .unresolved
            }
        }
    }

    // MARK: - receipt

    public enum ReceiptState: Equatable {
        /// No receipt for this launch yet.
        case waiting
        case confirmed
        case rejected([Rejection])
        case truncated(bytes: Int)
    }

    /// Whether the screen confirmed the payload of launch `launchId`.
    public static func receipt(_ reading: Reading, launchId: String) -> ReceiptState {
        switch reading {
        case .truncated(let bytes):
            return .truncated(bytes: bytes)
        case .bridge(let bridgeLaunch, let receipt, _):
            guard bridgeLaunch == launchId, let receipt else { return .waiting }
            return receipt.rejected.isEmpty ? .confirmed : .rejected(receipt.rejected)
        case .absent, .malformed:
            return .waiting
        }
    }

    /// The failure text when no receipt came (spec §10.5).
    public static func noReceiptMessage(screenId: String, timeout: TimeInterval, lastReading: Reading) -> String {
        let seen: String
        switch lastReading {
        case .absent: seen = "no state bridge '\(identifier(screenId))' was found"
        case .malformed: seen = "the state bridge '\(identifier(screenId))' could not be read"
        case .truncated(let bytes): seen = "the state bridge is \(bytes) bytes, over the iOS limit of 32KB"
        case .bridge(let launchId, _, _):
            seen = "the state bridge shows launch \(launchId ?? "null") without a receipt for this launch"
        }
        return "initialState for '\(screenId)' was not confirmed by the app within \(Int(timeout * 1000))ms (\(seen)). "
            + "Likely causes: SwiftJsonUI older than 10.30.0, or code generated by an older jsonui-cli (rebuild with `jui build`); "
            + "a build with the screen-marker gate closed (not DEBUG and no com.swiftjsonui.SCREEN_MARKER); "
            + "a screen id that does not match the layout ('\(screenId)')."
    }

    public static func rejectedMessage(screenId: String, _ rejections: [Rejection]) -> String {
        let listed = rejections.map { "'\($0.key)': \($0.reason)" }.joined(separator: "; ")
        return "initialState for '\(screenId)' was rejected by the app: \(listed)"
    }
}
