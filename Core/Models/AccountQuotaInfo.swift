import Foundation

struct QuotaWindowInfo: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let remainingPercentage: Int
    let resetTime: Date?
    let durationSeconds: TimeInterval?

    var usedPercentage: Int {
        max(0, min(100, 100 - remainingPercentage))
    }
}

struct AccountQuotaInfo: Codable, Identifiable, Sendable {
    let id: String
    let provider: ProviderType
    let displayName: String
    let planName: String?
    let windows: [QuotaWindowInfo]
    let updatedAt: Date

    var mostConstrainedPercentage: Int {
        windows.map(\.remainingPercentage).min() ?? 0
    }

    var nextResetTime: Date? {
        windows.compactMap(\.resetTime)
            .filter { $0 > Date() }
            .min()
    }
}

extension Array where Element == AccountQuotaInfo {
    func aggregateQuota(for provider: ProviderType) -> QuotaInfo? {
        let matching = filter { $0.provider == provider && !$0.windows.isEmpty }
        guard !matching.isEmpty else { return nil }

        let average = Double(matching.map(\.mostConstrainedPercentage).reduce(0, +))
            / Double(matching.count)
        let nextReset = matching.flatMap(\.windows)
            .compactMap(\.resetTime)
            .filter { $0 > Date() }
            .min()

        return QuotaInfo(
            provider: provider,
            remainingPercentage: Int(average.rounded()),
            resetTime: nextReset
        )
    }
}
