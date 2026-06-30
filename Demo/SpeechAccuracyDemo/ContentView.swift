import SwiftUI
import SpeechAccuracyKit

/// Minimal three-stage demo. You give it:
///   - what the person meant to say (reference),
///   - what recognition heard (hypothesis), editable so you can simulate a mishear,
///   - the answer the assistant returned.
/// It runs ASR scoring, NLU comprehension (twice), and response proximity, then
/// shows which stage owns the failure. The tamarind preset is loaded by default.
struct ContentView: View {
    @State private var reference = "what is tamarind"
    @State private var hypothesis = "what is tamarind"
    @State private var response = "Tammaron is a community in Texas."
    @State private var expectedIntent = "get_info"
    @State private var expectedSubject = "tamarind"
    @State private var misresolve = true   // tamarind -> tammaron, models NLU error
    @State private var result: StagedResult?

    private let maxWER = 0.20
    private let minProximity = 0.80

    private var harness: AccuracyHarness {
        let resolver = misresolve ? ["tamarind": "tammaron"] : [:]
        return AccuracyHarness(semantic: bestAvailableGrader(),
                               classifier: RuleBasedClassifier(entityResolver: resolver))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                presets

                field("What they meant", text: $reference)
                field("What Siri heard", text: $hypothesis)
                field("What Siri answered", text: $response)

                HStack(spacing: 12) {
                    field("Expected intent", text: $expectedIntent)
                    field("Expected subject", text: $expectedSubject)
                }

                Toggle("Simulate NLU entity misresolution (tamarind to tammaron)",
                       isOn: $misresolve)
                    .font(.caption)

                Button(action: run) {
                    Text("Run pipeline")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                if let result {
                    resultView(result)
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speech Accuracy")
                .font(.largeTitle.bold())
            Text("Localize a wrong answer to recognition, comprehension, or response.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets").font(.caption).foregroundStyle(.secondary)
            HStack {
                presetButton("Tamarind (comprehension)") {
                    reference = "what is tamarind"; hypothesis = "what is tamarind"
                    response = "Tammaron is a community in Texas."
                    expectedIntent = "get_info"; expectedSubject = "tamarind"
                    misresolve = true
                }
                presetButton("Mishear (recognition)") {
                    reference = "what is tamarind"; hypothesis = "what is tammaron"
                    response = "Tammaron is a community in Texas."
                    expectedIntent = "get_info"; expectedSubject = "tamarind"
                    misresolve = false
                }
                presetButton("Clean (pass)") {
                    reference = "set a timer for ten minutes"
                    hypothesis = "set a timer for ten minutes"
                    response = "Timer set for ten minutes."
                    expectedIntent = "set_timer"; expectedSubject = ""
                    misresolve = false
                }
            }
        }
    }

    private func presetButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption)
            .buttonStyle(.bordered)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func run() {
        let expected = ExpectedIntent(
            intent: expectedIntent,
            requiredSlots: expectedSubject.isEmpty ? [:] : ["subject": expectedSubject])
        result = harness.gradeStaged(
            reference: reference,
            hypothesis: hypothesis,
            expected: expected,
            responseText: response)
    }

    @ViewBuilder
    private func resultView(_ r: StagedResult) -> some View {
        let stage = r.diagnose(maxWER: maxWER, minProximity: minProximity)
        VStack(alignment: .leading, spacing: 14) {
            verdictBanner(stage)

            stageRow("1. Recognition (ASR)",
                     detail: "WER \(pct(r.wordErrorRate))",
                     ok: r.wordErrorRate <= maxWER)
            stageRow("2. Comprehension (NLU)",
                     detail: r.intentOnReference
                        ? "intent correct on clean text"
                        : "intent wrong on clean text",
                     ok: r.intentOnReference)
            stageRow("   NLU on recognized text",
                     detail: r.intentOnHypothesis ? "intent held" : "intent broke",
                     ok: r.intentOnHypothesis)
            stageRow("3. Response",
                     detail: "proximity \(pct(r.responseProximity))",
                     ok: r.responseProximity >= minProximity)
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func verdictBanner(_ stage: StagedResult.FailureStage) -> some View {
        let (text, color): (String, Color) = {
            switch stage {
            case .none:          return ("All stages passed", .green)
            case .recognition:   return ("Failure: Recognition stage", .orange)
            case .comprehension: return ("Failure: Comprehension stage", .red)
            case .response:      return ("Failure: Response stage", .purple)
            }
        }()
        return Text(text)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stageRow(_ title: String, detail: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func pct(_ x: Double) -> String {
        String(format: "%.0f%%", x * 100)
    }
}

/// Use NLEmbedding when the platform provides it; otherwise fall back to the
/// library's lexical proximity so the demo still runs anywhere.
private func bestAvailableGrader() -> SemanticGrader {
    #if canImport(NaturalLanguage)
    return NLEmbeddingGrader()
    #else
    return LexicalProximityGrader()
    #endif
}

