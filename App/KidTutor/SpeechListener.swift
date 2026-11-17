import AVFoundation
import KidTutorKit
import Observation
import Speech
import UIKit

/// Listens to the child read aloud and turns it into text, on the device only
/// (`requiresOnDeviceRecognition`): no audio or text leaves the iPad.
@MainActor
@Observable
final class SpeechListener {
    enum Availability: Equatable {
        case unknown
        /// Microphone or speech permission hasn't been asked yet; asked on the first mic tap.
        case needsPermission
        case ready
        case unavailable(String)
    }

    private(set) var availability = Availability.unknown
    private(set) var isListening = false
    /// Best transcription so far, for the "I heard …" line.
    private(set) var heard = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    /// Final alternatives, or nil when the recognizer itself failed (not "heard nothing").
    @ObservationIgnored private var onFinish: (([String]?) -> Void)?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var attemptStartedAt = Date.distantPast
    /// Counts recognition attempts, so results from a replaced one are ignored.
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var hints: [String] = []
    @ObservationIgnored private var onUpdate: (([String]) -> Bool)?
    /// Hands microphone audio to whichever recognition attempt is current.
    @ObservationIgnored private let feed = AudioFeed()
    @ObservationIgnored private var latest: [String] = []
    @ObservationIgnored private let meter = AudioMeter()
    @ObservationIgnored private var retries = ListeningRetries()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Listening waits as long as the child needs, so anything that takes the microphone away (a call,
    /// Siri, the iPad locking, a headset unplugged) must end it, or the mic would wait on silence forever.
    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                guard type == .began else { return }
                MainActor.assumeIsolated { self?.stopForInterruption("audio was interrupted") }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopForInterruption("the audio route changed") }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopForInterruption("the app left the screen") }
            },
        ]
    }

    /// Checks permissions and on-device recognition without asking for anything, so a child never
    /// meets a permission prompt just by opening Reading.
    func checkStatus() {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission
        if speech == .notDetermined || microphone == .undetermined {
            availability = .needsPermission
            Log.info(.reading, "speech availability: needs permission")
            return
        }
        update(speech: speech, microphone: microphone == .granted)
    }

    /// Asks for microphone and speech permission (the system asks only once) and checks again.
    func requestPermission() async {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        update(speech: speech, microphone: microphone)
    }

    private func update(speech: SFSpeechRecognizerAuthorizationStatus, microphone: Bool) {
        if speech != .authorized {
            availability = .unavailable("Speech recognition isn't allowed. Turn it on in Settings › Kid Tutor.")
        } else if !microphone {
            availability = .unavailable("The microphone isn't allowed. Turn it on in Settings › Kid Tutor.")
        } else if recognizer == nil || recognizer?.isAvailable == false {
            availability = .unavailable("English speech recognition isn't available on this iPad.")
        } else if recognizer?.supportsOnDeviceRecognition != true {
            availability = .unavailable("This iPad can't recognize speech without the internet, and Kid Tutor stays offline.")
        } else {
            availability = .ready
        }
        Log.info(.reading, "speech availability: \(availability) (speech=\(speech.rawValue) mic=\(microphone) onDevice=\(recognizer?.supportsOnDeviceRecognition ?? false))")
    }

    /// Starts listening. `onUpdate` sees every partial result and returns true to stop early (a match);
    /// `onFinish` gets the final alternatives after a pause or the time limit, or nil if the recognizer
    /// failed (for example, the on-device speech model isn't installed). Until the child says something it
    /// just keeps waiting: there is no time limit on starting to read.
    func start(
        hints: [String],
        onUpdate: @escaping ([String]) -> Bool,
        onFinish: @escaping ([String]?) -> Void
    ) {
        guard availability == .ready, recognizer != nil, !isListening else { return }
        heard = ""
        latest = []
        retries = ListeningRetries()
        startedAt = Date()
        self.hints = Array(NSOrderedSet(array: hints)) as? [String] ?? hints
        self.onUpdate = onUpdate
        self.onFinish = onFinish

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                Log.error(.reading, "microphone has no audio format: \(format) route=\(Self.routeDescription)")
                fail("The microphone isn't sending any sound. Check that no other app is using it, then try again.")
                return
            }
            meter.reset()
            feed.clear()
            let meter = meter
            let feed = feed
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                meter.add(buffer)
                feed.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isListening = true
            Log.info(.reading, "listening hints=\(hints) input=\(Int(format.sampleRate))Hz \(format.channelCount)ch route=\(Self.routeDescription)")
            beginRecognition()
        } catch {
            Log.error(.reading, "couldn't start listening: \(error)")
            stopAudio()
            onFinish(nil)
            self.onFinish = nil
        }
    }

    /// One recognition attempt on the running microphone. When it stops before any speech, the next
    /// attempt begins and the child never notices.
    private func beginRecognition() {
        guard let recognizer, let onUpdate else { return }
        attempt += 1
        let attempt = attempt
        attemptStartedAt = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        self.request = request
        feed.feed(request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let alternatives = result?.transcriptions.map(\.formattedString) ?? []
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                // Ignore a cancelled earlier attempt, or anything after listening stopped.
                guard let self, self.isListening, attempt == self.attempt else { return }
                if let error, alternatives.isEmpty {
                    let nsError = error as NSError
                    let elapsed = Date().timeIntervalSince(self.attemptStartedAt)
                    let meaning = SpeechErrorMeaning.of(domain: nsError.domain, code: nsError.code, heardAnything: !self.latest.isEmpty, secondsSinceStart: elapsed)
                    Log.warning(.reading, "recognition error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription) after \(String(format: "%.1f", elapsed))s of attempt \(attempt), heard so far: \(self.latest.isEmpty ? "nothing" : self.latest[0]) -> \(meaning) audio \(self.meter.summary)")
                    switch meaning {
                    case .cannotStart:
                        self.fail("Speech recognition couldn't start on this device (\(nsError.localizedDescription)). On an iPad, turning on Dictation in Settings › General › Keyboard downloads the speech model.")
                    case .heardNothing:
                        self.keepWaiting(failed: !SpeechErrorMeaning.isNoSpeech(domain: nsError.domain, code: nsError.code))
                    case .turnEnded:
                        self.finish()
                    }
                    return
                }
                guard !alternatives.isEmpty else {
                    if isFinal, self.latest.isEmpty { self.keepWaiting(failed: false) }
                    return
                }
                self.latest = alternatives
                self.heard = alternatives[0]
                if onUpdate(alternatives) || isFinal {
                    self.finish()
                    return
                }
                self.restartSilenceTimer()
                // Once the child is reading, stop 7 seconds later no matter what.
                if self.limitTask == nil {
                    self.limitTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(7))
                        guard !Task.isCancelled else { return }
                        self?.finish()
                    }
                }
            }
        }
    }

    /// The recognizer stopped before hearing anything: begin a new attempt on the same microphone,
    /// unless `ListeningRetries` says the recognizer is broken. `failed` is a real error, not "no speech".
    private func keepWaiting(failed: Bool) {
        // Retire this attempt first, so its cancellation report is ignored. Until the next attempt begins,
        // the feed keeps the audio, so a child who starts reading in the gap isn't cut off.
        attempt += 1
        feed.feed(nil)
        task?.cancel()
        request?.endAudio()
        guard engine.isRunning else {
            stopForInterruption("the microphone stopped")
            return
        }
        let ran = Date().timeIntervalSince(attemptStartedAt)
        switch retries.endedWithNothing(after: ran, failed: failed) {
        case .giveUp:
            fail("Speech recognition keeps stopping without hearing anything. A grown-up can check the reading instead.")
        case .listenAgain(let delay):
            Log.info(.reading, "nothing heard yet after \(String(format: "%.0f", Date().timeIntervalSince(startedAt)))s (attempt ran \(String(format: "%.1f", ran))s), still listening")
            let attempt = attempt
            Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard let self, self.isListening, attempt == self.attempt else { return }
                self.beginRecognition()
            }
        }
    }

    /// Something took the microphone away: stop without a result, so the mic button is ready to tap again.
    private func stopForInterruption(_ reason: String) {
        guard isListening else { return }
        Log.warning(.reading, "stopped listening: \(reason)")
        cancel()
    }

    /// Stops listening without reporting a result.
    func cancel() {
        onFinish = nil
        stopAudio()
    }

    // MARK: - Private

    private func restartSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// The recognizer is broken for this session: report it once and fall back to grown-up approval.
    private func fail(_ reason: String) {
        let callback = onFinish
        onFinish = nil
        stopAudio()
        availability = .unavailable(reason)
        Log.error(.reading, "speech unavailable: \(reason)")
        callback?(nil)
    }

    private func finish() {
        guard isListening else { return }
        let result = latest
        let callback = onFinish
        onFinish = nil
        stopAudio()
        Log.info(.reading, "heard: \(result.isEmpty ? "nothing" : result.map { "\"\($0)\"" }.joined(separator: " | ")) audio \(meter.summary)")
        callback?(result)
    }

    private static var routeDescription: String {
        AVAudioSession.sharedInstance().currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",").nilIfEmpty ?? "no input"
    }

    private func stopAudio() {
        silenceTask?.cancel()
        limitTask?.cancel()
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        feed.clear()
        request = nil
        task = nil
        limitTask = nil
        isListening = false
        // Back to speaking-only audio so prompts play normally.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
}

/// Measures what the microphone delivers while listening, so the log can tell "the child was quiet"
/// (normal room noise, around -50 dBFS) from "the microphone sent silence" (no buffers, or -inf).
/// Fed from the audio thread, read on the main thread.
final class AudioMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers = 0
    private var peak: Float = 0

    func reset() {
        lock.withLock {
            buffers = 0
            peak = 0
        }
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        var loudest: Float = 0
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(samples[i])) }
        }
        lock.withLock {
            buffers += 1
            peak = max(peak, loudest)
        }
    }

    /// "buffers=42 peak=-23 dBFS"
    var summary: String {
        lock.withLock {
            let db = peak > 0 ? String(format: "%.0f", 20 * log10(peak)) : "-inf"
            return "buffers=\(buffers) peak=\(db) dBFS"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Hands microphone audio to the current recognition request, from the audio thread. It also keeps the
/// last moment of audio, so a new attempt starts with whatever was said while the previous one was ending.
private final class AudioFeed: @unchecked Sendable {
    private static let keepSeconds = 1.5

    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recent: [AVAudioPCMBuffer] = []
    private var recentFrames: AVAudioFrameCount = 0

    /// Feeds `newRequest` from now on, starting with the recent audio; nil stops feeding but keeps recording.
    func feed(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            request = newRequest
            recent.forEach { newRequest?.append($0) }
        }
    }

    func clear() {
        lock.withLock {
            request = nil
            recent = []
            recentFrames = 0
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // The tap may reuse its buffer, so keep a copy.
        let copy = buffer.duplicate()
        lock.withLock {
            request?.append(buffer)
            guard let copy else { return }
            recent.append(copy)
            recentFrames += copy.frameLength
            let keep = AVAudioFrameCount(copy.format.sampleRate * Self.keepSeconds)
            while recentFrames > keep, let first = recent.first {
                recentFrames -= first.frameLength
                recent.removeFirst()
            }
        }
    }
}

private extension AVAudioPCMBuffer {
    func duplicate() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}
