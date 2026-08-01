import Foundation

/// Case-level retry loop: re-invokes `attempt` while the result fails, up to
/// `retries` extra times, and reports the total attempt count.
///
/// Pure on purpose — the runner itself needs the XCUITest runtime, so the
/// attempts/flaky accounting lives here where a plain XCTest can pin it
/// (results.schema.json: attempts = total runs, 1 = settled first try).
enum CaseRetry {
    static func run<T>(
        retries: Int,
        isPass: (T) -> Bool,
        onRetry: (_ attemptNumber: Int, _ maxAttempts: Int) -> Void = { _, _ in },
        attempt: () -> T
    ) -> (result: T, attempts: Int) {
        let maxAttempts = max(0, retries) + 1
        var attempts = 1
        var result = attempt()
        while !isPass(result) && attempts < maxAttempts {
            attempts += 1
            onRetry(attempts, maxAttempts)
            result = attempt()
        }
        return (result, attempts)
    }
}
