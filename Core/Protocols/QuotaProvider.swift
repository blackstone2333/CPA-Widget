import Foundation

protocol QuotaProvider: Sendable {
    var provider: ProviderType { get }
    var name: String { get }

    func fetchAccountQuotas() async throws -> [AccountQuotaInfo]
    func fetchQuota() async throws -> QuotaInfo
}

extension QuotaProvider {
    func fetchQuota() async throws -> QuotaInfo {
        let accounts = try await fetchAccountQuotas()
        guard let quota = accounts.aggregateQuota(for: provider) else {
            throw QuotaProviderError.invalidResponse(
                "No usable \(provider.displayName) quota windows"
            )
        }
        return quota
    }
}

enum QuotaProviderError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case adapterNotConfigured(ProviderType)
    case authenticationFailed
    case offline(String)
    case invalidResponse(String)
    case noProvidersEnabled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .adapterNotConfigured(let provider):
            "\(provider.displayName) quota adapter is not configured yet."
        case .authenticationFailed: "Authentication failed."
        case .offline(let message): "CLIProxyAPI is offline: \(message)"
        case .invalidResponse(let message): "Invalid quota response: \(message)"
        case .noProvidersEnabled: "No providers are enabled."
        }
    }
}
