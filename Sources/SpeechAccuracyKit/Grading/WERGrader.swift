import Foundation

/// Computes Word Error Rate via Levenshtein (edit) distance over word tokens.
/// WER = (substitutions + insertions + deletions) / reference_word_count.
///
/// This is pure Swift with no platform dependencies, so it is unit-testable
/// on any platform and forms the deterministic backbone of the harness.
public enum WERGrader {

    /// Normalize a transcript to comparable tokens: lowercase, strip
    /// punctuation, collapse whitespace. Matches the spirit of the Python
    /// checker's ATS-style normalization before comparison.
    public static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let stripped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        return String(stripped)
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
    }

    /// Word Error Rate in [0, 1+]. Returns 0 for identical token streams.
    /// If the reference is empty and the hypothesis is not, returns 1.0.
    public static func wer(reference: String, hypothesis: String) -> Double {
        let ref = tokenize(reference)
        let hyp = tokenize(hypothesis)

        if ref.isEmpty {
            return hyp.isEmpty ? 0.0 : 1.0
        }

        let distance = levenshtein(ref, hyp)
        return Double(distance) / Double(ref.count)
    }

    /// Classic dynamic-programming edit distance over arrays of tokens.
    static func levenshtein(_ a: [String], _ b: [String]) -> Int {
        let n = a.count
        let m = b.count
        if n == 0 { return m }
        if m == 0 { return n }

        var previous = Array(0...m)
        var current = [Int](repeating: 0, count: m + 1)

        for i in 1...n {
            current[0] = i
            for j in 1...m {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[m]
    }
}
