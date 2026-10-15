import XCTest
@testable import JsonUITestRunner

/// alertTap's tap-and-check (DismissTapConfirm), on a fake clock. The first
/// case is the measured sheet: the first tap is lost while it is still being
/// presented, the second closes it.
final class DismissTapConfirmTests: XCTestCase {
    private final class Fake {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        var present = true
        var hittableFrom: TimeInterval = 0
        /// Taps that are lost before this one lands.
        var tapsLost = 0
        var taps = 0
        var t: TimeInterval { clock.timeIntervalSinceReferenceDate }
    }

    private func run(_ fake: Fake, budget: TimeInterval = 8) -> DismissTapConfirm.Outcome {
        DismissTapConfirm().run(
            deadline: fake.clock.addingTimeInterval(budget),
            exists: { fake.present },
            hittable: { fake.t >= fake.hittableFrom },
            tap: {
                fake.taps += 1
                if fake.taps > fake.tapsLost { fake.present = false }
            },
            sleep: { fake.clock = fake.clock.addingTimeInterval($0) },
            now: { fake.clock })
    }

    func testALostFirstTapIsTappedAgain() {
        let fake = Fake()
        fake.tapsLost = 1
        XCTAssertEqual(run(fake), .dismissed(taps: 2))
    }

    func testOneTapThatTakesIsOneTap() {
        let fake = Fake()
        XCTAssertEqual(run(fake), .dismissed(taps: 1))
    }

    func testNoTapUntilTheButtonIsHittable() {
        let fake = Fake()
        fake.hittableFrom = 0.5
        XCTAssertEqual(run(fake), .dismissed(taps: 1))
        XCTAssertGreaterThanOrEqual(fake.t, 0.5)
    }

    func testAButtonThatNeverGoesFailsInsteadOfPassing() {
        // Before: alertTap returned OK after the first tap whatever happened.
        let fake = Fake()
        fake.tapsLost = .max
        guard case .stayed(let taps) = run(fake, budget: 3) else { return XCTFail("a button that stayed passed") }
        XCTAssertGreaterThan(taps, 1)
    }

    func testNeverHittableMakesNoTap() {
        let fake = Fake()
        fake.hittableFrom = .infinity
        XCTAssertEqual(run(fake, budget: 2), .neverHittable)
        XCTAssertEqual(fake.taps, 0)
    }

    func testGoneBeforeAnyTapIsNotATap() {
        let fake = Fake()
        fake.present = false
        XCTAssertEqual(run(fake), .dismissed(taps: 0))
    }
}
