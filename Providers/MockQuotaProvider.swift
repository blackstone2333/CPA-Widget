import Foundation

/// Phase 1 source used to validate the complete App → cache → Widget pipeline.
struct MockQuotaProvider: QuotaProvider {
    let provider: ProviderType

    var name: String { provider.displayName }

    func fetchAccountQuotas() async throws -> [AccountQuotaInfo] {
        let sample: (percentage: Int, resetInterval: TimeInterval)

        switch provider {
        case .claude: sample = (82, 3 * 3_600 + 20 * 60)
        case .codex: sample = (61, 8 * 3_600)
        case .gemini: sample = (91, 12 * 3_600)
        case .kimi: sample = (74, 7 * 24 * 3_600)
        }

        return [AccountQuotaInfo(
            id: "mock-\(provider.rawValue)",
            provider: provider,
            displayName: "\(provider.displayName) Demo Account",
            planName: provider == .kimi ? nil : "Pro",
            windows: [QuotaWindowInfo(
                id: "mock-\(provider.rawValue)-weekly",
                label: "Weekly Limit",
                remainingPercentage: sample.percentage,
                resetTime: Date().addingTimeInterval(sample.resetInterval),
                durationSeconds: 7 * 24 * 3_600
            )],
            updatedAt: Date()
        )]
    }
}
