import XCTest
@testable import SpeechAccuracyKit

final class WERGraderTests: XCTestCase {

    func testIdenticalIsZero() {
        XCTAssertEqual(WERGrader.wer(reference: "set a timer for ten minutes",
                                     hypothesis: "set a timer for ten minutes"),
                       0.0, accuracy: 1e-9)
    }

    func testCaseAndPunctuationNormalized() {
        XCTAssertEqual(WERGrader.wer(reference: "Call Mom.",
                                     hypothesis: "call mom"),
                       0.0, accuracy: 1e-9)
    }

    func testSingleSubstitution() {
        // one wrong word out of four -> 0.25
        XCTAssertEqual(WERGrader.wer(reference: "play the next song",
                                     hypothesis: "play the next track"),
                       0.25, accuracy: 1e-9)
    }

    func testInsertion() {
        // reference 3 words, one inserted -> 1/3
        XCTAssertEqual(WERGrader.wer(reference: "turn off lights",
                                     hypothesis: "turn off the lights"),
                       1.0 / 3.0, accuracy: 1e-9)
    }

    func testDeletion() {
        // reference 4 words, one deleted -> 0.25
        XCTAssertEqual(WERGrader.wer(reference: "what is the weather",
                                     hypothesis: "what is weather"),
                       0.25, accuracy: 1e-9)
    }

    func testEmptyReferenceWithHypothesis() {
        XCTAssertEqual(WERGrader.wer(reference: "", hypothesis: "hello"),
                       1.0, accuracy: 1e-9)
    }

    func testTokenize() {
        XCTAssertEqual(WERGrader.tokenize("Hey, Siri! Set a timer."),
                       ["hey", "siri", "set", "a", "timer"])
    }
}
