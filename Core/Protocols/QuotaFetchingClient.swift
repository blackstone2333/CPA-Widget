import Foundation

/// Network boundary for CLIProxyAPI. Once its quota contract is known, only
/// this client needs to know paths, headers, or provider-specific JSON shapes.
protocol QuotaFetchingClient: Sendable {
    func fetchAccountQuotas(for provider: ProviderType) async throws -> [AccountQuotaInfo]
}
