#if os(macOS)
import Foundation

enum AppPreferenceKey {
    static let alertChimeEnabled = "alertChimeEnabled"
    static let jumpSoundEnabled = "jumpSoundEnabled"
    static let hotKeyConfiguration = "hotKeyConfiguration"
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
}
#endif
