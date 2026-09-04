import Foundation

/// What was on screen when an untargeted dismiss gesture was about to run,
/// read again afterwards.
///
/// `hideKeyboard`'s last-resort strategy is a drag across raw screen
/// coordinates, and a drag has no target: it acts on whatever is underneath.
/// These two readings are what makes "the keyboard went away" separable from
/// "the thing holding the keyboard went away with it".
public struct PresentedContext: Equatable {
    /// Sheets XCTest reports as sheets. Zero does not mean "no modal" —
    /// which is exactly why `editableIdentifiers` is read as well.
    public let sheetCount: Int
    /// The frontmost sheet's identifier, for naming it in a failure.
    public let sheetIdentifier: String?
    /// Identifiers of the text inputs that EXIST, not the ones that are
    /// visible: an XCUITest element keeps existing while scrolled out of the
    /// viewport (see ScrollVisibility), so existence stays steady when the
    /// keyboard merely retracts and changes when the field is torn down.
    public let editableIdentifiers: [String]

    public init(sheetCount: Int, sheetIdentifier: String?, editableIdentifiers: [String]) {
        self.sheetCount = sheetCount
        self.sheetIdentifier = sheetIdentifier
        self.editableIdentifiers = editableIdentifiers
    }
}

/// The outcome of a keyboard dismiss, once the context is taken into account.
public enum HideKeyboardVerdict: Equatable {
    /// The keyboard went away and what was in front of it is still there.
    case dismissed
    /// The keyboard went away because the presented context went away. The
    /// string names what disappeared.
    case contextLost(String)
    /// The keyboard is still on screen.
    case notDismissed
}

/// Whether a keyboard dismissal took the test's context with it.
///
/// Measured 2026-09-02 and again 2026-09-04, four sites across two
/// consumer screens on iOS driver 1.9.12: inside a presented
/// SwiftUI `.sheet`, strategy 3's drag from (0.5, 0.4) to (0.5, 0.98) is the
/// system's interactive sheet-dismiss gesture. The sheet goes away, the
/// keyboard goes away with its first responder, and `waitForKeyboardDismiss`
/// — which asks only "is the keyboard gone?" — returns true.
///
/// So the strictly worse outcome satisfied the same predicate as the intended
/// one, and `hideKeyboard` reported OK. The next step then failed with
/// `Element not found:` on a control inside the vanished sheet, two steps and
/// one bisect away from the action that actually did it.
///
/// The fix is not to make the predicate stricter about keyboards. It is to
/// notice that a dismiss which destroys the surrounding context is a
/// different event from a dismiss, and to say which one happened.
public enum KeyboardDismissSafety {
    /// Pure so the shapes below are unit-tested rather than argued about.
    ///
    /// The keyboard reading comes first: if the keyboard is still up, nothing
    /// about the context matters, the action simply did not work.
    public static func verdict(
        keyboardGone: Bool,
        before: PresentedContext,
        after: PresentedContext
    ) -> HideKeyboardVerdict {
        guard keyboardGone else { return .notDismissed }

        if after.sheetCount < before.sheetCount {
            let name = before.sheetIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? "(no identifier)"
            return .contextLost("hideKeyboard dismissed the presented sheet '\(name)'")
        }

        // A SwiftUI sheet is not always reported as a sheet, so the count
        // above can stay flat through the very dismissal it is meant to
        // catch. The fields being edited are the other half of the reading:
        // hiding a keyboard does not remove the field the keyboard was
        // editing, and dismissing the presentation does.
        //
        // Blind spot worth naming: fields with no accessibility identifier
        // contribute nothing here (they cannot be named in a message), so on
        // a screen where NO input carries an identifier this reading is
        // empty and only the sheet count is left. Generated JsonUI screens
        // set identifiers, which is what the four measured sites look like.
        let lost = before.editableIdentifiers.filter { !after.editableIdentifiers.contains($0) }
        if !lost.isEmpty {
            let names = lost.map { "'\($0)'" }.joined(separator: ", ")
            return .contextLost(
                "hideKeyboard dismissed the presented context — "
                    + "the field(s) being edited no longer exist: \(names)"
            )
        }

        return .dismissed
    }
}
