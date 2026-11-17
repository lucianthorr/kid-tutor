import SwiftUI

/// Voice picker with previews, speaking speed, and Personal Voice access.
struct VoiceSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var voices: [VoiceOption] = []
    @State private var personalVoiceStatus: String?

    var body: some View {
        @Bindable var model = model
        Section {
            LabeledContent("Speaking now", value: model.speaker.voiceDescription)
            LabeledContent("Speed") {
                HStack {
                    Image(systemName: "tortoise")
                    Slider(value: $model.settings.speechRate, in: 0.3...0.6)
                        .frame(maxWidth: 280)
                    Image(systemName: "hare")
                }
            }

            voiceRow(id: nil, title: "Automatic", detail: "best installed voice")
            ForEach(voices) { voice in
                voiceRow(id: voice.id, title: voice.name, detail: "\(voice.quality.label) · \(voice.language)", preview: voice)
            }

            Button("Use my Personal Voice…", systemImage: "person.wave.2") {
                Task {
                    let status = await Speaker.requestPersonalVoiceAccess()
                    personalVoiceStatus = status
                    Log.info(.speech, "personal voice access: \(status)")
                    voices = await Speaker.availableVoices()
                }
            }
            if let personalVoiceStatus {
                Text("Personal Voice: \(personalVoiceStatus)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("""
            For a natural voice, download one in Settings › Accessibility › Spoken Content › Voices › English: \
            the Premium voices (such as Ava, Zoe or Evan) sound the most human. Or record your own voice in \
            Settings › Accessibility › Personal Voice and allow it here. Downloaded voices work offline. \
            Return to this screen to see newly downloaded voices.
            """)
        }
        .task { voices = await Speaker.availableVoices() }
    }

    private func voiceRow(id: String?, title: String, detail: String, preview: VoiceOption? = nil) -> some View {
        HStack {
            Button {
                model.settings.voiceIdentifier = id
            } label: {
                HStack {
                    Image(systemName: model.settings.voiceIdentifier == id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(title)
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            if let preview {
                Button("Play", systemImage: "play.circle") { model.speaker.preview(preview) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// Lets a grown-up allow the microphone and speech recognition ahead of time, so the child doesn't
/// meet the permission prompts in Reading.
struct ReadingSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let listener = model.listener
        Section {
            LabeledContent("Status", value: status(listener.availability))
            if listener.availability == .needsPermission {
                Button("Allow microphone and speech recognition", systemImage: "mic") {
                    Task { await listener.requestPermission() }
                }
            }
        } header: {
            Text("Reading")
        } footer: {
            Text("Reading listens while your child reads aloud. Speech is recognized on this iPad only (the app requires on-device recognition), even though Apple's permission prompt mentions sending speech to Apple.")
        }
        .onAppear { listener.checkStatus() }
    }

    private func status(_ availability: SpeechListener.Availability) -> String {
        switch availability {
        case .unknown: "Checking…"
        case .needsPermission: "Not set up yet"
        case .ready: "Ready (on-device)"
        case .unavailable(let reason): reason
        }
    }
}
