import Foundation

/// A single graded utterance: what we expected, what recognition produced,
/// and the quality scores. Mirrors the structured verdict output of the
/// Python ai-content-accuracy-checker (claim -> verdict/confidence), adapted
/// to the speech domain (reference -> WER + semantic proximity).
public struct AccuracyResult: Sendable, Equatable {
    /// The reference (ground-truth) transcript for the utterance.
    public let reference: String
    /// The hypothesis produced by on-device speech recognition.
    public let hypothesis: String
    /// Word Error Rate in [0, 1]. 0.0 means a perfect transcription.
    /// This is the ASR-accuracy layer: edit distance over words, not semantics.
    public let wordErrorRate: Double
    /// Semantic proximity in [0, 1]. 1.0 means hypothesis and reference are
    /// in the same intent neighborhood. This is the response-grading layer:
    /// "is this utterance in the vicinity of what we think it is."
    public let semanticProximity: Double

    public init(reference: String,
                hypothesis: String,
                wordErrorRate: Double,
                semanticProximity: Double) {
        self.reference = reference
        self.hypothesis = hypothesis
        self.wordErrorRate = wordErrorRate
        self.semanticProximity = semanticProximity
    }

    /// Whether this result passes both quality gates.
    /// Used as the assertion target in XCTest and as a CI/CD build gate,
    /// the native analogue of the Python repo's "fail builds if faithfulness < 0.8".
    public func passes(maxWER: Double, minProximity: Double) -> Bool {
        wordErrorRate <= maxWER && semanticProximity >= minProximity
    }
}

/// One ground-truth fixture: an audio file bundled with the test target, the
/// reference transcript it should produce, and the KNOWN quality baseline for
/// this fixture on the current recognizer.
///
/// The baselines make this a characterization (regression) test rather than a
/// perfection test. A fixture's `maxWER` is not "what we wish recognition did"
/// but "what it actually does today." The test fails only if recognition gets
/// WORSE than this established baseline. Example: the recognizer cannot reliably
/// transcribe "tamarind" (it hears "tamarin"), so that fixture's baseline WER is
/// ~0.34, not 0. That is a recorded fact about the recognizer, not a pass we are
/// papering over.
public struct UtteranceFixture: Sendable {
    public let audioResource: String   // bundled resource name, e.g. "set_timer_10min"
    public let audioExtension: String  // e.g. "wav", "m4a"
    public let reference: String       // expected transcript / intent text
    public let maxWER: Double           // known WER ceiling for this fixture
    public let minProximity: Double     // known proximity floor for this fixture

    public init(audioResource: String,
                audioExtension: String,
                reference: String,
                maxWER: Double = 0.20,
                minProximity: Double = 0.80) {
        self.audioResource = audioResource
        self.audioExtension = audioExtension
        self.reference = reference
        self.maxWER = maxWER
        self.minProximity = minProximity
    }
}
