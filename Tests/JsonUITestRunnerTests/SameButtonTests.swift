import XCTest
@testable import JsonUITestRunner

/// The shapes measured on iOS 27.2 and 26.5 (2026-11-05), and the ones a
/// name must not be settled for.
final class SameButtonTests: XCTestCase {
    private let frame = CGRect(x: 205, y: 529, width: 140, height: 48)
    private let id = "kTCCServicePhotosAdd-allow-button"

    private func button(id: String = "", label: String = "Allow", frame: CGRect? = nil, children: [SameButton.Node] = []) -> SameButton.Node {
        SameButton.Node(identifier: id, label: label, frame: frame ?? self.frame, children: children)
    }

    func testNothingMatchedIsAbsent() {
        XCTAssertEqual(SameButton.read([]), .absent)
    }

    func testOneMatchIsOne() {
        XCTAssertEqual(SameButton.read([button()]), .one)
    }

    /// The iOS 27.2 privacy prompt: the query matches the parent and the child.
    func testAButtonHoldingItselfIsOne() {
        let child = button(id: id)
        XCTAssertEqual(SameButton.read([button(id: id, children: [child]), child]), .one)
    }

    func testTheOrderOfTheMatchesDoesNotDecide() {
        let child = button(id: id)
        XCTAssertEqual(SameButton.read([child, button(id: id, children: [child])]), .one)
    }

    func testTheCopyMayBeDeeper() {
        let child = button(id: id)
        let wrapper = SameButton.Node(isButton: false, identifier: "", label: "", frame: frame, children: [child])
        XCTAssertEqual(SameButton.read([button(id: id, children: [wrapper]), child]), .one)
    }

    func testThreeDeepIsOne() {
        let inner = button(id: id)
        let middle = button(id: id, children: [inner])
        XCTAssertEqual(SameButton.read([button(id: id, children: [middle]), middle, inner]), .one)
    }

    /// An alert with two actions of one title: side by side, other frames.
    func testTwoButtonsOfOneNameAreDifferent() {
        let other = CGRect(x: 57, y: 463, width: 288, height: 48)
        XCTAssertEqual(SameButton.read([button(), button(frame: other)]), .different(2))
    }

    /// Same place and name but not nested: nothing says they are one button.
    func testTheSameFrameWithoutNestingIsDifferent() {
        XCTAssertEqual(SameButton.read([button(id: id), button(id: id)]), .different(2))
    }

    func testNestedWithAnotherFrameIsDifferent() {
        let other = CGRect(x: 205, y: 529, width: 100, height: 48)
        let child = button(id: id, frame: other)
        XCTAssertEqual(SameButton.read([button(id: id, children: [child]), child]), .different(2))
    }

    func testNestedWithAnotherLabelIsDifferent() {
        let child = button(id: id, label: "Deny")
        XCTAssertEqual(SameButton.read([button(id: id, children: [child]), child]), .different(2))
    }

    func testNestedWithAnotherIdentifierIsDifferent() {
        let child = button(id: "other")
        XCTAssertEqual(SameButton.read([button(id: id, children: [child]), child]), .different(2))
    }

    /// A nested pair and a third button with the name: the third is real.
    func testANestedPairBesideAnotherButtonIsDifferent() {
        let child = button(id: id)
        let other = button(id: id, frame: CGRect(x: 57, y: 529, width: 140, height: 48))
        XCTAssertEqual(SameButton.read([button(id: id, children: [child]), child, other]), .different(3))
    }

    /// A match that is not a button is never the same button.
    func testACopyThatIsNotAButtonIsDifferent() {
        let text = SameButton.Node(isButton: false, identifier: id, label: "Allow", frame: frame)
        XCTAssertEqual(SameButton.read([button(id: id, children: [text]), text]), .different(2))
    }

    func testThePhotosPromptsAreNotAnotherServices() {
        XCTAssertFalse(SameButton.isAnotherServicesPrompt("kTCCServicePhotosAdd-alert"))
        XCTAssertFalse(SameButton.isAnotherServicesPrompt("kTCCServicePhotos-alert"))
    }

    func testACameraPromptIsAnotherServices() {
        XCTAssertTrue(SameButton.isAnotherServicesPrompt("kTCCServiceCamera-alert"))
    }

    /// iOS 26, and the notification and location prompts on both.
    func testAPromptWithoutAnIdentifierSaysNothing() {
        XCTAssertFalse(SameButton.isAnotherServicesPrompt(""))
    }
}
