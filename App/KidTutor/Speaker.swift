import AVFoundation
import Observation
import KidTutorKit

/// One installed voice, as shown in the voice picker.
struct VoiceOption: Identifiable, Hashable, Sendable {
    enum Quality: Int, Comparable, Sendable {
        case standard, enhanced, premium, personal
        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .standard: "Standard"
            case .enhanced: "Enhanced"
            case .premium: "Premium"
            case .personal: "Personal Voice"
            }
        }
    }

    let id: String
    let name: String
    let language: String
    let quality: Quality
}

/// Reads prompts aloud. Uses the voice chosen in Settings, or else the best English voice installed.
/// Premium and Enhanced voices are free downloads in Settings › Accessibility › Spoken Content › Voices
/// and then work offline; a Personal Voice is the parent's own recorded voice.
@MainActor
@Observable
final class Speaker {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let parts = SpeechParts()
    /// Nil means the system default voice, used until the chosen voice has loaded.
    private(set) var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var rate = AVSpeechUtteranceDefaultSpeechRate * 0.9

    init() {
        synthesizer.delegate = parts
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch {
            Log.error(.speech, "audio session: \(error)")
        }
    }

    /// Picks the voice and speed. Voice lookup runs off the main thread: listing voices waits on work
    /// that needs the main thread, so doing it there hangs the app.
    func configure(voiceIdentifier: String?, rate: Double) {
        self.rate = Float(rate)
        Task {
            voice = await Self.loadVoice(identifier: voiceIdentifier)
            Log.info(.speech, "voice: \(voiceDescription) rate=\(String(format: "%.2f", rate))")
        }
    }

    func say(_ text: String) {
        speak(text, with: voice)
    }

    /// Says `texts` one after another, reporting each as it starts and finishes (used to fade the
    /// "who am I?" tiles clue by clue). Anything said afterwards cuts it off, and no more reports come.
    func say(parts texts: [String], onStart: @escaping @MainActor (Int) -> Void = { _ in }, onFinish: @escaping @MainActor (Int) -> Void = { _ in }) {
        Log.debug(.speech, "say parts \(texts)")
        synthesizer.stopSpeaking(at: .immediate)
        parts.reset(onStart: onStart, onFinish: onFinish)
        for text in texts {
            let utterance = utterance(text, with: voice)
            parts.track(utterance)
            synthesizer.speak(utterance)
        }
    }

    /// Stops talking, e.g. before listening so the app doesn't hear itself.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Says a sample sentence in a voice without selecting it.
    func preview(_ option: VoiceOption) {
        Task {
            let voice = await Self.loadVoice(identifier: option.id)
            speak("Hi! Let's spell the word friend.", with: voice)
        }
    }

    private func speak(_ text: String, with voice: AVSpeechSynthesisVoice?) {
        Log.debug(.speech, "say \"\(text)\"")
        synthesizer.stopSpeaking(at: .immediate)
        parts.reset()
        synthesizer.speak(utterance(text, with: voice))
    }

    private func utterance(_ text: String, with voice: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        return utterance
    }

    var voiceDescription: String {
        guard let voice else { return "System default" }
        return "\(voice.name) (\(Self.quality(of: voice).label), \(voice.language))"
    }

    // MARK: - Voices (off the main thread)

    /// English voices, best quality first, US English before other English.
    nonisolated static func availableVoices() async -> [VoiceOption] {
        humanEnglishVoices()
            .map { VoiceOption(id: $0.identifier, name: $0.name, language: $0.language, quality: quality(of: $0)) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality > b.quality }
                if (a.language == "en-US") != (b.language == "en-US") { return a.language == "en-US" }
                return a.name < b.name
            }
    }

    /// Asks permission to use the parent's Personal Voice (made in Settings › Accessibility › Personal Voice).
    nonisolated static func requestPersonalVoiceAccess() async -> String {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                let text: String
                switch status {
                case .authorized: text = "allowed"
                case .denied: text = "not allowed (change it in Settings › Kid Tutor)"
                case .unsupported: text = "not supported on this device"
                case .notDetermined: text = "not decided"
                @unknown default: text = "unknown"
                }
                continuation.resume(returning: text)
            }
        }
    }

    nonisolated private static func loadVoice(identifier: String?) async -> AVSpeechSynthesisVoice? {
        let english = humanEnglishVoices()
        if let identifier, let chosen = english.first(where: { $0.identifier == identifier }) {
            return chosen
        }
        let best = english.max { rank($0) < rank($1) }
        return best ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// English voices that sound like a person: no novelty, Eloquence or old MacinTalk voices.
    nonisolated private static func humanEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && VoiceCatalog.isHumanVoice(
                identifier: $0.identifier,
                isNovelty: $0.voiceTraits.contains(.isNoveltyVoice),
                isPersonal: $0.voiceTraits.contains(.isPersonalVoice)
            )
        }
    }

    nonisolated private static func quality(of voice: AVSpeechSynthesisVoice) -> VoiceOption.Quality {
        if voice.voiceTraits.contains(.isPersonalVoice) { return .personal }
        switch voice.quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .standard
        }
    }

    /// Prefers Premium over Enhanced over Standard, then US English. A Personal Voice is only used
    /// when picked in Settings.
    nonisolated private static func rank(_ voice: AVSpeechSynthesisVoice) -> (Int, Int) {
        let q = quality(of: voice)
        return (q == .personal ? -1 : q.rawValue, voice.language == "en-US" ? 1 : 0)
    }
}

/// Tells `Speaker.say(parts:)` callers when each part starts and finishes.
private final class SpeechParts: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    // Touched only on the main thread.
    private var utterances: [AVSpeechUtterance] = []
    private var onStart: (@MainActor (Int) -> Void)?
    private var onFinish: (@MainActor (Int) -> Void)?

    func reset(onStart: (@MainActor (Int) -> Void)? = nil, onFinish: (@MainActor (Int) -> Void)? = nil) {
        utterances = []
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func track(_ utterance: AVSpeechUtterance) {
        utterances.append(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        report(utterance) { parts, i in parts.onStart?(i) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        report(utterance) { parts, i in parts.onFinish?(i) }
    }

    private func report(_ utterance: AVSpeechUtterance, _ call: @escaping @MainActor (SpeechParts, Int) -> Void) {
        Task { @MainActor in
            if let i = self.utterances.firstIndex(where: { $0 === utterance }) { call(self, i) }
        }
    }
}
