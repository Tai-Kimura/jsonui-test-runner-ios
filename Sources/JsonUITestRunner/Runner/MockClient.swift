import Foundation

/// Client for the local mock server's admin API (/__jsonui__/).
///
/// Switches API mock scenarios during a run: a screen test's root `mocks`
/// (set before the app relaunches) and `setMocks` steps in flows. Requests are
/// synchronous (XCUITest runner runs off the main thread), matched to the
/// runner's imperative control flow.
public final class MockClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// Switch a set of endpoints to the given scenarios. Throws on unknown refs.
    public func scenarioSet(_ mocks: [String: String]) throws {
        let body = try JSONSerialization.data(withJSONObject: ["mocks": mocks])
        let response = try post(path: "/__jsonui__/scenario-set", body: body)
        if let unknown = response?["unknown"] as? [String], !unknown.isEmpty {
            throw MockClientError.unknownOperations(unknown)
        }
    }

    /// Reset every endpoint back to its default scenario.
    public func reset() throws {
        _ = try post(path: "/__jsonui__/reset", body: nil)
    }

    @discardableResult
    private func post(path: String, body: Data?) throws -> [String: Any]? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-JsonUI-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = resultError {
            throw MockClientError.transport(error.localizedDescription)
        }
        if let http = resultResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MockClientError.httpStatus(http.statusCode)
        }
        if let data = resultData, !data.isEmpty {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        return nil
    }
}

public enum MockClientError: Error, LocalizedError {
    case transport(String)
    case httpStatus(Int)
    case unknownOperations([String])
    case notConfigured(feature: String)

    public var errorDescription: String? {
        switch self {
        case .transport(let message):
            return "mock server request failed: \(message)"
        case .httpStatus(let code):
            return "mock server returned HTTP \(code)"
        case .unknownOperations(let ops):
            return "mock scenario-set: unknown operationId(s): \(ops.joined(separator: ", "))"
        case .notConfigured(let feature):
            return "'\(feature)' requires a mock server: set mockServerURL + mockToken in TestRunnerConfig (from 'jsonui-test mock serve')."
        }
    }
}
