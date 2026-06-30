import Foundation

/// Errors surfaced by the recognition layer.
public enum RecognitionError: Error, Equatable {
    case unauthorized
    case recognizerUnavailable
    case onDeviceUnsupported
    case noResult
    case fileNotFound(String)
}

#if canImport(Speech)
import Speech

/// Wraps SFSpeechRecognizer for file-based, on-device recognition.
///
/// Design choices that make this test-friendly:
///  - File input (SFSpeechURLRecognitionRequest), not live mic, so the suite
///    is deterministic and runs headless on CI.
///  - requiresOnDeviceRecognition = true: no network, results are stable and
///    reflect the on-device model the way a reliability test should.
public final class OnDeviceSpeechRecognizer {

    private let recognizer: SFSpeechRecognizer?

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Request authorization. Call once before recognizing.
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    /// Recognize a bundled audio file fully on-device, returning the transcript.
    public func transcribe(url: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw RecognitionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw RecognitionError.onDeviceUnsupported
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecognitionError.fileNotFound(url.lastPathComponent)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
#endif
