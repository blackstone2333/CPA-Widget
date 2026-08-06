import Darwin
import Foundation

struct AppSettingsStore: Sendable {
    static let appGroupIdentifier = "group.com.cpawidget.shared"

    private struct StoredSettings: Codable, Sendable {
        var enabledProviders: [String]? = nil
        var refreshInterval: TimeInterval? = nil
        var useMockData: Bool? = nil
        var language: AppLanguage? = nil
        var warnsAboutInsecureHTTP: Bool? = nil
    }

    static func sharedContainerURL(fileManager: FileManager = .default) -> URL {
        if let passwordEntry = getpwuid(getuid()),
           let homePointer = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("CPAWidget", isDirectory: true)
                .appendingPathComponent("Shared", isDirectory: true)
        }

        return fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("CPAWidget", isDirectory: true)
            .appendingPathComponent("Shared", isDirectory: true)
    }

    private var settingsURL: URL {
        Self.sharedContainerURL().appendingPathComponent(
            "settings.json",
            isDirectory: false
        )
    }

    var enabledProviders: Set<ProviderType> {
        get {
            guard let rawValues = load().enabledProviders else {
                return [.codex]
            }
            return Set(rawValues.compactMap(ProviderType.init(rawValue:)))
        }
        nonmutating set {
            update { settings in
                settings.enabledProviders = newValue.map(\.rawValue).sorted()
            }
        }
    }

    var refreshInterval: TimeInterval {
        get {
            let stored = load().refreshInterval ?? 0
            return stored > 0 ? stored : 15 * 60
        }
        nonmutating set {
            update { settings in
                settings.refreshInterval = max(newValue, 5 * 60)
            }
        }
    }

    var useMockData: Bool {
        get {
            load().useMockData ?? false
        }
        nonmutating set {
            update { settings in
                settings.useMockData = newValue
            }
        }
    }

    var language: AppLanguage {
        get {
            load().language ?? .simplifiedChinese
        }
        nonmutating set {
            update { settings in
                settings.language = newValue
            }
        }
    }

    var warnsAboutInsecureHTTP: Bool {
        get {
            load().warnsAboutInsecureHTTP ?? false
        }
        nonmutating set {
            update { settings in
                settings.warnsAboutInsecureHTTP = newValue
            }
        }
    }

    private func load() -> StoredSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return StoredSettings()
        }
        return settings
    }

    private func update(_ change: (inout StoredSettings) -> Void) {
        var settings = load()
        change(&settings)

        do {
            let directory = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            // Settings retain safe defaults when shared storage is unavailable.
        }
    }
}
