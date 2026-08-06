import Foundation

struct ClaudeProvider: QuotaProvider {
    let provider: ProviderType = .claude
    let client: any QuotaFetchingClient

    var name: String { provider.displayName }

    func fetchAccountQuotas() async throws -> [AccountQuotaInfo] {
        try await client.fetchAccountQuotas(for: provider)
    }
}
