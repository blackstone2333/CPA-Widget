import Foundation
import WidgetKit

struct CPAWidgetTimelineProvider: TimelineProvider {
    private let cacheStore = CacheStore()
    private let settingsStore = AppSettingsStore()

    func placeholder(in context: Context) -> CPAWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CPAWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CPAWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let delay = entry.accounts.isEmpty ? 60 : settingsStore.refreshInterval
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(delay))))
    }

    private func makeEntry() -> CPAWidgetEntry {
        let enabledProviders = settingsStore.enabledProviders
        let accounts = cacheStore.loadAccountQuota()
            .filter { enabledProviders.contains($0.provider) }
            .sorted(by: accountOrder)
        let provider: ProviderType? = accounts.contains(where: { $0.provider == .codex })
            ? .codex
            : accounts.first?.provider

        return CPAWidgetEntry(
            date: Date(),
            accounts: accounts,
            status: cacheStore.loadStatus(),
            language: settingsStore.language,
            mode: .singleProvider,
            selectedProvider: provider,
            selectedAccountIDs: [],
            windowChoice: .weekly,
            warnsAboutInsecureHTTP: settingsStore.warnsAboutInsecureHTTP
        )
    }
}

struct CPAAccountWidgetTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = AccountQuotaWidgetIntent
    typealias Entry = CPAWidgetEntry

    private let cacheStore = CacheStore()
    private let settingsStore = AppSettingsStore()

    func placeholder(in context: Context) -> CPAWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: AccountQuotaWidgetIntent, in context: Context) async -> CPAWidgetEntry {
        context.isPreview ? .placeholder : makeEntry(configuration)
    }

    func timeline(for configuration: AccountQuotaWidgetIntent, in context: Context) async -> Timeline<CPAWidgetEntry> {
        let entry = makeEntry(configuration)
        let delay = entry.accounts.isEmpty ? 60 : settingsStore.refreshInterval
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(delay)))
    }

    private func makeEntry(_ configuration: AccountQuotaWidgetIntent) -> CPAWidgetEntry {
        let allAccounts = liveAccounts()
        let requestedIDs = configuration.accounts?.map(\.id) ?? []
        let selectedAccounts = requestedIDs.isEmpty
            ? allAccounts
            : allAccounts.filter { requestedIDs.contains($0.id) }
        let requestedProvider = configuration.provider.provider
        let availableProvider = requestedProvider.flatMap { provider in
            allAccounts.contains(where: { $0.provider == provider }) ? provider : nil
        }

        return CPAWidgetEntry(
            date: Date(),
            accounts: selectedAccounts,
            status: cacheStore.loadStatus(),
            language: settingsStore.language,
            mode: configuration.mode,
            selectedProvider: availableProvider
                ?? (allAccounts.contains(where: { $0.provider == .codex }) ? .codex : allAccounts.first?.provider),
            selectedAccountIDs: requestedIDs,
            windowChoice: .automatic,
            warnsAboutInsecureHTTP: settingsStore.warnsAboutInsecureHTTP
        )
    }

    private func liveAccounts() -> [AccountQuotaInfo] {
        let enabledProviders = settingsStore.enabledProviders
        return cacheStore.loadAccountQuota()
            .filter { enabledProviders.contains($0.provider) }
            .sorted(by: accountOrder)
    }
}

struct CPATimelineWidgetTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = QuotaTimelineWidgetIntent
    typealias Entry = CPAWidgetEntry

    private let cacheStore = CacheStore()
    private let settingsStore = AppSettingsStore()

    func placeholder(in context: Context) -> CPAWidgetEntry {
        let entry = CPAWidgetEntry.placeholder
        return CPAWidgetEntry(
            date: entry.date,
            accounts: entry.accounts,
            status: entry.status,
            language: entry.language,
            mode: .accountOverview,
            selectedProvider: nil,
            selectedAccountIDs: [],
            windowChoice: .automatic,
            warnsAboutInsecureHTTP: false
        )
    }

    func snapshot(for configuration: QuotaTimelineWidgetIntent, in context: Context) async -> CPAWidgetEntry {
        context.isPreview ? placeholder(in: context) : makeEntry(configuration)
    }

    func timeline(for configuration: QuotaTimelineWidgetIntent, in context: Context) async -> Timeline<CPAWidgetEntry> {
        let entry = makeEntry(configuration)
        let delay = entry.accounts.isEmpty ? 60 : settingsStore.refreshInterval
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(delay)))
    }

    private func makeEntry(_ configuration: QuotaTimelineWidgetIntent) -> CPAWidgetEntry {
        let enabledProviders = settingsStore.enabledProviders
        var accounts = cacheStore.loadAccountQuota()
            .filter { enabledProviders.contains($0.provider) }
        if let provider = configuration.provider.provider {
            accounts = accounts.filter { $0.provider == provider }
        }

        let requestedIDs = configuration.accounts?.map(\.id) ?? []
        if !requestedIDs.isEmpty {
            accounts = accounts.filter { requestedIDs.contains($0.id) }
        }
        accounts.sort(by: accountOrder)

        return CPAWidgetEntry(
            date: Date(),
            accounts: accounts,
            status: cacheStore.loadStatus(),
            language: settingsStore.language,
            mode: .accountOverview,
            selectedProvider: configuration.provider.provider,
            selectedAccountIDs: requestedIDs,
            windowChoice: configuration.window,
            warnsAboutInsecureHTTP: settingsStore.warnsAboutInsecureHTTP
        )
    }
}

private func accountOrder(_ lhs: AccountQuotaInfo, _ rhs: AccountQuotaInfo) -> Bool {
    if lhs.mostConstrainedPercentage != rhs.mostConstrainedPercentage {
        return lhs.mostConstrainedPercentage < rhs.mostConstrainedPercentage
    }
    if lhs.provider.sortOrder != rhs.provider.sortOrder {
        return lhs.provider.sortOrder < rhs.provider.sortOrder
    }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}
