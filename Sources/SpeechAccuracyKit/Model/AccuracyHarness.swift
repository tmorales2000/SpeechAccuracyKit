import Foundation

/// Composes the two grading layers into a single AccuracyResult and, on device,
/// drives recognition end to end. The grading half is platform-independent and
/// unit-testable without audio; the recognition half is gated behind Speech.
public struct AccuracyHarness: Sendable {

    private let semantic: SemanticGrader
    private let classifier: IntentClassifier?

    public init(semantic: SemanticGrader, classifier: IntentClassifier? = nil) {
        self.semantic = semantic
        self.classifier = classifier
    }

    /// Grade an already-produced hypothesis against a reference. This is the
    /// pure path: no audio, no Speech framework, fully testable.
    public func grade(reference: String, hypothesis: String) -> AccuracyResult {
        let wer = WERGrader.wer(reference: reference, hypothesis: hypothesis)
        let prox = semantic.proximity(reference: reference, hypothesis: hypothesis)
        return AccuracyResult(
            reference: reference,
            hypothesis: hypothesis,
            wordErrorRate: wer,
            semanticProximity: prox
        )
    }

    /// Full three-stage evaluation. Runs the intent classifier twice, once on
    /// the perfect reference transcript and once on the ASR hypothesis, so the
    /// diagnosis can separate a comprehension failure from a recognition one.
    /// Requires a classifier; falls back to reference==hypothesis intent if nil.
    public func gradeStaged(reference: String,
                            hypothesis: String,
                            expected: ExpectedIntent,
                            responseText: String) -> StagedResult {
        let wer = WERGrader.wer(reference: reference, hypothesis: hypothesis)
        let prox = semantic.proximity(reference: reference, hypothesis: responseText)

        let clf = classifier ?? RuleBasedClassifier()
        let onRef = expected.matches(clf.classify(reference))
        let onHyp = expected.matches(clf.classify(hypothesis))

        return StagedResult(
            reference: reference,
            hypothesis: hypothesis,
            wordErrorRate: wer,
            intentOnReference: onRef,
            intentOnHypothesis: onHyp,
            responseProximity: prox
        )
    }
}

#if canImport(Speech)
import Speech

extension AccuracyHarness {
    /// Full on-device path: recognize a fixture's audio, then grade.
    public func evaluate(fixture: UtteranceFixture,
                         bundle: Bundle,
                         recognizer: OnDeviceSpeechRecognizer) async throws -> AccuracyResult {
        guard let url = bundle.url(forResource: fixture.audioResource,
                                   withExtension: fixture.audioExtension) else {
            throw RecognitionError.fileNotFound(
                "\(fixture.audioResource).\(fixture.audioExtension)")
        }
        let hypothesis = try await recognizer.transcribe(url: url)
        return grade(reference: fixture.reference, hypothesis: hypothesis)
    }
}
#endif
