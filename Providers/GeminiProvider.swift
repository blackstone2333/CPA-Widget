import Foundation

struct GeminiProvider: QuotaProvider {
    let provider: ProviderType = .gemini
    let client: any QuotaFetchingClient

    var name: String { provider.displayName }

    func fetchAccountQuotas() async throws -> [AccountQuotaInfo] {
        try await client.fetchAccountQuotas(for: provider)
    }
}
