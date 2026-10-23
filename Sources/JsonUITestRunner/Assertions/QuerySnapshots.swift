import XCTest

extension XCUIElementQuery {
    /// Every element the query matches, one snapshot each, in index order.
    ///
    /// Not `0..<count` and an attribute per index: every read resolves the
    /// query again, so an element that left after the count makes the last
    /// index match nothing, and XCUITest does not answer that read — it
    /// retries for about two seconds, records "Failed to get matching
    /// snapshot: No matches found for Element at index N" as a test failure
    /// and stops the test, whatever continueAfterFailure says (a tablet flow
    /// under `assert: screen`, three runs in three: jsonui-cli ticket
    /// 2026-10-23-test-ios-hittable-screens-index-race-on-shrinking-marker-query).
    ///
    /// Here an index that matches nothing ends the read: `exists` answers
    /// without retrying, and `snapshot()` throws instead of recording, for an
    /// element that leaves between the two. The query has fewer elements by
    /// then, so every later index is past the end as well. One snapshot per
    /// element also reads all of its attributes at one moment.
    ///
    /// What comes back is what the query matched while it was read: an
    /// element that left is not in it, and one that left before a later
    /// index was read moves the rest down by one, so a caller that needs
    /// every element compares the size with `count`.
    func snapshotsBoundByIndex() -> [XCUIElementSnapshot] {
        var read: [XCUIElementSnapshot] = []
        for index in 0..<count {
            let element = element(boundBy: index)
            guard element.exists, let snapshot = try? element.snapshot() else { break }
            read.append(snapshot)
        }
        return read
    }
}
