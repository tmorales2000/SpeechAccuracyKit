import Foundation

/// fixture-gen: generate a speech-robustness fixture corpus.
///
/// For each utterance it writes a clean WAV (the WER reference) and one degraded
/// WAV per profile (noisy, reverb, muffled, slow, bad-mic). Output lands in the
/// directory given as a positional argument, default ./Fixtures.
///
/// Usage:
///   swift run fixture-gen [output-dir] [--voice "Voice Name or identifier"]
///
/// --voice accepts a display name (e.g. "Samantha") or a voice identifier. If
/// the requested voice is not installed, the tool prints the available English
/// voices and exits without generating anything. Omit it to use the system
/// default en-US voice.
///
/// These are synthetic degradations of synthetic speech. They illustrate the
/// categories of real-world degradation a robustness suite must cover; they do
/// not replace physical device-lab acoustic testing.

import AVFoundation

func parseArgs() -> (outDir: URL, voiceArg: String?) {
    var positional: [String] = []
    var voiceArg: String? = nil
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--voice" {
            guard i + 1 < args.count else {
                FileHandle.standardError.write(Data("--voice needs a value\n".utf8))
                exit(2)
            }
            voiceArg = args[i + 1]
            i += 2
        } else {
            positional.append(a)
            i += 1
        }
    }
    let path = positional.first ?? "./Fixtures"
    return (URL(fileURLWithPath: path, isDirectory: true), voiceArg)
}

let (outDir, voiceArg) = parseArgs()

struct Item {
    let slug: String
    let text: String
}

// Keep references identical across a variant group so the harness measures
// robustness to degradation, not a different target.
let corpus: [Item] = [
    Item(slug: "set_timer_10min", text: "set a timer for ten minutes"),
    Item(slug: "whats_the_weather", text: "what is the weather"),
    Item(slug: "what_is_tamarind", text: "what is tamarind")
]

let profiles: [(String, AudioDegrader.Profile)] = [
    ("noisy",   .noisy),
    ("muffled", .muffled),
    ("farmic",  .farMic),
    ("badmic",  .badMic)
]

func run() {
    // Resolve and validate the voice BEFORE any generation. Fail fast.
    let chosenVoice: AVSpeechSynthesisVoice?
    switch SpeechSynth.resolveVoice(voiceArg) {
    case .notFound:
        let err = FixtureError.voiceNotFound(voiceArg ?? "",
                                             SpeechSynth.availableEnglishVoices())
        FileHandle.standardError.write(Data("Error: \(err)\n".utf8))
        exit(1)
    case .useDefault:
        chosenVoice = nil          // synth falls back to en-US default
    case .found(let v):
        chosenVoice = v
    }

    do {
        try FileManager.default.createDirectory(at: outDir,
                                                withIntermediateDirectories: true)
        let voiceLabel = chosenVoice?.name ?? "system default"
        print("Writing fixtures to \(outDir.path)")
        print("Voice: \(voiceLabel)\n")

        for item in corpus {
            let cleanURL = outDir.appendingPathComponent("\(item.slug)_clean.wav")
            try SpeechSynth.synthesize(text: item.text, to: cleanURL, voice: chosenVoice)
            print("  clean   \(cleanURL.lastPathComponent)  \"\(item.text)\"")

            for (name, profile) in profiles {
                let degURL = outDir.appendingPathComponent("\(item.slug)_\(name).wav")
                try AudioDegrader.process(input: cleanURL, output: degURL, profile: profile)
                print("  \(name.padding(toLength: 8, withPad: " ", startingAt: 0))\(degURL.lastPathComponent)")
            }
            print("")
        }

        print("Done. Reference transcript per slug:")
        for item in corpus { print("  \(item.slug): \"\(item.text)\"") }
        print("\nNote: synthetic speech, synthetic degradation. Illustrates "
            + "degradation categories; not a substitute for physical acoustic testing.")
    } catch {
        FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
        exit(1)
    }
}

run()
