import Foundation

/// Which selector a `selectOption` step resolves to when it carries more
/// than one of `index` / `value` / `label`.
///
/// The schema (jsonui-test-runner `schemas/actions.schema.json`, 169ad16)
/// declares the order: `index` (explicit, locale-free), then `value` (the
/// machine key), then `label` (the visible text) — a lower selector is
/// ignored when a higher one is present, and for `selectOption` the `label`
/// key keeps its option-text meaning, so a free-text note placed there IS
/// the option to select. The three drivers used to disagree (this one read
/// `label` first, web `value` first, android `index` first), and a
/// consumer's step carrying `index` plus a note in `label` set the picker
/// wheel to the note here and passed on android.
///
/// Kept apart from the XCUITest-driven executor so the decision can be
/// unit-tested without a simulator; the executor only acts on the result.
enum SelectOptionSelector: Equatable {
    case index(Int)
    case value(String)
    case label(String)

    /// `nil` when the step carries no selector at all.
    static func resolve(index: Int?, value: String?, label: String?) -> SelectOptionSelector? {
        if let index = index { return .index(index) }
        if let value = value { return .value(value) }
        if let label = label { return .label(label) }
        return nil
    }
}
