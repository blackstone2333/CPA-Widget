import Foundation
import WidgetKit

struct CPAWidgetEntry: TimelineEntry {
    let date: Date
    let accounts: [AccountQuotaInfo]
    let status: CacheStatus
    let language: AppLanguage
    let mode: QuotaWidgetMode
    let selectedProvider: ProviderType?
    let selectedAccountIDs: [String]
    let windowChoice: WidgetWindowChoice
    let warnsAboutInsecureHTTP: Bool

    static let placeholder = CPAWidgetEntry(
        date: Date(),
        accounts: [
            AccountQuotaInfo(
                id: "claude-work",
                provider: .claude,
                displayName: "Work Claude",
                planName: "Pro",
                windows: [
                    QuotaWindowInfo(
                        id: "five-hour",
                        label: "5h",
                        remainingPercentage: 72,
                        resetTime: Date().addingTimeInterval(3 * 60 * 60),
                        durationSeconds: 5 * 60 * 60
                    ),
                    QuotaWindowInfo(
                        id: "weekly",
                        label: "Weekly",
                        remainingPercentage: 48,
                        resetTime: Date().addingTimeInterval(4 * 24 * 60 * 60),
                        durationSeconds: 7 * 24 * 60 * 60
                    )
                ],
                updatedAt: Date()
            ),
            AccountQuotaInfo(
                id: "codex-personal",
                provider: .codex,
                displayName: "Personal Codex",
                planName: "Plus",
                windows: [
                    QuotaWindowInfo(
                        id: "five-hour",
                        label: "5h",
                        remainingPercentage: 34,
                        resetTime: Date().addingTimeInterval(90 * 60),
                        durationSeconds: 5 * 60 * 60
                    )
                ],
                updatedAt: Date()
            ),
            AccountQuotaInfo(
                id: "gemini-work",
                provider: .gemini,
                displayName: "Work Gemini",
                planName: nil,
                windows: [
                    QuotaWindowInfo(
                        id: "daily",
                        label: "Daily",
                        remainingPercentage: 83,
                        resetTime: Date().addingTimeInterval(12 * 60 * 60),
                        durationSeconds: 24 * 60 * 60
                    )
                ],
                updatedAt: Date()
            )
        ],
        status: .fresh,
        language: .english,
        mode: .providerOverview,
        selectedProvider: .codex,
        selectedAccountIDs: [],
        windowChoice: .automatic,
        warnsAboutInsecureHTTP: false
    )
}
