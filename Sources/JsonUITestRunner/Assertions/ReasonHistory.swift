import Foundation

/// The reasons an auto-waiting assertion gave while it waited, in order.
///
/// pollUntil used to report only what it saw last — and for `visible` not
/// even a reason, just "not visible". When the reason changed while waiting
/// (below the fold for two seconds, then removed by the app's own polling)
/// the failure could not say so, and the reader looked for an element that
/// was never rendered instead of one that was below the fold.
///
/// The block is the same on the web and Android drivers; the first line (the
/// assertion's own Expected / Actual) is this driver's own.
struct ReasonHistory {
    /// `reason` is the first line of what a failed look said: what consecutive
    /// looks fold on. `start` is seconds since the poll started.
    struct Segment: Equatable {
        let reason: String
        let start: TimeInterval
    }

    /// Above this many segments the middle is elided.
    static let maxSegments = 8
    private static let head = 3
    private static let tail = 4

    private(set) var segments: [Segment] = []

    /// Record one failed look. Folds into the current segment when the reason
    /// repeats the previous look's; A → B → A stays three segments.
    mutating func observe(_ reason: String, at time: TimeInterval) {
        let key = reason.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? reason
        if segments.last?.reason == key { return }
        segments.append(Segment(reason: key, start: time))
    }

    /// The block under the first line; nil when the reason never changed, so
    /// a one-reason failure is exactly the message it always was.
    func block(end: TimeInterval) -> String? {
        segments.count < 2 ? nil : Self.render(segments, end: end)
    }

    static func render(_ segments: [Segment], end: TimeInterval) -> String {
        var rows: [String] = []
        for (i, s) in segments.enumerated() {
            let until = i + 1 < segments.count ? segments[i + 1].start : end
            rows.append("    \(seconds(s.start))–\(seconds(until))s  \(withoutSubject(s.reason))")
        }
        if rows.count > maxSegments {
            rows = Array(rows.prefix(head)) + ["    … \(rows.count - head - tail) more"] + Array(rows.suffix(tail))
        }
        return (["  waited \(seconds(end))s; the reason changed while waiting:"] + rows).joined(separator: "\n")
    }

    /// The first line already names the element; the rows do not repeat it.
    private static func withoutSubject(_ reason: String) -> String {
        guard let range = reason.range(of: "^Element '[^']*' ", options: .regularExpression) else { return reason }
        return String(reason[range.upperBound...])
    }

    private static func seconds(_ t: TimeInterval) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), max(0, t))
    }
}
