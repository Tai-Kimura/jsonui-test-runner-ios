import XCTest
@testable import JsonUITestRunner

/// How `visible` names what an element is under (ModalCover.reason). The
/// first case is the measured one: iOS's "Save Password?" sheet, which the
/// snapshot shows as a Sheet carrying that label, over a 2FA screen.
final class ModalCoverTests: XCTestCase {
    func testASheetIsNamedByItsLabel() {
        XCTAssertEqual(ModalCover.reason(.sheet(label: "パスワードを保存しますか?")),
                       "under a modal ('パスワードを保存しますか?')")
    }

    func testAnAlertIsNamedByItsLabel() {
        XCTAssertEqual(ModalCover.reason(.alert(label: "Delete item?")), "under a modal ('Delete item?')")
    }

    func testAnUnlabelledOneIsNamedByItsKind() {
        XCTAssertEqual(ModalCover.reason(.sheet(label: "")), "under a modal (sheet)")
        XCTAssertEqual(ModalCover.reason(.alert(label: "")), "under a modal (alert)")
    }

    func testAPresentedScreenIsNamedByItsMarker() {
        XCTAssertEqual(ModalCover.reason(.screen("forgot_password")), "under a modal (screen 'forgot_password')")
    }

    func testNothingToNameStillSaysModalNotAbsent() {
        // The element exists (the query found it); only the snapshot lacks it.
        XCTAssertEqual(ModalCover.reason(nil), "under a modal")
    }

    func testNoWordingSaysTheElementIsMissing() {
        // The defect: "does not exist" for an element that was in the tree.
        for cover: ModalCover.Candidate? in [.sheet(label: "x"), .alert(label: ""), .screen("s"), nil] {
            XCTAssertFalse(ModalCover.reason(cover).contains("does not exist"))
            XCTAssertTrue(ModalCover.reason(cover).hasPrefix("under a modal"))
        }
    }

    func testTheWaitHistorySpeaksTheSameWords() throws {
        // The measured sequence: the screen arrives, then the sheet comes
        // over it. The block lists the modal by name, not as an absence.
        var h = ReasonHistory()
        let sheet = ModalCover.reason(.sheet(label: "パスワードを保存しますか?"))
        for i in 0..<10 { h.observe("does not exist", at: Double(i) * 0.1) }
        for i in 10...50 { h.observe(sheet, at: Double(i) * 0.1) }
        let block = try XCTUnwrap(h.block(end: 5.0))
        XCTAssertTrue(block.contains("1.0–5.0s  under a modal ('パスワードを保存しますか?')"), block)
    }
}
