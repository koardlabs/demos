import Foundation

struct AppConfiguration {
    let apiKey: String
    /// One of `UAT`, `PRODUCTION`.
    let environment: String
}

/// Reads the bundled `Config.plist` and picks the section for the env
/// **baked into this build at compile time**.
///
/// **How the env is selected.** Each Xcode scheme uses its own build
/// configuration (UAT / Production) and each sets
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` to a `KOARD_ENV_<NAME>` flag. The
/// `#if` chain below resolves at compile time, so the env literally lives in
/// the compiled bytes — no Info.plist lookup, no environment variables, no
/// UserDefaults. The env in the binary is the env you built against. Works on
/// TestFlight day-one.
///
/// **Config.plist layout** — one plist, two sub-dicts:
///
/// ```xml
/// <plist><dict>
///     <key>UAT</key>        <dict>apiKey</dict>
///     <key>PRODUCTION</key> <dict>apiKey</dict>
/// </dict></plist>
/// ```
///
/// Each section carries only `apiKey`. Merchant code + PIN are NOT stored
/// here — users log in via `LoginView`.
class ConfigurationManager {
    static func loadConfiguration() -> AppConfiguration? {
        let envKey = resolveEnvKey()

        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let root = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("[ConfigurationManager] ERROR: Config.plist not found in bundle. Did you copy Config.plist.template to Config.plist and add it to the target?")
            return nil
        }

        guard let section = root[envKey] as? [String: Any] else {
            print("[ConfigurationManager] ERROR: Config.plist has no `\(envKey)` section. Available keys: \(Array(root.keys).sorted())")
            return nil
        }

        guard let apiKey = section["apiKey"] as? String, !apiKey.hasPrefix("YOUR_") else {
            print("[ConfigurationManager] ERROR: Missing or unfilled `apiKey` in Config.plist[\(envKey)]")
            return nil
        }

        print("[ConfigurationManager] Loaded \(envKey) section")

        return AppConfiguration(
            apiKey: apiKey,
            environment: envKey
        )
    }

    /// Resolves the env name from a Swift compile-time flag set by the active
    /// build configuration. The `#if` chain is evaluated by the compiler —
    /// exactly one branch survives in the binary.
    ///
    /// If you ever see the "no env flag" fallback fire, that means someone
    /// built against the stock `Debug`/`Release` configs. Pick the
    /// "Koard Demo (UAT)" or "Koard Demo (Production)" scheme instead.
    static func resolveEnvKey() -> String {
        #if KOARD_ENV_UAT
        return "UAT"
        #elseif KOARD_ENV_PRODUCTION
        return "PRODUCTION"
        #else
        #warning("No KOARD_ENV_* compilation flag set. Falling back to UAT. Pick the 'Koard Demo (UAT)' or 'Koard Demo (Production)' scheme.")
        print("[ConfigurationManager] WARNING: No KOARD_ENV_* compile flag was set on this build. Falling back to UAT. Pick a UAT/Production scheme.")
        return "UAT"
        #endif
    }
}
