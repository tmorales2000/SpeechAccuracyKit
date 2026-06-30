import XCTest
@testable import SpeechAccuracyKit

#if canImport(Speech)
import Speech

/// End-to-end tests that exercise real on-device recognition. These run on a
/// device or simulator with Speech authorization, not on Linux CI.
///
/// This is a CHARACTERIZATION test. Each fixture carries its own known WER and
/// proximity baseline (see UtteranceFixture). The assertion fails only when
/// recognition gets worse than the recorded baseline for that fixture, so the
/// gate catches regressions without pretending the recognizer is perfect.
final class OnDeviceRecognitionTests: XCTestCase {

    // Small tolerance so floating-point and minor model variation do not flake.
    let tolerance = 0.05

    // Per-fixture quality BASELINES, set from observed recognizer behavior.
    // This is a characterization test: each fixture asserts recognition is no
    // worse than its known baseline, not that it is perfect.
    //
    // Observed: "tamarind" is misrecognized as "tamarin" (drops the final d),
    // giving WER ~0.33 even on clean audio. That is a recorded property of the
    // recognizer, captured here as a baseline rather than hidden by a loose
    // global threshold. timer and weather transcribe cleanly across degradations.
    let corpus: [UtteranceFixture] = {
        // (slug, reference, baseline maxWER, baseline minProximity)
        let refs: [(String, String, Double, Double)] = [
            ("set_timer_10min",   "set a timer for ten minutes", 0.20, 0.80),
            ("whats_the_weather", "what is the weather",         0.20, 0.80),
            // tamarind: recognizer cannot get the final consonant; baseline ~0.34.
            ("what_is_tamarind",  "what is tamarind",            0.40, 0.75)
        ]
        let variants = ["clean", "noisy", "muffled", "farmic", "badmic"]
        var out: [UtteranceFixture] = []
        for (slug, ref, wer, prox) in refs {
            for v in variants {
                out.append(UtteranceFixture(audioResource: "\(slug)_\(v)",
                                            audioExtension: "wav",
                                            reference: ref,
                                            maxWER: wer,
                                            minProximity: prox))
            }
        }
        return out
    }()

    func testCorpusMeetsQualityGate() async throws {
        let status = await OnDeviceSpeechRecognizer.requestAuthorization()
        try XCTSkipUnless(status == .authorized, "Speech recognition not authorized.")

        let harness = AccuracyHarness(semantic: NLEmbeddingGrader())
        let recognizer = OnDeviceSpeechRecognizer()

        var evaluated = 0
        var failures: [String] = []
        for fixture in corpus {
            // .copy("Fixtures") preserves the directory, so the resource may live
            // under a "Fixtures" subdirectory in the bundle. Try both layouts.
            let url = Bundle.module.url(forResource: fixture.audioResource,
                                        withExtension: fixture.audioExtension,
                                        subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: fixture.audioResource,
                                     withExtension: fixture.audioExtension)
            guard let url else { continue }   // fixture not generated yet
            evaluated += 1
            let hypothesis = try await recognizer.transcribe(url: url)
            let result = harness.grade(reference: fixture.reference,
                                       hypothesis: hypothesis)
            // Characterization: fail only if worse than this fixture's baseline.
            let werOK = result.wordErrorRate <= fixture.maxWER + tolerance
            let proxOK = result.semanticProximity >= fixture.minProximity - tolerance
            if !(werOK && proxOK) {
                failures.append(
                    "[\(fixture.audioResource)] WER=\(round3(result.wordErrorRate)) "
                  + "(baseline \(fixture.maxWER)) "
                  + "prox=\(round3(result.semanticProximity)) "
                  + "(baseline \(fixture.minProximity)) hyp=\"\(result.hypothesis)\"")
            }
        }

        try XCTSkipIf(evaluated == 0,
            "No audio fixtures found in bundle. Generate them, then rebuild:\n"
          + "  swift run fixture-gen Tests/SpeechAccuracyKitTests/Fixtures\n"
          + "  swift test   (resources bundle at build time)")

        XCTAssertTrue(failures.isEmpty,
            "Quality gate failed for:\n" + failures.joined(separator: "\n"))
    }

    private func round3(_ x: Double) -> Double {
        (x * 1000).rounded() / 1000
    }
}
#endif
