import Foundation

/// Whether `hideKeyboard` may press the Return key to put the keyboard away.
///
/// An iPhone text keyboard has no dismiss key, and the interactive drag only
/// works over a scroll view that dismisses interactively — measured
/// 2026-10-15 on iPhone 17 / iOS 27.0: a login form's keyboard survived the
/// dismiss-key, accessory-Done and drag attempts (2/2), and Return closed it.
/// So Return is the last rung of the ladder, and the only one that is not
/// aimed at "put the keyboard away" alone: it ends editing, and the field's
/// submit handler runs with it. That is why the rung has rules.
///
/// - Only a single-line field. In a multi-line one Return inserts a newline,
///   and `hideKeyboard` must not change what the test typed.
/// - Only a key that names no action of its own (return / Done). A key that
///   reads Go / Send / Search / Join / Next … announces what pressing it
///   does; the test should do that on purpose, not as a side effect of
///   putting the keyboard away.
///
/// What it cannot see: whether the screen binds a submit handler to a quiet
/// Return as well. Nothing in the accessibility tree says so, so the exit
/// note says it may have run.
///
/// `tap` never takes this rung: its target is usually the very submit button
/// the Return would already have fired, so the submit could run twice.
public enum ReturnKeyDismiss {
    /// The focused field as the accessibility tree types it.
    public enum FieldKind: Equatable {
        /// TextField / SecureField.
        case singleLine
        /// TextEditor / UITextView: Return inserts a newline.
        case multiLine
        /// No focused field could be read (no `hasKeyboardFocus` on this
        /// XCTest, or nothing reports it).
        case unknown
    }

    public enum Verdict: Equatable {
        /// Press the key carrying this label.
        case press(label: String)
        /// Do not press; the reason goes into the action's failure.
        case refuse(String)
    }

    /// Return-key labels that name no action. Compared case-insensitively.
    public static let quietLabels: [String] = ["return", "改行", "done", "完了"]

    /// Return-key labels that name an action (UIReturnKeyType, en / ja).
    /// Exact matches: a prefix would also catch the globe key, whose label
    /// is "Next keyboard".
    public static let actionLabels: [String] = [
        "go", "search", "send", "next", "join", "route", "continue", "emergency call",
        "開く", "検索", "送信", "次へ", "参加", "経路", "続ける", "緊急電話"
    ]

    public static func verdict(field: FieldKind, fieldId: String?, keyLabels: [String]) -> Verdict {
        let name = fieldId.map { $0.isEmpty ? "(no identifier)" : $0 } ?? "(no identifier)"
        switch field {
        case .unknown:
            return .refuse("no focused field could be read, so Return was not pressed "
                + "(it could insert a newline into a multi-line field)")
        case .multiLine:
            return .refuse("the focused field '\(name)' is multi-line, where Return inserts a newline")
        case .singleLine:
            break
        }
        let lowered = keyLabels.map { $0.lowercased() }
        if let index = lowered.firstIndex(where: { quietLabels.contains($0) }) {
            return .press(label: keyLabels[index])
        }
        if let index = lowered.firstIndex(where: { actionLabels.contains($0) }) {
            return .refuse("the Return key reads '\(keyLabels[index])', which names an action of its own — "
                + "press it as a step if that is what the test means")
        }
        return .refuse("no Return key was found on the keyboard")
    }
}
