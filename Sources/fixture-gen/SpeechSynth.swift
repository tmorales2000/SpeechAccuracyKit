import Foundation
import AVFoundation

/// Synthesizes an utterance to a clean WAV. Pass one of the fixture pipeline:
/// produce the baseline file (also the WER reference) before any degradation.
///
/// Completion is driven by the synthesizer delegate's didFinish, not by relying
/// on a trailing zero-length buffer (whose presence varies by OS version). We
/// also count frames written so we can tell "finished, audio produced" apart
/// from "finished, nothing produced" (usually a missing voice).
/// Note: not Sendable. Used on a single thread (the CLI's main run loop).
final class SpeechSynth: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()
    private var outputFile: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0
    private var writeError: Error?
    private var finished = false
    private var outputURL: URL!

    /// Outcome of resolving a requested voice string.
    enum VoiceResolution {
        case useDefault                         // no/empty request: system default
        case found(AVSpeechSynthesisVoice)      // matched an installed voice
        case notFound                           // requested, but not installed
    }

    /// Resolve a user-supplied voice string (display name or identifier) to an
    /// installed voice. A nil/empty input means "use the system default".
    static func resolveVoice(_ requested: String?) -> VoiceResolution {
        guard let requested, !requested.isEmpty else { return .useDefault }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let byId = voices.first(where: { $0.identifier == requested }) {
            return .found(byId)
        }
        if let byName = voices.first(where: {
            $0.name.compare(requested, options: .caseInsensitive) == .orderedSame
        }) {
            return .found(byName)
        }
        return .notFound
    }

    /// Human-readable list of installed en-* voices, for error messages.
    static func availableEnglishVoices() -> [String] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { "\($0.name) [\($0.language)]" }
            .sorted()
    }

    static func synthesize(text: String,
                           to url: URL,
                           rate: Float? = nil,
                           voice: AVSpeechSynthesisVoice? = nil) throws {
        let instance = SpeechSynth()
        try instance.run(text: text, to: url, rate: rate, voice: voice)
    }

    private func run(text: String, to url: URL, rate: Float?,
                     voice: AVSpeechSynthesisVoice?) throws {
        outputURL = url
        synthesizer.delegate = self

        let utterance = AVSpeechUtterance(string: text)
        if let rate { utterance.rate = rate }
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.write(utterance) { [weak self] buffer in
            guard let self else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            do {
                if self.outputFile == nil {
                    self.outputFile = try AVAudioFile(
                        forWriting: url,
                        settings: pcm.format.settings,
                        commonFormat: pcm.format.commonFormat,
                        interleaved: pcm.format.isInterleaved)
                }
                try self.outputFile?.write(from: pcm)
                self.framesWritten += AVAudioFramePosition(pcm.frameLength)
            } catch {
                self.writeError = error
            }
        }

        // CRITICAL: write()'s callbacks are delivered asynchronously on the main
        // run loop. Blocking the thread (e.g. on a semaphore) deadlocks: the
        // callbacks can never fire because the thread that delivers them is
        // blocked. So we PUMP the run loop until didFinish, rather than block.
        let deadline = Date().addingTimeInterval(60)
        while !finished && writeError == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if let writeError { throw writeError }
        guard framesWritten > 0, outputFile != nil else {
            throw FixtureError.synthesisProducedNoAudio(text)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        finished = true
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        finished = true
    }
}

enum FixtureError: Error, CustomStringConvertible {
    case synthesisProducedNoAudio(String)
    case fileNotFound(String)
    case renderSetupFailed(String)
    case voiceNotFound(String, [String])

    var description: String {
        switch self {
        case .synthesisProducedNoAudio(let t):
            return "Synthesis produced no audio for: \"\(t)\". "
                 + "Likely no usable voice. Check: say -v '?' | grep en_US, or "
                 + "System Settings > Accessibility > Spoken Content > System Voice "
                 + "and download an English voice."
        case .fileNotFound(let p):      return "File not found: \(p)"
        case .renderSetupFailed(let m): return "Offline render setup failed: \(m)"
        case .voiceNotFound(let req, let available):
            let list = available.isEmpty ? "(none found)"
                : "\n  " + available.joined(separator: "\n  ")
            return "Requested voice not installed: \"\(req)\".\n"
                 + "Available English voices:" + list
        }
    }
}
