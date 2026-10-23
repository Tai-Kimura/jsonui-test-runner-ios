import Foundation

/// The screen a flow is on, what `state` reads, and which screens still owe a
/// receipt for their initialState (spec §6, §10.5). Pure — the runner hands it
/// the two XCUITest operations — so the rules below are unit-tested.
///
/// - A flow file and each attempt of its body start from "unknown": nothing
///   carries over from the previous flow file or from a failed attempt. A
///   screen tracked at the end of one would make the next one's first step
///   look like "the same screen" and skip both the implicit screen check and
///   the receipt (measured on web; the same shape here).
/// - `verifyScreenTransitions: false` skips the implicit screen check only:
///   the screen is still tracked and its receipt still checked.
/// - A pending receipt is removed only once it is confirmed, so a retried
///   attempt that reaches the screen checks it again.
struct FlowScreenTracker {
    /// The screen the previous inline step ran on; nil is "unknown".
    private(set) var trackedScreen: String?
    /// The last screen a flow step named: what `state` reads between steps.
    private(set) var lastNamedScreen: String?
    /// While a referenced file's case runs, `state` reads that file's screen.
    private var referencedScreen: String?
    /// Screen id -> the launch whose payload it has yet to confirm.
    private(set) var pendingReceipts: [String: String] = [:]

    /// The screen `state` reads now.
    var stateScreen: String? { referencedScreen ?? lastNamedScreen }

    /// A new flow file: nothing from the previous one counts.
    mutating func startFlow(pendingReceipts: [String: String]) {
        self.pendingReceipts = pendingReceipts
        startAttempt()
    }

    /// A new attempt of the flow body (a retry): back to unknown. Pending
    /// receipts stay — the launch, and the payload, are the same.
    mutating func startAttempt() {
        trackedScreen = nil
        lastNamedScreen = nil
        referencedScreen = nil
    }

    /// Before an inline step that names `screen` (or none).
    mutating func enterStep(
        screen: String?,
        verifyScreens: Bool,
        verify: (String) throws -> Void,
        waitForReceipt: (_ screen: String, _ launchId: String) throws -> Void
    ) throws {
        referencedScreen = nil
        guard let screen else { return }
        lastNamedScreen = screen
        guard screen != trackedScreen else { return }
        if verifyScreens { try verify(screen) }
        trackedScreen = screen
        if let launchId = pendingReceipts[screen] {
            try waitForReceipt(screen, launchId)
            pendingReceipts.removeValue(forKey: screen)
        }
    }

    /// A file reference runs a case of another file: the screen is unknown
    /// afterwards, and `state` reads that file's screen meanwhile.
    mutating func enterFileReference(screenOfFile: String?) {
        trackedScreen = nil
        referencedScreen = screenOfFile
    }

    /// After the file reference: `state` goes back to the flow's screen.
    mutating func leaveFileReference() {
        referencedScreen = nil
    }

    /// The warning for each screen still owing its receipt when the flow
    /// ends (spec §10.5, a3161b7; the same rule and sentence as web, validate
    /// and Android) — including one an earlier attempt reached and failed on
    /// that the passing attempt never went back to: its initialState was
    /// never confirmed.
    var unreachedWarnings: [String] {
        pendingReceipts.keys.sorted().map {
            "initialState for screen '\($0)' was never checked: the flow never reached it (no step names that screen)"
        }
    }
}

/// The runner's FlowScreenTracker. A step's screen check runs on a copy,
/// written back afterwards, so no access to the runner's state is open while
/// `verify` and `waitForReceipt` do their XCUITest work.
///
/// XCUITest stops a test by unwinding through that work — a read it cannot
/// answer is recorded as a failure and the test is interrupted, whatever
/// continueAfterFailure says — and the unwinding runs no Swift cleanup. A
/// mutating call on a stored property of the runner keeps a Swift
/// exclusivity access open for the whole call, the closures included; left
/// open, it stays registered on the main thread, pointing into a stack frame
/// that no longer exists, and the next access the next test makes walks into
/// it: SIGSEGV in swift_beginAccess under verifyScreenTransitionIfNeeded, at
/// the first step of the test after the one that was stopped (a consumer's
/// tablet run, 2026-10-20 and 2026-10-23; jsonui-cli ticket
/// 2026-10-23-test-ios-runner-segv-in-verify-screen-transition). The copy is
/// a local the access checker does not track, and the runner holds this
/// object in a `let`, which it does not track either.
///
/// A step stopped that way leaves the tracker where the step began; the next
/// flow or attempt starts from "unknown" anyway (startFlow, startAttempt).
final class FlowScreens {
    private var tracker = FlowScreenTracker()

    var stateScreen: String? { tracker.stateScreen }
    var unreachedWarnings: [String] { tracker.unreachedWarnings }

    func startFlow(pendingReceipts: [String: String]) {
        tracker.startFlow(pendingReceipts: pendingReceipts)
    }

    func startAttempt() {
        tracker.startAttempt()
    }

    func enterStep(
        screen: String?,
        verifyScreens: Bool,
        verify: (String) throws -> Void,
        waitForReceipt: (_ screen: String, _ launchId: String) throws -> Void
    ) throws {
        var copy = tracker
        defer { tracker = copy }
        try copy.enterStep(
            screen: screen, verifyScreens: verifyScreens, verify: verify, waitForReceipt: waitForReceipt)
    }

    func enterFileReference(screenOfFile: String?) {
        tracker.enterFileReference(screenOfFile: screenOfFile)
    }

    func leaveFileReference() {
        tracker.leaveFileReference()
    }
}
