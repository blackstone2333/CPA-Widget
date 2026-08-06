import Foundation

struct QuotaInfo: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let provider: ProviderType
    let remainingPercentage: Int
    let resetTime: Date?
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        provider: ProviderType,
        remainingPercentage: Int,
        resetTime: Date?,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.remainingPercentage = min(max(remainingPercentage, 0), 100)
        self.resetTime = resetTime
        self.updatedAt = updatedAt
    }
}
