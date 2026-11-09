import Foundation
import Speech

/// Thread-safe "resume exactly once" guard for continuations fed by callbacks.
final class ResumeOnce {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Transcribes recorded or imported audio. Uses on-device recognition when the
/// language model is installed (no duration limit, works offline); otherwise Apple's
/// server recognition, which Apple limits to roughly one minute per request.
enum SpeechTranscriber {
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(url: URL, localeIdentifier: String) async throws -> String {
        guard await requestAuthorization() else { throw ImportError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw ImportError.speechUnavailable
        }
        // On-device first (no time limit, offline). The language model can be reported as
        // supported but not yet downloaded, so a failure falls back to Apple's servers.
        if recognizer.supportsOnDeviceRecognition {
            do {
                return try await recognize(url: url, recognizer: recognizer, onDevice: true)
            } catch ImportError.noSpeech {
                throw ImportError.noSpeech
            } catch {
                // fall through to server recognition
            }
        }
        guard recognizer.isAvailable else { throw ImportError.speechUnavailable }
        return try await recognize(url: url, recognizer: recognizer, onDevice: false)
    }

    private static func recognize(url: URL, recognizer: SFSpeechRecognizer, onDevice: Bool) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = onDevice

        let session = TranscriptionSession(recognizer: recognizer)
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce()
            session.task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if once.claim() {
                        session.finish()
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let result, result.isFinal, once.claim() {
                    session.finish()
                    let text = result.bestTranscription.formattedString
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(throwing: ImportError.noSpeech)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }
}

/// Keeps the recognizer and task alive for the duration of a transcription.
private final class TranscriptionSession {
    let recognizer: SFSpeechRecognizer
    var task: SFSpeechRecognitionTask?

    init(recognizer: SFSpeechRecognizer) { self.recognizer = recognizer }

    func finish() { task = nil }
}
