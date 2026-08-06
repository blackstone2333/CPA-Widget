import Foundation

/// Provider-neutral payload returned by a future CLIProxyAPI integration.
struct ProviderQuotaPayload: Sendable {
    let remainingPercentage: Int
    let resetTime: Date?
}
