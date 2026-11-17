/// Which system voices sound like a person.
public enum VoiceCatalog {
    /// Allow-list rather than block-list: Apple's novelty flag catches joke voices (Bubbles, Zarvox, …)
    /// but not the robotic Eloquence voices (`com.apple.eloquence.*`: Eddy, Grandma, …) or the old
    /// MacinTalk voices (`com.apple.speech.synthesis.voice.*`: Fred, Junior, …). Natural voices live
    /// under `com.apple.voice.` (compact, enhanced, premium) or the older `com.apple.ttsbundle.`;
    /// a parent's Personal Voice is always allowed.
    public static func isHumanVoice(identifier: String, isNovelty: Bool, isPersonal: Bool) -> Bool {
        if isPersonal { return true }
        if isNovelty { return false }
        return identifier.hasPrefix("com.apple.voice.") || identifier.hasPrefix("com.apple.ttsbundle.")
    }
}
