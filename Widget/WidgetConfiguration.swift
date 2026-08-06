import AppIntents
import Foundation

enum QuotaWidgetMode: String, AppEnum, Sendable {
    case singleProvider
    case providerOverview
    case accountOverview

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "显示方式 / Display")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .singleProvider: "单类额度详情 / One provider",
        .providerOverview: "多类额度总览 / Provider overview",
        .accountOverview: "账号额度 / Accounts"
    ]
}

enum WidgetProviderChoice: String, AppEnum, Sendable {
    case automatic
    case claude
    case codex
    case gemini
    case kimi

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "服务类型 / Provider")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "自动选择 / Automatic",
        .claude: "Claude",
        .codex: "Codex",
        .gemini: "Gemini / Antigravity",
        .kimi: "Kimi"
    ]

    var provider: ProviderType? {
        ProviderType(rawValue: rawValue)
    }
}

enum WidgetWindowChoice: String, AppEnum, Sendable {
    case automatic
    case short
    case weekly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "配额周期 / Quota window")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "自动 / Automatic",
        .short: "短周期（5 小时）/ Short",
        .weekly: "周配额 / Weekly"
    ]
}

struct WidgetAccountEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "账号 / Account")
    static let defaultQuery = WidgetAccountQuery()

    let id: String
    let title: String
    let providerName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(providerName)")
    }
}

struct WidgetAccountQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        let wanted = Set(identifiers)
        return Self.allEntities().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        Self.allEntities()
    }

    private static func allEntities() -> [WidgetAccountEntity] {
        CacheStore().loadAccountQuota()
            .sorted {
                let providerOrder = $0.provider.displayName.localizedCaseInsensitiveCompare(
                    $1.provider.displayName
                )
                if providerOrder != .orderedSame {
                    return providerOrder == .orderedAscending
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .enumerated()
            .map { index, account in
                WidgetAccountEntity(
                    id: account.id,
                    title: maskedAccountTitle(account.displayName, fallbackIndex: index + 1),
                    providerName: account.provider.displayName
                )
            }
    }

    private static func maskedAccountTitle(_ value: String, fallbackIndex: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "账号 \(fallbackIndex) / Account \(fallbackIndex)" }
        guard let at = trimmed.firstIndex(of: "@") else { return trimmed }

        let local = trimmed[..<at]
        let domain = trimmed[at...]
        let prefix = local.prefix(2)
        return "\(prefix)•••\(domain)"
    }
}

struct AccountQuotaWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "CPA 额度显示 / CPA Quota"
    static let description = IntentDescription("选择额度显示方式、服务类型和账号。/ Choose a layout, provider and accounts.")

    @Parameter(title: "显示方式 / Display", default: .singleProvider)
    var mode: QuotaWidgetMode

    @Parameter(title: "服务类型 / Provider", default: .codex)
    var provider: WidgetProviderChoice

    @Parameter(title: "账号（最多 4 个）/ Accounts (up to 4)")
    var accounts: [WidgetAccountEntity]?

    init() {
        mode = .singleProvider
        provider = .codex
        accounts = nil
    }
}

struct QuotaTimelineWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "CPA 配额时间线 / CPA Timeline"
    static let description = IntentDescription("选择服务、账号和配额周期。/ Choose a provider, accounts and quota window.")

    @Parameter(title: "服务类型 / Provider", default: .automatic)
    var provider: WidgetProviderChoice

    @Parameter(title: "账号（大型最多显示 3 个）/ Accounts (up to 3 on Large)")
    var accounts: [WidgetAccountEntity]?

    @Parameter(title: "配额周期 / Quota window", default: .automatic)
    var window: WidgetWindowChoice

    init() {
        provider = .automatic
        accounts = nil
        window = .automatic
    }
}
