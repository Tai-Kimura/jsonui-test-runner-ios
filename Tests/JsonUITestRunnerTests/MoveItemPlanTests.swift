import XCTest
@testable import JsonUITestRunner

/// moveItem's gesture plan against Fixtures/move-item.json, a byte copy of jsonui-test-runner
/// specs/vectors/move-item.json: where the press and the release land, and the reason a step fails before anything
/// moves. The web and Android drivers run the same vectors.
final class MoveItemPlanTests: XCTestCase {

    private func rect(_ a: Any?) -> CGRect? {
        guard let n = a as? [Double], n.count == 4 else { return nil }
        return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
    }

    func testTheTimingIsTheVectorsTiming() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "move-item", withExtension: "json", subdirectory: "Fixtures"))
        let vector = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let timing = try XCTUnwrap(vector["timing"] as? [String: Double])
        XCTAssertEqual(timing["pressSeconds"], MoveItemPlan.pressSeconds)
        XCTAssertEqual(timing["holdSeconds"], MoveItemPlan.holdSeconds)
        XCTAssertEqual(vector["edgeMargin"] as? Double, Double(MoveItemPlan.edgeMargin))
        XCTAssertEqual(vector["listMargin"] as? Double, Double(MoveItemPlan.listMargin))
    }

    func testVerify() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "move-item", withExtension: "json", subdirectory: "Fixtures"))
        let vector = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(vector["verify"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 5)
        for w in cases {
            let got = MoveItemPlan.scrolled(before: try XCTUnwrap(rect(w["before"])), after: rect(w["after"]))
            XCTAssertEqual(got != nil, w["scrolled"] as? Bool, w["name"] as? String ?? "?")
            if w["offScreen"] as? Bool == true, let got {
                XCTAssertTrue(MoveItemPlan.scrolledSentence("list_item_1", moved: got).contains("('list_item_1' moved off the screen)"))
            }
        }
    }

    func testEveryCase() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "move-item", withExtension: "json", subdirectory: "Fixtures"))
        let vector = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(vector["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 25)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            var rows: [String: [CGRect]] = [:]
            for (address, frames) in (c["rows"] as? [String: [[Double]]]) ?? [:] {
                rows[address] = frames.compactMap { rect($0) }
            }
            let handle: CGRect?? = c.keys.contains("handle") ? .some(rect(c["handle"])) : .none
            let got = MoveItemPlan.plan(id: "list", from: c["from"] as! Int, to: c["to"] as! Int,
                                        section: c["section"] as? Int ?? 0,
                                        viewport: try XCTUnwrap(rect(c["viewport"])), rows: rows, handle: handle,
                                        list: rect(c["list"]),
                                        canScrollUp: c["canScrollUp"] as? Bool ?? true,
                                        canScrollDown: c["canScrollDown"] as? Bool ?? true)
            if let fail = c["fail"] as? String {
                XCTAssertEqual(got, .fail(fail), name)
            } else {
                let p = try XCTUnwrap(c["press"] as? [Double]), r = try XCTUnwrap(c["release"] as? [Double])
                XCTAssertEqual(got, .gesture(press: CGPoint(x: p[0], y: p[1]), release: CGPoint(x: r[0], y: r[1])), name)
            }
        }
    }
}
