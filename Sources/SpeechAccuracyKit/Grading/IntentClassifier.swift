import Foundation

/// Stage 2 seam: comprehension. Given text (reference OR ASR hypothesis),
/// classify intent and extract slots. Swap the rule-based v1 for an on-device
/// Core ML intent model or the LLM-based Siri NLU path without changing callers.
public protocol IntentClassifier: Sendable {
    func classify(_ text: String) -> IntentResult
}

/// Expected ground truth for an utterance's comprehension stage.
public struct ExpectedIntent: Sendable, Equatable {
    public let intent: String
    public let requiredSlots: [String: String]

    public init(intent: String, requiredSlots: [String: String] = [:]) {
        self.intent = intent
        self.requiredSlots = requiredSlots
    }

    /// NLU is "correct" if intent matches and every required slot matches.
    public func matches(_ result: IntentResult) -> Bool {
        guard result.intent == intent else { return false }
        for (k, v) in requiredSlots where result.slots[k] != v {
            return false
        }
        return true
    }
}

/// v1 reference classifier: keyword rules plus a small entity resolver. Not
/// production NLU; it exists so the three-stage pipeline runs end to end and the
/// failure-isolation logic is demonstrable today, including a genuine
/// comprehension (entity-resolution) failure, not a staged one.
///
/// The resolver maps a recognized subject token to a canonical entity. A
/// misresolution here is exactly the tamarind-to-Tammaron class of bug: the word
/// was heard correctly, but comprehension bound it to the wrong referent.
public struct RuleBasedClassifier: IntentClassifier {
    /// Optional seeded misresolutions, e.g. ["tamarind": "tammaron"], to model a
    /// comprehension failure that occurs even on a perfectly recognized word.
    private let entityResolver: [String: String]

    public init(entityResolver: [String: String] = [:]) {
        self.entityResolver = entityResolver
    }

    public func classify(_ text: String) -> IntentResult {
        let tokens = WERGrader.tokenize(text)
        let set = Set(tokens)

        if set.contains("timer") || (set.contains("set") && set.contains("minutes")) {
            let minutes = tokens.first(where: { Int($0) != nil })
                ?? numberWord(in: tokens) ?? ""
            return IntentResult(intent: "set_timer", slots: ["duration": minutes])
        }
        if set.contains("weather") {
            return IntentResult(intent: "get_weather")
        }
        if set.contains("call") {
            let who = tokens.last(where: { $0 != "call" }) ?? ""
            return IntentResult(intent: "make_call", slots: ["contact": who])
        }
        if set.contains("what") && set.contains("is") {
            let raw = tokens.last ?? ""
            // Entity resolution: a seeded misresolution models the tamarind bug.
            let resolved = entityResolver[raw] ?? raw
            return IntentResult(intent: "get_info", slots: ["subject": resolved])
        }
        return IntentResult(intent: "unknown")
    }

    private func numberWord(in tokens: [String]) -> String? {
        let words = ["one":"1","two":"2","three":"3","four":"4","five":"5",
                     "six":"6","seven":"7","eight":"8","nine":"9","ten":"10"]
        for t in tokens { if let n = words[t] { return n } }
        return nil
    }
}

/// Documented next step: an on-device intent model exported to Core ML, or the
/// LLM-based comprehension path. Stubbed intentionally.
public struct CoreMLIntentClassifier: IntentClassifier {
    public init() {}
    public func classify(_ text: String) -> IntentResult {
        fatalError("Not implemented in v1. Upgrade path: Core ML intent "
                 + "classifier or LLM NLU; same on-device export pipeline.")
    }
}
