import Foundation
import AVFoundation

/// Pass two of the fixture pipeline: read a clean WAV, apply degradation by
/// direct DSP on the sample buffer, and write the degraded WAV.
///
/// Deliberately NO AVAudioEngine. Offline effect-graph rendering through the
/// engine's mixer is fragile (format negotiation, error -10868). The
/// degradations that matter for a robustness illustration are simple math on the
/// samples: additive noise (busy room), a one-pole low-pass (muffled / covered
/// mic), and gain. This keeps the tool dependency-light, deterministic, and
/// verifiable.
///
/// HONESTY: synthetic degradation of synthetic speech. It reproduces the
/// *categories* of degradation, not a physical acoustic path, mic array, or real
/// noise field. Physical device-lab testing is a separate, higher-fidelity tier.
enum AudioDegrader {

    struct Profile {
        var noiseSNRdB: Double? = nil    // additive white noise at target SNR
        var lowpassHz: Double? = nil     // muffle: one-pole low-pass cutoff
        var gain: Float? = nil           // linear gain (e.g. 0.5 quieter, far mic)

        static let cleanCopy = Profile()
        static let noisy   = Profile(noiseSNRdB: 8.0)
        static let muffled = Profile(lowpassHz: 1200)
        static let farMic  = Profile(noiseSNRdB: 14.0, lowpassHz: 2500, gain: 0.6)
        static let badMic  = Profile(noiseSNRdB: 10.0, lowpassHz: 1800)
    }

    static func process(input inURL: URL, output outURL: URL, profile: Profile) throws {
        guard FileManager.default.fileExists(atPath: inURL.path) else {
            throw FixtureError.fileNotFound(inURL.path)
        }
        let inFile = try AVAudioFile(forReading: inURL)
        let format = inFile.processingFormat

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(inFile.length)) else {
            throw FixtureError.renderSetupFailed("could not allocate buffer")
        }
        try inFile.read(into: buffer)

        guard let channels = buffer.floatChannelData else {
            throw FixtureError.renderSetupFailed("buffer is not float PCM")
        }
        let frames = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        let sampleRate = format.sampleRate

        for ch in 0..<chCount {
            let samples = channels[ch]

            if let cutoff = profile.lowpassHz {
                onePoleLowpass(samples, frames: frames, cutoffHz: cutoff, sampleRate: sampleRate)
            }
            if let snr = profile.noiseSNRdB {
                addWhiteNoise(samples, frames: frames, targetSNRdB: snr)
            }
            if let g = profile.gain {
                for i in 0..<frames { samples[i] *= g }
            }
            clampInPlace(samples, frames: frames)
        }

        let outFile = try AVAudioFile(forWriting: outURL,
                                      settings: format.settings,
                                      commonFormat: .pcmFormatFloat32,
                                      interleaved: false)
        try outFile.write(from: buffer)
    }

    /// One-pole IIR low-pass. y[n] = y[n-1] + a*(x[n]-y[n-1]),
    /// a = dt / (rc + dt), rc = 1/(2*pi*fc). Muffles by attenuating highs.
    private static func onePoleLowpass(_ s: UnsafeMutablePointer<Float>,
                                       frames: Int, cutoffHz: Double, sampleRate: Double) {
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * Double.pi * cutoffHz)
        let a = Float(dt / (rc + dt))
        var prev: Float = frames > 0 ? s[0] : 0
        for i in 0..<frames {
            prev = prev + a * (s[i] - prev)
            s[i] = prev
        }
    }

    /// Add white noise scaled so its RMS hits the target SNR vs the signal RMS.
    /// For uniform[-1,1]*k, RMS = k/sqrt(3), so scale = noiseRMS*sqrt(3).
    private static func addWhiteNoise(_ s: UnsafeMutablePointer<Float>,
                                      frames: Int, targetSNRdB: Double) {
        guard frames > 0 else { return }
        var sumSq = 0.0
        for i in 0..<frames { sumSq += Double(s[i] * s[i]) }
        let signalRMS = (sumSq / Double(frames)).squareRoot()
        guard signalRMS > 0 else { return }
        let noiseRMS = signalRMS / pow(10.0, targetSNRdB / 20.0)
        let scale = Float(noiseRMS * 1.7320508)   // sqrt(3)
        for i in 0..<frames {
            s[i] += Float(Double.random(in: -1...1)) * scale
        }
    }

    private static func clampInPlace(_ s: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames {
            if s[i] > 1 { s[i] = 1 } else if s[i] < -1 { s[i] = -1 }
        }
    }
}
