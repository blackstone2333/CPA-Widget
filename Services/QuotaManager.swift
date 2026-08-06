import Foundation

final class QuotaManager: @unchecked Sendable {
    private let providers: [any QuotaProvider]
    private let cacheStore: CacheStore

    init(providers: [any QuotaProvider], cacheStore: CacheStore = CacheStore()) {
        self.providers = providers
        self.cacheStore = cacheStore
    }

    convenience init(
        enabledProviders: Set<ProviderType>,
        useMockData: Bool,
        endpoint: String,
        managementSecret: String,
        cacheStore: CacheStore = CacheStore()
    ) {
        let providers: [any QuotaProvider]

        if useMockData {
            providers = enabledProviders
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(MockQuotaProvider.init(provider:))
        } else {
            let url = URL(string: endpoint) ?? URL(fileURLWithPath: "/")
            let client = CLIProxyAPIQuotaClient(
                endpoint: url,
                managementSecret: managementSecret
            )
            providers = enabledProviders.compactMap { provider in
                switch provider {
                case .claude: ClaudeProvider(client: client)
                case .codex: CodexProvider(client: client)
                case .gemini: GeminiProvider(client: client)
                case .kimi: KimiProvider(client: client)
                }
            }
        }

        self.init(providers: providers, cacheStore: cacheStore)
    }

    func refresh() async throws {
        guard !providers.isEmpty else {
            try cacheStore.clearQuota()
            cacheStore.saveStatus(.noData)
            throw QuotaProviderError.noProvidersEnabled
        }

        let results = await withTaskGroup(of: FetchResult.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return .success(try await provider.fetchAccountQuotas())
                    } catch let error as QuotaProviderError {
                        return .failure(error)
                    } catch {
                        return .failure(.offline(error.localizedDescription))
                    }
                }
            }

            var collected: [FetchResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let accounts = results.flatMap(\.accounts)
            .sorted { lhs, rhs in
                if lhs.provider.sortOrder == rhs.provider.sortOrder {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                        == .orderedAscending
                }
                return lhs.provider.sortOrder < rhs.provider.sortOrder
            }
        let quota = ProviderType.allCases.compactMap { provider in
            accounts.aggregateQuota(for: provider)
        }
            .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
        let failures = results.compactMap(\.error)

        guard !quota.isEmpty else {
            let status: CacheStatus
            if failures.contains(where: { error in
                if case .authenticationFailed = error { return true }
                return false
            }) {
                status = .authenticationFailed
            } else if failures.contains(where: { error in
                switch error {
                case .invalidConfiguration, .adapterNotConfigured: return true
                default: return false
                }
            }) {
                status = .configurationRequired
            } else if failures.contains(where: { error in
                if case .offline = error { return true }
                return false
            }) {
                status = .offline
            } else {
                status = .noData
            }
            cacheStore.saveStatus(status)
            throw failures.first ?? QuotaProviderError.invalidResponse("Empty result")
        }

        try cacheStore.saveAccountQuota(accounts)
        try cacheStore.saveQuota(quota)
        cacheStore.saveStatus(failures.isEmpty ? .fresh : .partial)
    }

    func getCachedQuota() -> [QuotaInfo] {
        cacheStore.loadQuota()
    }

    func getCachedAccountQuota() -> [AccountQuotaInfo] {
        cacheStore.loadAccountQuota()
    }
}

private enum FetchResult: Sendable {
    case success([AccountQuotaInfo])
    case failure(QuotaProviderError)

    var accounts: [AccountQuotaInfo] {
        guard case .success(let accounts) = self else { return [] }
        return accounts
    }

    var error: QuotaProviderError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
