import Foundation

struct KimiProvider: QuotaProvider {
    let provider: ProviderType = .kimi
    let client: any QuotaFetchingClient

    var name: String { provider.displayName }

    func fetchAccountQuotas() async throws -> [AccountQuotaInfo] {
        try await client.fetchAccountQuotas(for: provider)
    }
}
