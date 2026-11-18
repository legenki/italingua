import AVFoundation
import Observation

/// Offline Italian text-to-speech with the system voices. The best installed
/// it-IT voice is used (premium > enhanced > default); better voices can be
/// downloaded once in Settings › Accessibility › Spoken Content › Voices.
@Observable
final class Speech {
    static let shared = Speech()

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = FinishDelegate()
    private(set) var speakingText: String?

    /// The Italian voice, found in the background: listing the system voices
    /// can block for a long time (it hung the iOS Simulator on launch), so it
    /// never runs on the main thread.
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    /// False only once the lookup finished and found no Italian voice.
    private(set) var hasItalianVoice = true

    init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] in
            Task { @MainActor in self?.speakingText = nil }
        }
        Task.detached(priority: .utility) {
            let found = Self.findVoice()
            await MainActor.run {
                self.voice = found?.voice
                self.hasItalianVoice = found != nil
            }
        }
    }

    private struct FoundVoice: @unchecked Sendable { let voice: AVSpeechSynthesisVoice }

    private nonisolated static func findVoice() -> FoundVoice? {
        let italian = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("it") }
        // Best quality first; among equals prefer the natural adult voices.
        let preferred = ["Federica", "Luca", "Alice", "Paola"]
        func rank(_ v: AVSpeechSynthesisVoice) -> (Int, Int) {
            (v.quality.rawValue, -(preferred.firstIndex { v.name.hasPrefix($0) } ?? preferred.count))
        }
        return (italian.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "it-IT")).map(FoundVoice.init)
    }

    func isSpeaking(_ text: String) -> Bool { speakingText == text }

    /// Speaks Italian text; tapping the same text again stops it.
    func speak(_ text: String, slow: Bool = false) {
        if synthesizer.isSpeaking {
            let same = speakingText == text
            synthesizer.stopSpeaking(at: .immediate)
            speakingText = nil
            if same { return }
        }
        let utterance = AVSpeechUtterance(string: Self.spokenForm(text))
        // Until the lookup finishes, the system picks its default Italian voice.
        utterance.voice = voice
        if utterance.voice == nil { utterance.voice = AVSpeechSynthesisVoice(language: "it-IT") }
        utterance.rate = slow ? 0.38 : 0.46
        utterance.postUtteranceDelay = 0.1
        speakingText = text
        synthesizer.speak(utterance)
        StudySession.shared.noteSpoken(text)
    }

    /// Removes markup the synthesizer would read aloud ("parl|o", "**", "___").
    nonisolated static func spokenForm(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "___", with: "…")
            .replacingOccurrences(of: "→", with: ",")
    }
}

/// Reports when speech ends, so the stop button turns back into play.
private nonisolated final class FinishDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (@Sendable () -> Void)?

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onFinish?() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onFinish?() }
}
