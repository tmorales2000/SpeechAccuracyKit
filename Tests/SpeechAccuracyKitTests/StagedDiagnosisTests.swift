import XCTest
@testable import SpeechAccuracyKit

final class StagedDiagnosisTests: XCTestCase {

    let maxWER = 0.20
    let minProximity = 0.80

    /// Everything works: heard right, understood right, answer on-topic.
    func testAllPass() {
        let r = StagedResult(reference: "set a timer for ten minutes",
                             hypothesis: "set a timer for ten minutes",
                             wordErrorRate: 0.0,
                             intentOnReference: true,
                             intentOnHypothesis: true,
                             responseProximity: 0.95)
        XCTAssertEqual(r.diagnose(maxWER: maxWER, minProximity: minProximity), .none)
    }

    /// The tamarind case. ASR heard the word correctly (WER low), but NLU
    /// resolved the entity wrong even on the perfect transcript: it answered
    /// about Tammaron, Texas instead of the fruit. Comprehension is broken,
    /// not recognition. The harness must point at the NLU stage.
    func testTamarindIsComprehensionFailure() {
        let r = StagedResult(reference: "what is tamarind",
                             hypothesis: "what is tamarind",
                             wordErrorRate: 0.0,
                             intentOnReference: false,   // wrong even on clean text
                             intentOnHypothesis: false,
                             responseProximity: 0.30)     // Tammaron != tamarind
        XCTAssertEqual(r.diagnose(maxWER: maxWER, minProximity: minProximity),
                       .comprehension)
    }

    /// ASR misheard the utterance. NLU is fine on clean text but fed garbage by
    /// recognition. The fix belongs to the acoustic/recognition stage.
    func testMishearingIsRecognitionFailure() {
        let r = StagedResult(reference: "what is tamarind",
                             hypothesis: "what is tammaron",
                             wordErrorRate: 0.5,
                             intentOnReference: true,
                             intentOnHypothesis: false,
                             responseProximity: 0.40)
        XCTAssertEqual(r.diagnose(maxWER: maxWER, minProximity: minProximity),
                       .recognition)
    }

    /// Heard right, understood right, but the generated answer is off-topic.
    /// Recognition and comprehension are clean; the response stage owns it.
    func testOffTopicAnswerIsResponseFailure() {
        let r = StagedResult(reference: "what is tamarind",
                             hypothesis: "what is tamarind",
                             wordErrorRate: 0.0,
                             intentOnReference: true,
                             intentOnHypothesis: true,
                             responseProximity: 0.45)
        XCTAssertEqual(r.diagnose(maxWER: maxWER, minProximity: minProximity),
                       .response)
    }

    /// The rule-based classifier resolves a clean info query's subject.
    func testClassifierExtractsSubject() {
        let clf = RuleBasedClassifier()
        let result = clf.classify("what is tamarind")
        XCTAssertEqual(result.intent, "get_info")
        XCTAssertEqual(result.slots["subject"], "tamarind")
    }

    /// A seeded entity misresolution produces a genuine comprehension error on
    /// perfectly recognized text: the tamarind-to-Tammaron bug.
    func testEntityMisresolutionModelsComprehensionFailure() {
        let clf = RuleBasedClassifier(entityResolver: ["tamarind": "tammaron"])
        let expected = ExpectedIntent(intent: "get_info",
                                      requiredSlots: ["subject": "tamarind"])
        // Word heard perfectly, but NLU binds it to the wrong entity.
        XCTAssertFalse(expected.matches(clf.classify("what is tamarind")))
    }
}
