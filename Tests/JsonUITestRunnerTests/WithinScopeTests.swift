import XCTest
import CoreGraphics
@testable import JsonUITestRunner

/// `within`: decoding (step, flow step, condition), the snapshot walk that
/// scopes the target to a container, the two failure messages, and the
/// `hidden` rule over every match.
final class WithinScopeTests: XCTestCase {

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testAStepDecodesWithin() throws {
        let step = try decode(TestStep.self,
                              #"{"assert":"text","id":"ocr_field_label_text","within":"fields_item_2","equals":"年数"}"#)
        XCTAssertEqual(step.within, "fields_item_2")
        XCTAssertEqual(step.id, "ocr_field_label_text")
    }

    func testAStepWithoutWithinHasNone() throws {
        let step = try decode(TestStep.self, #"{"action":"tap","id":"submit"}"#)
        XCTAssertNil(step.within)
    }

    func testAFlowStepDecodesWithin() throws {
        let step = try decode(FlowTestStep.self,
                              #"{"screen":"s","action":"tap","id":"delete","within":"rows_item_0"}"#)
        XCTAssertEqual(step.within, "rows_item_0")
    }

    func testTheMemberwiseInitCarriesWithin() {
        XCTAssertEqual(TestStep(action: "tap", id: "x", within: "list_item_1").within, "list_item_1")
        XCTAssertNil(TestStep(action: "tap", id: "x").within)
    }

    func testAConditionDecodesWithinAsAKnownKey() throws {
        let condition = try decode(WhenCondition.self, #"{"visible":"badge","within":"list_item_3"}"#)
        XCTAssertEqual(condition.visible, "badge")
        XCTAssertEqual(condition.within, "list_item_3")
        // Known: the fail-safe skip for unknown keys must not fire on it.
        XCTAssertEqual(condition.unknownKeys, [])
    }

    func testAConditionWithoutWithinHasNone() throws {
        let condition = try decode(WhenCondition.self, #"{"hidden":"spinner"}"#)
        XCTAssertNil(condition.within)
        XCTAssertEqual(condition.unknownKeys, [])
    }

    // MARK: - Snapshot walk

    private final class Node {
        let id: String
        let frame: CGRect
        let clips: Bool
        let children: [Node]
        init(_ id: String, _ frame: CGRect, clips: Bool = false, _ children: [Node] = []) {
            self.id = id; self.frame = frame; self.clips = clips; self.children = children
        }
    }

    private func locate(_ id: String, within: String?, in root: Node) -> WithinScope.Located {
        WithinScope.locate(id: id, within: within, root: root,
                           identifier: { $0.id }, children: { $0.children },
                           frame: { $0.frame }, clips: { $0.clips })
    }

    /// A collection of three cells, each holding a label with the same id.
    private let window = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let list = CGRect(x: 0, y: 100, width: 400, height: 600)
    private func cellFrame(_ n: Int) -> CGRect { CGRect(x: 0, y: 100 + CGFloat(n) * 100, width: 400, height: 100) }
    private func labelFrame(_ n: Int) -> CGRect { CGRect(x: 10, y: 110 + CGFloat(n) * 100, width: 200, height: 20) }
    private var tree: Node {
        Node("", window, [
            Node("title", CGRect(x: 0, y: 0, width: 400, height: 50)),
            Node("list", list, clips: true, (0..<3).map { n in
                Node("list_item_\(n)", cellFrame(n), [
                    Node("", cellFrame(n), [Node("label", labelFrame(n))])
                ])
            })
        ])
    }

    func testWithoutWithinTheFirstMatchInTreeOrderIsTaken() {
        XCTAssertEqual(locate("label", within: nil, in: tree), .found(frame: labelFrame(0), clips: [window, list]))
    }

    func testWithinTakesTheMatchInsideThatCell() {
        XCTAssertEqual(locate("label", within: "list_item_2", in: tree),
                       .found(frame: labelFrame(2), clips: [window, list]))
        XCTAssertEqual(locate("label", within: "list_item_1", in: tree),
                       .found(frame: labelFrame(1), clips: [window, list]))
    }

    func testAMissingContainerIsNamedAsTheContainer() {
        XCTAssertEqual(locate("label", within: "list_item_9", in: tree), .containerMissing)
    }

    func testAContainerWithoutTheTargetIsTargetMissing() {
        // `title` exists, but not inside the cell.
        XCTAssertEqual(locate("title", within: "list_item_0", in: tree), .targetMissing)
    }

    func testTheContainerItselfIsNotItsOwnDescendant() {
        XCTAssertEqual(locate("list_item_1", within: "list_item_1", in: tree), .targetMissing)
    }

    func testAMissingTargetWithoutWithinIsTargetMissing() {
        XCTAssertEqual(locate("nope", within: nil, in: tree), .targetMissing)
    }

    // MARK: - Messages

    func testTheContainerMessageNamesItAndSaysCellsExistOnlyWhileDrawn() {
        let message = WithinScope.containerNotFound(within: "fields_item_7", id: "ocr_field_label_text")
        XCTAssertTrue(message.contains("'fields_item_7'"), message)
        XCTAssertTrue(message.contains("'ocr_field_label_text'"), message)
        XCTAssertTrue(message.contains("exists in the tree only while it is drawn"), message)
        XCTAssertTrue(message.contains("scrollUntilVisible to 'fields_item_7' first"), message)
    }

    func testTheTargetMessageNamesBoth() {
        let message = WithinScope.targetNotFound(id: "ocr_field_label_text", within: "fields_item_2")
        XCTAssertTrue(message.contains("'ocr_field_label_text'"), message)
        XCTAssertTrue(message.contains("within 'fields_item_2'"), message)
        XCTAssertTrue(message.contains("the container exists"), message)
    }

    // MARK: - hidden over every match

    func testHiddenHoldsWithNoMatch() {
        XCTAssertTrue(WithinScope.hiddenHolds(containerMissing: false, drawn: []))
    }

    func testHiddenFailsWhenAnyMatchIsDrawnNotOnlyTheFirst() {
        XCTAssertFalse(WithinScope.hiddenHolds(containerMissing: false, drawn: [false, true]))
        XCTAssertFalse(WithinScope.hiddenHolds(containerMissing: false, drawn: [true, false]))
    }

    func testHiddenHoldsWhenEveryMatchIsNotDrawn() {
        XCTAssertTrue(WithinScope.hiddenHolds(containerMissing: false, drawn: [false, false]))
    }

    func testHiddenFailsWhenTheContainerIsMissing() {
        XCTAssertFalse(WithinScope.hiddenHolds(containerMissing: true, drawn: []))
        XCTAssertFalse(WithinScope.hiddenHolds(containerMissing: true, drawn: [true]))
    }

    func testNotVisibleFailsWhenTheContainerIsMissing() {
        XCTAssertFalse(WithinScope.notVisibleHolds(containerMissing: true, visible: false))
        XCTAssertTrue(WithinScope.notVisibleHolds(containerMissing: false, visible: false))
        XCTAssertFalse(WithinScope.notVisibleHolds(containerMissing: false, visible: true))
    }

    func testAMissingContainerFailsOnlyWithWithin() {
        XCTAssertTrue(WithinScope.missingContainerFails(within: "list_item_9", containerExists: false))
        XCTAssertFalse(WithinScope.missingContainerFails(within: "list_item_1", containerExists: true))
        // Without within there is no container: a missing target is the
        // step's own matter (notVisible / hidden hold on it).
        XCTAssertFalse(WithinScope.missingContainerFails(within: nil, containerExists: false))
    }
}
