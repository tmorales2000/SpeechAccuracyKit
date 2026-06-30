import Foundation

/// Dependency-free fallback grader: Jaccard token overlap. Coarse but runs on
/// any platform with no frameworks, so the harness and demo stay functional
/// without NaturalLanguage. Production path is NLEmbedding or Core ML.
public struct LexicalProximityGrader: SemanticGrader {
    public init() {}
    public func proximity(reference: String, hypothesis: String) -> Double {
        let a = Set(WERGrader.tokenize(reference))
        let b = Set(WERGrader.tokenize(hypothesis))
        if a.isEmpty && b.isEmpty { return 1.0 }
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }
}

/// Strategy seam for semantic grading. v1 ships an NLEmbedding-backed
/// implementation. The same protocol accepts a Core ML sentence-transformer
/// (better intent discrimination) or an NLI entailment grader (claim-level
/// Supported/Contradicted/Not-Found, ported from the Python checker) without
/// touching call sites. This is the extension point you describe in interviews.
public protocol SemanticGrader: Sendable {
    /// Proximity in [0, 1]: 1.0 == same intent neighborhood.
    func proximity(reference: String, hypothesis: String) -> Double
}

#if canImport(NaturalLanguage)
import NaturalLanguage

/// v1 grader: on-device word embeddings via Apple's NaturalLanguage framework.
/// Zero dependencies, no model bundling, runs immediately on device.
/// Sentence proximity is approximated by mean-pooling word vectors and taking
/// cosine similarity. Good enough to cluster paraphrases and catch off-intent
/// transcriptions; documented upgrade path is a Core ML sentence-transformer.
public struct NLEmbeddingGrader: SemanticGrader {
    private let language: NLLanguage

    public init(language: NLLanguage = .english) {
        self.language = language
    }

    public func proximity(reference: String, hypothesis: String) -> Double {
        guard let embedding = NLEmbedding.wordEmbedding(for: language) else {
            return 0.0
        }
        guard let refVec = meanVector(reference, embedding),
              let hypVec = meanVector(hypothesis, embedding) else {
            return 0.0
        }
        let sim = cosine(refVec, hypVec)
        // Map cosine [-1, 1] into [0, 1].
        return max(0.0, min(1.0, (sim + 1.0) / 2.0))
    }

    private func meanVector(_ text: String, _ embedding: NLEmbedding) -> [Double]? {
        let tokens = WERGrader.tokenize(text)
        guard !tokens.isEmpty else { return nil }
        var sum: [Double]? = nil
        var count = 0
        for token in tokens {
            guard let vec = embedding.vector(for: token) else { continue }
            if sum == nil { sum = [Double](repeating: 0, count: vec.count) }
            for i in 0..<vec.count { sum![i] += vec[i] }
            count += 1
        }
        guard var s = sum, count > 0 else { return nil }
        for i in 0..<s.count { s[i] /= Double(count) }
        return s
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (sqrt(na) * sqrt(nb))
    }
}
#endif

/// Documented next step: swap in a sentence-transformer exported to Core ML
/// for stronger sentence-level intent discrimination. Same export pipeline
/// used for on-device vision-language models. Stubbed intentionally.
public struct CoreMLSentenceGrader: SemanticGrader {
    public init() {}
    public func proximity(reference: String, hypothesis: String) -> Double {
        fatalError("Not implemented in v1. Upgrade path: bundle a Core ML "
                 + "sentence-transformer and mean-pool token embeddings.")
    }
}

/// Documented next step: port the Python RoBERTa-MNLI entailment grader
/// (Supported / Contradicted / Not Found) to on-device Core ML. This grades
/// claim-level contradiction rather than proximity. Stubbed intentionally.
public struct NLIGrader: SemanticGrader {
    public init() {}
    public func proximity(reference: String, hypothesis: String) -> Double {
        fatalError("Not implemented in v1. Upgrade path: Core ML RoBERTa-MNLI, "
                 + "map entailment -> high, neutral -> mid, contradiction -> low.")
    }
}
