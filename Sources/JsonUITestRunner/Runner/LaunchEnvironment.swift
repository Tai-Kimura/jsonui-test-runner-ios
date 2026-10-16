import Foundation

/// The launch environment the runner hands the app (spec §5, §10.2).
///
/// The runner owns four keys and removes all four before every launch, then
/// sets the ones this launch needs. `XCUIApplication.launchEnvironment`
/// persists across launches of the same instance, so a key set for one file
/// used to reach every later file's launch (a clearState from file A wiped
/// the state file B relied on). Keys the harness set itself are kept.
public enum LaunchEnvironment {
    public static let clearState = "JSONUI_TEST_CLEAR_STATE"
    public static let arguments = "JSONUI_TEST_ARGS"
    public static let permissions = "JSONUI_TEST_PERMISSIONS"
    public static let initialState = "JSONUI_TEST_INITIAL_STATE"
    public static let owned: [String] = [clearState, arguments, permissions, initialState]

    public static func environment(base: [String: String], launch: LaunchConfig?,
                                   initialStatePayload: String?) -> [String: String] {
        var environment = base
        for key in owned { environment.removeValue(forKey: key) }
        if launch?.clearState == true {
            environment[clearState] = "1"
        }
        if let values = launch?.arguments, !values.isEmpty,
           let json = json(values.mapValues { $0.value }) {
            environment[arguments] = json
        }
        if let values = launch?.permissions, !values.isEmpty, let json = json(values) {
            environment[permissions] = json
        }
        if let initialStatePayload {
            environment[initialState] = initialStatePayload
        }
        return environment
    }

    static func json(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
