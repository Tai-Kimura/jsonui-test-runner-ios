import Foundation

/// Which of `hideKeyboard`'s four exits produced the OK the step reported.
///
/// The action returns the same success from four places: the keyboard was
/// not on screen at all, a dismiss key worked, an accessory Done worked, or
/// the coordinate drag worked. Only the last one can take a presented sheet
/// with it, so "did the risky path run?" is the question every diagnosis of
/// this action starts from — and until 1.9.14 nothing in the output answered
/// it.
///
/// Measured 2026-09-04, a consumer lane on 1.9.13 removed a platform gate and
/// ran the sheet flow three times: 3/3 passed, no context-loss failure, the
/// sheet survived. That result is consistent with the drag running harmlessly
/// AND with the keyboard never being visible, and the two readings call for
/// opposite next steps. The run could not distinguish them, so the firing
/// condition stayed unknown.
///
/// So each exit says which one it was. This is diagnosis only: no path
/// changes what the action returns or throws.
public enum HideKeyboardPath: Equatable {
    /// No keyboard on screen when the action began — nothing was done.
    case notVisible
    /// An explicit dismiss key (iPad keyboards have one).
    case dismissKey
    /// An input-accessory Done / 完了 / 閉じる / Close.
    case accessoryDone
    /// The coordinate drag — the only exit that acts on whatever is
    /// underneath. The counts are the context reading taken AFTER the drag,
    /// so a reader can see what survived rather than trust that it did.
    case drag(sheets: Int, fields: Int)

    /// The line for `note(...)`, which prefixes `jsonui-test-runner: `.
    ///
    /// Deliberately a non-optional String over an exhaustive switch with no
    /// `default:`. That is the coverage control: a fifth exit added later
    /// does not compile until it says which one it is. A test asserting "no
    /// path is missing a note" could only iterate a hand-written list of
    /// paths, and a hand-written population is silent about the case its
    /// author forgot — the compiler's is not.
    public var note: String {
        switch self {
        case .notVisible:
            return "hideKeyboard: keyboard not visible — nothing to do"
        case .dismissKey:
            return "hideKeyboard: dismissed via dismiss key"
        case .accessoryDone:
            return "hideKeyboard: dismissed via accessory Done"
        case .drag(let sheets, let fields):
            return "hideKeyboard: dismissed via drag (context intact: sheets=\(sheets), fields=\(fields))"
        }
    }
}
