import Foundation

/// The intent a stage believes an utterance expressed. Slots are the extracted
/// entities (e.g. ["subject": "tamarind"]). This is what NLU produces and what
/// the tamarind class of bugs corrupts.
public struct IntentResult: Sendable, Equatable {
    public let intent: String
    public let slots: [String: String]

    public init(intent: String, slots: [String: String] = [:]) {
        self.intent = intent
        self.slots = slots
    }
}

/// A full three-stage evaluation of one utterance. Each stage answers a
/// different question, and separating them is the whole point: the same wrong
/// final answer can come from three different broken stages with three
/// different owners.
///
///  1. ASR  — "what did Siri hear?"        WER vs reference transcript.
///  2. NLU  — "what did Siri comprehend?"  intent/slot match vs expected intent,
///            run on BOTH the reference transcript and the ASR hypothesis so we
///            can tell a comprehension failure apart from a recognition failure.
///  3. RESP — "is the answer in the right neighborhood?"  semantic proximity.
public struct StagedResult: Sendable, Equatable {
    public let reference: String
    public let hypothesis: String

    // Stage 1: recognition
    public let wordErrorRate: Double

    // Stage 2: comprehension, measured twice to isolate error propagation.
    public let intentOnReference: Bool   // NLU correct when fed perfect text
    public let intentOnHypothesis: Bool  // NLU correct when fed actual ASR text

    // Stage 3: response
    public let responseProximity: Double

    public init(reference: String,
                hypothesis: String,
                wordErrorRate: Double,
                intentOnReference: Bool,
                intentOnHypothesis: Bool,
                responseProximity: Double) {
        self.reference = reference
        self.hypothesis = hypothesis
        self.wordErrorRate = wordErrorRate
        self.intentOnReference = intentOnReference
        self.intentOnHypothesis = intentOnHypothesis
        self.responseProximity = responseProximity
    }

    /// Localizes the dominant failure to a single stage. This is the output
    /// that turns "wrong" into an actionable, ownable defect.
    public enum FailureStage: String, Sendable {
        case none
        case recognition       // ASR misheard; comprehension was fine on clean text
        case comprehension     // heard fine, still misunderstood (the tamarind case)
        case response          // heard and understood, answer still off
    }

    public func diagnose(maxWER: Double, minProximity: Double) -> FailureStage {
        let recognitionOK = wordErrorRate <= maxWER
        let responseOK = responseProximity >= minProximity

        // NLU correct on clean text but wrong on the ASR output, and ASR was
        // bad: recognition broke and propagated.
        if intentOnReference && !intentOnHypothesis && !recognitionOK {
            return .recognition
        }
        // NLU wrong even on the perfect reference transcript: comprehension
        // itself is broken. This is the tamarind-to-Tammaron entity failure.
        if !intentOnReference {
            return .comprehension
        }
        // Heard right, understood right, answer still off-topic.
        if recognitionOK && intentOnReference && intentOnHypothesis && !responseOK {
            return .response
        }
        if recognitionOK && responseOK && intentOnHypothesis {
            return .none
        }
        // Mixed/!recognitionOK with NLU robust to it: still a recognition issue.
        return recognitionOK ? .response : .recognition
    }
}
