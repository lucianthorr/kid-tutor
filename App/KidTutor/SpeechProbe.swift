import AVFoundation
import Speech

/// Diagnostic: launch with `-speechProbe <file in Documents>` to check the iOS 26 speech model
/// (DictationTranscriber), install it if needed, and transcribe a recorded file. Everything goes to the log.
@available(iOS 26, *)
enum SpeechProbe {
    static func run(fileName: String) async {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent(fileName)
        let installed = await DictationTranscriber.installedLocales.map(\.identifier)
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            Log.error(.reading, "probe: en-US not supported by DictationTranscriber (installed: \(installed))")
            return
        }
        Log.info(.reading, "probe: locale \(locale.identifier), installed locales \(installed)")

        do {
            let reserved = try await AssetInventory.reserve(locale: locale)
            Log.info(.reading, "probe: reserve \(locale.identifier) -> \(reserved); reserved now \(await AssetInventory.reservedLocales.map(\.identifier))")
        } catch {
            Log.error(.reading, "probe: reserve failed: \(error)")
        }
        let general = SpeechTranscriber(locale: locale, preset: .transcription)
        Log.info(.reading, "probe: SpeechTranscriber status \(await AssetInventory.status(forModules: [general])) formats \(await general.availableCompatibleAudioFormats.count) installed \(await SpeechTranscriber.installedLocales.map(\.identifier))")
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [general]) {
                Log.info(.reading, "probe: downloading SpeechTranscriber model")
                try await request.downloadAndInstall()
                Log.info(.reading, "probe: SpeechTranscriber status after \(await AssetInventory.status(forModules: [general])) formats \(await general.availableCompatibleAudioFormats.count)")
            }
        } catch {
            Log.error(.reading, "probe: SpeechTranscriber install failed: \(error)")
        }

        let transcriber = DictationTranscriber(locale: locale, preset: .shortDictation)
        Log.info(.reading, "probe: DictationTranscriber formats \(await transcriber.availableCompatibleAudioFormats.count)")
        var status = await AssetInventory.status(forModules: [transcriber])
        Log.info(.reading, "probe: model status \(status)")
        if status != .installed {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    Log.info(.reading, "probe: downloading speech model")
                    try await request.downloadAndInstall()
                } else {
                    Log.info(.reading, "probe: no installation request needed")
                }
            } catch {
                Log.error(.reading, "probe: model install failed: \(error)")
            }
            status = await AssetInventory.status(forModules: [transcriber])
            Log.info(.reading, "probe: model status after install \(status)")
        }

        do {
            let audio = try AVAudioFile(forReading: file)
            Log.info(.reading, "probe: transcribing \(fileName) (\(audio.length) frames at \(audio.processingFormat.sampleRate) Hz)")
            let collector = Task {
                var texts: [String] = []
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    Log.info(.reading, "probe: result final=\(result.isFinal) \"\(text)\"")
                    texts.append(text)
                }
                return texts
            }
            let analyzer = try await SpeechAnalyzer(inputAudioFile: audio, modules: [transcriber], finishAfterFile: true)
            _ = analyzer
            let texts = try await collector.value
            Log.info(.reading, "probe: done, heard \(texts)")
        } catch {
            Log.error(.reading, "probe: transcription failed: \(error)")
        }
        Log.file.flush()
    }
}
