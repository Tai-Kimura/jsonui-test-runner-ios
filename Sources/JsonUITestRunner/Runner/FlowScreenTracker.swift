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
    /// Screens the flow reached in any attempt (a reached screen whose
    /// receipt failed is a failure, not "never reached").
    private(set) var reached: Set<String> = []

    /// The screen `state` reads now.
    var stateScreen: String? { referencedScreen ?? lastNamedScreen }

    /// A new flow file: nothing from the previous one counts.
    mutating func startFlow(pendingReceipts: [String: String]) {
        self.pendingReceipts = pendingReceipts
        reached = []
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
        reached.insert(screen)
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

    /// The warning for each screen in viewModels the flow never reached
    /// (the same sentence as web, validate and Android).
    var unreachedWarnings: [String] {
        pendingReceipts.keys.filter { !reached.contains($0) }.sorted().map {
            "initialState for screen '\($0)' was never checked: the flow never reached it (no step names that screen)"
        }
    }
}
