import AVFoundation
@MainActor
final class Speech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speech()
    private let synthesizer = AVSpeechSynthesizer()
    private override init() { super.init(); synthesizer.delegate = self }

    static func voiceLanguage(_ preferred: String) -> String {
        let p = preferred.lowercased()
        if p.hasPrefix("zh-hant-hk") || p.hasPrefix("zh-hk") { return "zh-HK" }
        if p.hasPrefix("zh-hant") || p.hasPrefix("zh-tw") { return "zh-TW" }
        if p.hasPrefix("zh") { return "zh-CN" }
        if p.hasPrefix("en") { return preferred.count >= 5 ? String(preferred.prefix(5)) : "en-US" }
        return AVSpeechSynthesisVoice.currentLanguageCode()
    }

    func read(_ r: BPReading, guideline: BPGuideline) {
        let text = L.timestamp(r.date) + " · " + L.timeOfDay(r.date) + " · " + L.f("血压 %@ 比 %@，脉搏 %@，属于 %@。", String(r.systolic), String(r.diastolic), r.pulse.map(String.init) ?? "—", L.grade(guideline.classify(r.systolic, r.diastolic).grade, guideline: guideline))
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        let lang = Speech.voiceLanguage(Locale.preferredLanguages.first ?? "en-US")
        utterance.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = 0.42
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
