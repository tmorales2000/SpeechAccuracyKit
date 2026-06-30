import XCTest
@testable import SpeechAccuracyKit

/// Deterministic stand-in for a real embedding grader so harness logic and the
/// pass/fail gate can be tested without platform frameworks or audio.
struct FakeSemanticGrader: SemanticGrader {
    let value: Double
    func proximity(reference: String, hypothesis: String) -> Double { value }
}

final class AccuracyHarnessTests: XCTestCase {

    func testGradeCombinesBothMetrics() {
        let harness = AccuracyHarness(semantic: FakeSemanticGrader(value: 0.9))
        let r = harness.grade(reference: "play the next song",
                              hypothesis: "play the next track")
        XCTAssertEqual(r.wordErrorRate, 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.semanticProximity, 0.9, accuracy: 1e-9)
    }

    func testGatePassesWhenBothWithinThreshold() {
        let r = AccuracyResult(reference: "a", hypothesis: "a",
                               wordErrorRate: 0.1, semanticProximity: 0.85)
        XCTAssertTrue(r.passes(maxWER: 0.2, minProximity: 0.8))
    }

    func testGateFailsOnHighWER() {
        let r = AccuracyResult(reference: "a", hypothesis: "b",
                               wordErrorRate: 0.35, semanticProximity: 0.95)
        XCTAssertFalse(r.passes(maxWER: 0.2, minProximity: 0.8))
    }

    func testGateFailsOnLowProximity() {
        // High word accuracy but off-intent: the semantic gate catches it.
        let r = AccuracyResult(reference: "a", hypothesis: "a",
                               wordErrorRate: 0.0, semanticProximity: 0.4)
        XCTAssertFalse(r.passes(maxWER: 0.2, minProximity: 0.8))
    }
}
