#if os(macOS)
import Foundation
import OverwatchrCore

enum AppPreferenceKey {
    static let alertChimeEnabled = "alertChimeEnabled"
    static let jumpSoundEnabled = "jumpSoundEnabled"
    static let hotKeyConfiguration = "hotKeyConfiguration"
    static let voiceEnabled = "voiceEnabled"
    static let voiceHotKeyConfiguration = "voiceHotKeyConfiguration"
    static let azureSpeechRegion = "azureSpeechRegion"
    static let azureSpeechEndpoint = "azureSpeechEndpoint"
    static let azureSpeechLanguage = "azureSpeechLanguage"
    static let voiceSubmitMode = "voiceSubmitMode"
}

struct AppPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var alertChimeEnabled: Bool {
        get { defaults.bool(forKey: AppPreferenceKey.alertChimeEnabled) }
        set { defaults.set(newValue, forKey: AppPreferenceKey.alertChimeEnabled) }
    }

    var jumpSoundEnabled: Bool {
        get {
            if defaults.object(forKey: AppPreferenceKey.jumpSoundEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: AppPreferenceKey.jumpSoundEnabled)
        }
        set { defaults.set(newValue, forKey: AppPreferenceKey.jumpSoundEnabled) }
    }

    var hotKeyConfiguration: HotKeyConfiguration {
        get {
            guard let data = defaults.data(forKey: AppPreferenceKey.hotKeyConfiguration),
                  let configuration = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
                return .default
            }
            return configuration
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: AppPreferenceKey.hotKeyConfiguration)
            }
        }
    }

    var voiceHotKeyConfiguration: HotKeyConfiguration {
        get {
            guard let data = defaults.data(forKey: AppPreferenceKey.voiceHotKeyConfiguration),
                  let configuration = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
                return .defaultVoice
            }
            return configuration
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: AppPreferenceKey.voiceHotKeyConfiguration)
            }
        }
    }

    var voiceEnabled: Bool {
        get {
            if defaults.object(forKey: AppPreferenceKey.voiceEnabled) == nil {
                return false
            }
            return defaults.bool(forKey: AppPreferenceKey.voiceEnabled)
        }
        set { defaults.set(newValue, forKey: AppPreferenceKey.voiceEnabled) }
    }

    var azureSpeechRegion: String {
        get { defaults.string(forKey: AppPreferenceKey.azureSpeechRegion) ?? "" }
        set { defaults.set(newValue, forKey: AppPreferenceKey.azureSpeechRegion) }
    }

    var azureSpeechEndpoint: String {
        get { defaults.string(forKey: AppPreferenceKey.azureSpeechEndpoint) ?? "" }
        set { defaults.set(newValue, forKey: AppPreferenceKey.azureSpeechEndpoint) }
    }

    var azureSpeechLanguage: String {
        get { defaults.string(forKey: AppPreferenceKey.azureSpeechLanguage) ?? "en-US" }
        set { defaults.set(newValue, forKey: AppPreferenceKey.azureSpeechLanguage) }
    }

    var voiceSubmitMode: VoiceSubmitMode {
        get {
            guard let rawValue = defaults.string(forKey: AppPreferenceKey.voiceSubmitMode),
                  let mode = VoiceSubmitMode(rawValue: rawValue) else {
                return .stripAndSubmit
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: AppPreferenceKey.voiceSubmitMode)
        }
    }
}
#endif
