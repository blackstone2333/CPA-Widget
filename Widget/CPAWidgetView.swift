import SwiftUI
import WidgetKit

struct CPAAccountQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CPAWidgetEntry

    private var providerSummaries: [ProviderQuotaSummary] {
        let grouped = Dictionary(grouping: entry.accounts, by: \.provider)
        return grouped.compactMap { provider, accounts in
            accounts.isEmpty ? nil : ProviderQuotaSummary(provider: provider, accounts: accounts)
        }
        .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
    }

    private var selectedSummary: ProviderQuotaSummary? {
        let provider = entry.selectedProvider ?? providerSummaries.first?.provider
        return providerSummaries.first { $0.provider == provider }
    }

    var body: some View {
        Group {
            if entry.accounts.isEmpty {
                WidgetEmptyState(
                    entry: entry,
                    subtitle: entry.localized("Open CPA Widget, refresh once, then edit this widget.", "打开 CPA Widget 刷新一次，然后编辑此小组件。")
                )
            } else {
                switch entry.mode {
                case .singleProvider:
                    singleProviderLayout
                case .providerOverview:
                    providerOverviewLayout
                case .accountOverview:
                    accountOverviewLayout
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var singleProviderLayout: some View {
        if let summary = selectedSummary {
            switch family {
            case .systemSmall:
                SingleProviderRingView(summary: summary, entry: entry)
            case .systemLarge:
                LargeSingleProviderView(summary: summary, entry: entry)
            default:
                ProviderDetailView(summary: summary, entry: entry)
            }
        } else {
            WidgetEmptyState(entry: entry, subtitle: entry.localized("Choose another provider in Edit Widget.", "请在“编辑小组件”中改选其他服务。"))
        }
    }

    @ViewBuilder
    private var providerOverviewLayout: some View {
        switch family {
        case .systemSmall:
            RingGridView(items: providerSummaries.prefixArray(4), entry: entry)
        case .systemLarge:
            DetailGridView(
                items: providerSummaries.prefixArray(4).map(QuotaDetailItem.init),
                entry: entry,
                title: entry.localized("Provider Quota", "服务额度")
            )
        default:
            RingStripView(items: providerSummaries.prefixArray(4), entry: entry)
        }
    }

    @ViewBuilder
    private var accountOverviewLayout: some View {
        let ordered = entry.accounts.sorted(by: accountOrder)
        switch family {
        case .systemSmall:
            AccountRingGridView(accounts: ordered.prefixArray(4), entry: entry)
        case .systemLarge:
            DetailGridView(
                items: ordered.prefixArray(4).map(QuotaDetailItem.init),
                entry: entry,
                title: entry.localized("Account Quota", "账号额度")
            )
        default:
            AccountDetailListView(accounts: ordered.prefixArray(2), entry: entry)
        }
    }
}

struct CPAQuotaTimelineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CPAWidgetEntry

    private var groups: [QuotaTimelineGroup] {
        entry.accounts.compactMap { account in
            let windows = preferredWindows(for: account, choice: entry.windowChoice)
            return windows.isEmpty ? nil : QuotaTimelineGroup(account: account, windows: windows)
        }
        .sorted(by: timelineGroupOrder)
    }

    private var items: [QuotaTimelineItem] {
        groups.compactMap { group in
            group.windows.first.map { QuotaTimelineItem(account: group.account, window: $0) }
        }
    }

    private var capacity: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 2
        case .systemLarge: 3
        default: 2
        }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                WidgetEmptyState(
                    entry: entry,
                    subtitle: entry.localized("No matching reset window. Edit the provider, accounts or period.", "没有匹配的重置周期，请编辑服务、账号或周期。")
                )
            } else if family == .systemSmall {
                smallLayout
            } else if family == .systemLarge {
                largeLayout
            } else {
                standardLayout
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var smallLayout: some View {
        let visibleItems = items.prefixArray(capacity)
        return VStack(alignment: .leading, spacing: visibleItems.count == 3 ? 3 : 6) {
            WidgetHeader(title: entry.localized("Quota Timeline", "配额时间线"), entry: entry, compact: true)
            ForEach(visibleItems) { item in
                TimelineQuotaRow(item: item, date: entry.date, language: entry.language, compact: true)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var standardLayout: some View {
        let visibleItems = items.prefixArray(capacity)
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 5 : 9) {
            WidgetHeader(title: entry.localized("CPA Quota Timeline", "CPA 配额时间线"), entry: entry)
            QuotaRaceLegend(language: entry.language)
            ForEach(visibleItems) { item in
                TimelineQuotaRow(
                    item: item,
                    date: entry.date,
                    language: entry.language,
                    dense: family == .systemLarge
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var largeLayout: some View {
        let visibleGroups = groups.prefixArray(capacity)
        return VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: entry.localized("CPA Quota Timeline", "CPA 配额时间线"), entry: entry)
            QuotaRaceLegend(language: entry.language)
            ForEach(visibleGroups) { group in
                TimelineAccountGroupView(group: group, date: entry.date, language: entry.language)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

private struct SingleProviderRingView: View {
    let summary: ProviderQuotaSummary
    let entry: CPAWidgetEntry

    var body: some View {
        VStack(spacing: 6) {
            WidgetHeader(title: summary.provider.displayName, entry: entry, compact: true)
            Spacer(minLength: 0)
            QuotaRing(
                percentage: summary.percentage,
                color: providerColor(summary.provider),
                diameter: 82,
                lineWidth: 10,
                provider: summary.provider
            )
            Text(entry.localized("Average · \(summary.accountCount) accounts", "平均余量 · \(summary.accountCount) 个账号"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct ProviderDetailView: View {
    let summary: ProviderQuotaSummary
    let entry: CPAWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 5) {
                QuotaRing(
                    percentage: summary.percentage,
                    color: providerColor(summary.provider),
                    diameter: 82,
                    lineWidth: 10,
                    provider: summary.provider
                )
                Text(summary.provider.displayName)
                    .font(.headline)
                Text(entry.localized("\(summary.accountCount) accounts", "\(summary.accountCount) 个账号"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: entry.localized("Quota details", "额度详情"), entry: entry)
                ForEach(summary.detailWindows.prefix(2)) { window in
                    WindowDetailRow(window: window, color: providerColor(summary.provider), language: entry.language)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }
}

private struct LargeSingleProviderView: View {
    let summary: ProviderQuotaSummary
    let entry: CPAWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            WidgetHeader(title: "\(summary.provider.displayName) · \(entry.localized("Account details", "账号详情"))", entry: entry)
            HStack(spacing: 14) {
                QuotaRing(
                    percentage: summary.percentage,
                    color: providerColor(summary.provider),
                    diameter: 76,
                    lineWidth: 9,
                    provider: summary.provider
                )
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(summary.detailWindows.prefix(2)) { window in
                        WindowDetailRow(window: window, color: providerColor(summary.provider), language: entry.language)
                    }
                }
            }
            DetailGridView(
                items: summary.accounts.sorted(by: accountOrder).prefixArray(4).map(QuotaDetailItem.init),
                entry: entry,
                title: ""
            )
            Spacer(minLength: 0)
        }
    }
}

private struct RingGridView: View {
    let items: [ProviderQuotaSummary]
    let entry: CPAWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: entry.localized("Providers", "服务额度"), entry: entry, compact: true)
            SmallProviderRingLayout(items: items)
        }
    }
}

private struct SmallProviderRingLayout: View {
    let items: [ProviderQuotaSummary]

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                providerRing(item, diameter: 72)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 5
                ) {
                    ForEach(items) { item in
                        providerRing(item, diameter: items.count == 2 ? 54 : 44)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func providerRing(_ item: ProviderQuotaSummary, diameter: CGFloat) -> some View {
        QuotaRing(
            percentage: item.percentage,
            color: providerColor(item.provider),
            diameter: diameter,
            lineWidth: diameter >= 54 ? 7 : 5,
            provider: item.provider
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.provider.displayName), \(item.percentage)%")
    }
}

private struct AccountRingGridView: View {
    let accounts: [AccountQuotaInfo]
    let entry: CPAWidgetEntry
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: entry.localized("Accounts", "账号额度"), entry: entry, compact: true)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(accounts) { account in
                    MiniRingTile(
                        title: account.displayName,
                        percentage: account.mostConstrainedPercentage,
                        provider: account.provider
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RingStripView: View {
    let items: [ProviderQuotaSummary]
    let entry: CPAWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: entry.localized("Provider Quota", "服务额度"), entry: entry)
            HStack(spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 5) {
                        QuotaRing(
                            percentage: item.percentage,
                            color: providerColor(item.provider),
                            diameter: 58,
                            lineWidth: 7,
                            provider: item.provider
                        )
                        Text(item.provider.displayName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AccountDetailListView: View {
    let accounts: [AccountQuotaInfo]
    let entry: CPAWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetHeader(title: entry.localized("Account Quota", "账号额度"), entry: entry)
            ForEach(accounts) { account in
                AccountDetailCard(item: QuotaDetailItem(account), language: entry.language, compact: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct DetailGridView: View {
    let items: [QuotaDetailItem]
    let entry: CPAWidgetEntry
    let title: String
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: title.isEmpty ? 0 : 9) {
            if !title.isEmpty {
                WidgetHeader(title: title, entry: entry)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items) { item in
                    AccountDetailCard(item: item, language: entry.language)
                }
            }
        }
    }
}

private struct AccountDetailCard: View {
    let item: QuotaDetailItem
    let language: AppLanguage
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(spacing: 6) {
                ProviderLogo(provider: item.provider, size: compact ? 12 : 14)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(item.percentage)%")
                    .font(.caption.monospacedDigit().weight(.bold))
            }
            ForEach(item.windows.prefix(2)) { window in
                WindowDetailRow(window: window, color: providerColor(item.provider), language: language, compact: true)
            }
        }
        .padding(compact ? 8 : 10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct MiniRingTile: View {
    let title: String
    let percentage: Int
    let provider: ProviderType

    var body: some View {
        HStack(spacing: 5) {
            QuotaRing(
                percentage: percentage,
                color: providerColor(provider),
                diameter: 38,
                lineWidth: 5,
                provider: provider
            )
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuotaRing: View {
    let percentage: Int
    let color: Color
    let diameter: CGFloat
    let lineWidth: CGFloat
    let provider: ProviderType

    private var clamped: Int { min(max(percentage, 0), 100) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped) / 100)
                .stroke(
                    clamped == 0 ? Color.red : color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                ProviderLogo(provider: provider, size: diameter * 0.19)
                Text("\(clamped)%")
                    .font(.system(size: diameter * 0.20, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.65)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("\(clamped)%")
    }
}

private struct WindowDetailRow: View {
    let window: QuotaWindowInfo
    let color: Color
    let language: AppLanguage
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(language.quotaLabel(window.label))
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(window.remainingPercentage)%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                if !compact, let reset = window.resetTime {
                    Text(language.relativeString(for: reset, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            WidgetQuotaBar(
                percentage: window.remainingPercentage,
                color: color,
                height: compact ? 6 : 11
            )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetQuotaBar: View {
    let percentage: Int
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(percentage, 0), 100)
            let width = proxy.size.width * CGFloat(clamped) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(clamped == 0 ? Color.red : color)
                    .frame(width: clamped == 0 ? 4 : max(4, width))
            }
        }
        .frame(height: height)
    }
}

private struct TimelineAccountGroupView: View {
    let group: QuotaTimelineGroup
    let date: Date
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                ProviderLogo(provider: group.account.provider, size: 12)
                Text(group.account.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            ForEach(group.windows.prefix(2)) { window in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(language.quotaLabel(window.label))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(window.remainingPercentage)%")
                            .font(.caption2.monospacedDigit().weight(.bold))
                        if let reset = window.resetTime {
                            Text(language.text("重置 ", "Reset ") + language.relativeString(for: reset, relativeTo: date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    QuotaRaceBar(
                        item: QuotaTimelineItem(account: group.account, window: window),
                        date: date,
                        height: 5
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TimelineQuotaRow: View {
    let item: QuotaTimelineItem
    let date: Date
    let language: AppLanguage
    var compact = false
    var dense = false

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 2 : compact ? 3 : 5) {
            HStack(spacing: 5) {
                ProviderLogo(provider: item.account.provider, size: compact ? 10 : 12)
                Text(item.account.displayName)
                    .font((compact || dense ? Font.caption2 : Font.caption).weight(.semibold))
                    .lineLimit(1)
                Text(language.quotaLabel(item.window.label))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(item.window.remainingPercentage)%")
                    .font(.caption2.monospacedDigit().weight(.bold))
                if !compact, let reset = item.window.resetTime {
                    Text(language.text("重置 ", "Reset ") + language.relativeString(for: reset, relativeTo: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            QuotaRaceBar(
                item: item,
                date: date,
                height: dense ? 5 : compact ? 5 : 6
            )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuotaRaceLegend: View {
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(Color.secondary.opacity(0.72))
                    .overlay { Capsule().fill(Color.black.opacity(0.25)) }
                    .frame(width: 12)
            }
            .frame(width: 24, height: 5)
            Text(language.text("深色 = 已用额度", "Dark = quota used"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct QuotaRaceBar: View {
    let item: QuotaTimelineItem
    let date: Date
    let height: CGFloat

    private var elapsed: Double {
        guard let reset = item.window.resetTime,
              let duration = item.window.durationSeconds,
              duration > 0 else { return 0 }
        return min(max(1 - reset.timeIntervalSince(date) / duration, 0), 1)
    }

    private var used: Double {
        Double(min(max(item.window.usedPercentage, 0), 100)) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            let currentX = proxy.size.width * elapsed
            let usedWidth = proxy.size.width * used
            let color = providerColor(item.account.provider)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.13))
                Capsule()
                    .fill(color.opacity(0.22))
                    .frame(width: max(2, currentX))
                if used > 0 {
                    Capsule()
                        .fill(color.opacity(0.94))
                        .overlay { Capsule().fill(Color.black.opacity(0.25)) }
                        .frame(width: max(5, usedWidth))
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.86))
                    .frame(width: 1.5, height: max(8, height + 4))
                    .offset(x: min(max(currentX - 0.75, 0), max(proxy.size.width - 1.5, 0)))
            }
        }
        .frame(height: height)
    }
}

private struct WidgetHeader: View {
    let title: String
    let entry: CPAWidgetEntry
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.tint)
            Text(compact ? "CPA" : title)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(2)
            Spacer(minLength: 3)
            Text(updatedText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .layoutPriority(1)
            if entry.warnsAboutInsecureHTTP {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(entry.localized(
                        "Connection uses HTTP; HTTPS is recommended.",
                        "当前连接使用 HTTP，建议改用 HTTPS。"
                    ))
            }
            Link(destination: URL(string: "cpawidget://refresh")!) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.localized("Refresh quota", "手动刷新配额"))
        }
    }

    private var updatedText: String {
        let relative = entry.language.relativeString(for: entry.latestUpdate, relativeTo: entry.date)
        return compact
            ? relative
            : entry.localized("Updated \(relative)", "更新于 \(relative)")
    }
}

private struct WidgetEmptyState: View {
    @Environment(\.widgetFamily) private var family
    let entry: CPAWidgetEntry
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetHeader(title: "CPA", entry: entry)
            Spacer(minLength: 0)
            Image(systemName: emptyStateSymbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
            if family != .systemSmall {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        switch entry.status {
        case .fresh, .partial:
            entry.localized("No quota data", "暂无配额数据")
        default:
            entry.status.localizedMessage(language: entry.language)
        }
    }

    private var emptyStateSymbol: String {
        switch entry.status {
        case .fresh, .partial: "chart.bar.xaxis"
        default: entry.status.emptyStateSymbol
        }
    }
}

private struct ProviderQuotaSummary: Identifiable {
    let provider: ProviderType
    let accounts: [AccountQuotaInfo]
    var id: String { provider.rawValue }
    var percentage: Int { roundedAverage(accounts.map(\.mostConstrainedPercentage)) }
    var accountCount: Int { accounts.count }

    var detailWindows: [QuotaWindowInfo] {
        let all = accounts.flatMap(\.windows)
        let grouped = Dictionary(grouping: all, by: windowGroupKey)
        return grouped.map { key, windows in
            let representative = windows.sorted(by: windowOrder).first!
            return QuotaWindowInfo(
                id: "\(provider.rawValue)-summary-\(key)",
                label: representative.label,
                remainingPercentage: roundedAverage(windows.map(\.remainingPercentage)),
                resetTime: windows.compactMap(\.resetTime).min(),
                durationSeconds: windows.compactMap(\.durationSeconds).min()
            )
        }
        .sorted(by: windowOrder)
    }
}

private func roundedAverage(_ values: [Int]) -> Int {
    guard !values.isEmpty else { return 0 }
    return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
}

private struct QuotaDetailItem: Identifiable {
    let id: String
    let title: String
    let provider: ProviderType
    let percentage: Int
    let windows: [QuotaWindowInfo]

    init(_ account: AccountQuotaInfo) {
        id = account.id
        title = account.displayName
        provider = account.provider
        percentage = account.mostConstrainedPercentage
        windows = account.windows.sorted(by: windowOrder)
    }

    init(_ summary: ProviderQuotaSummary) {
        id = summary.id
        title = summary.provider.displayName
        provider = summary.provider
        percentage = summary.percentage
        windows = summary.detailWindows
    }
}

private struct QuotaTimelineItem: Identifiable {
    let account: AccountQuotaInfo
    let window: QuotaWindowInfo
    var id: String { "\(account.id)-\(window.id)" }
}

private struct QuotaTimelineGroup: Identifiable {
    let account: AccountQuotaInfo
    let windows: [QuotaWindowInfo]
    var id: String { account.id }
}

private func timelineGroupOrder(_ lhs: QuotaTimelineGroup, _ rhs: QuotaTimelineGroup) -> Bool {
    let providerOrder = lhs.account.provider.displayName.localizedCaseInsensitiveCompare(
        rhs.account.provider.displayName
    )
    if providerOrder != .orderedSame {
        return providerOrder == .orderedAscending
    }
    return lhs.account.displayName.localizedCaseInsensitiveCompare(rhs.account.displayName)
        == .orderedAscending
}

private func preferredWindows(
    for account: AccountQuotaInfo,
    choice: WidgetWindowChoice
) -> [QuotaWindowInfo] {
    let candidates = account.windows
        .filter { $0.resetTime != nil && $0.durationSeconds != nil }
        .sorted(by: windowOrder)
    let matching: [QuotaWindowInfo]
    switch choice {
    case .short:
        matching = candidates.filter(isShortWindow)
    case .weekly:
        matching = candidates.filter(isWeekScaleWindow)
    case .automatic:
        let weekly = candidates.filter(isWeekScaleWindow)
        matching = weekly.isEmpty ? candidates : weekly
    }
    return matching.prefixArray(2)
}

private func windowGroupKey(_ window: QuotaWindowInfo) -> String {
    let text = "\(window.id) \(window.label)".lowercased()
    if text.contains("spark") { return "spark" }
    if text.contains("week") { return "weekly" }
    if text.contains("5-hour") || text.contains("5h") { return "short" }
    return window.label.lowercased()
}

private func windowOrder(_ lhs: QuotaWindowInfo, _ rhs: QuotaWindowInfo) -> Bool {
    func rank(_ window: QuotaWindowInfo) -> Int {
        let key = windowGroupKey(window)
        if key == "weekly" { return 0 }
        if key == "spark" { return 1 }
        if key == "short" { return 2 }
        return 3
    }
    let lhsRank = rank(lhs)
    let rhsRank = rank(rhs)
    return lhsRank == rhsRank ? lhs.label < rhs.label : lhsRank < rhsRank
}

private func isWeeklyWindow(_ window: QuotaWindowInfo) -> Bool {
    let text = "\(window.id) \(window.label)".lowercased()
    return text.contains("week") && !text.contains("spark")
}

private func isWeekScaleWindow(_ window: QuotaWindowInfo) -> Bool {
    if let duration = window.durationSeconds, duration >= 6 * 24 * 60 * 60 {
        return true
    }
    let text = "\(window.id) \(window.label)".lowercased()
    return text.contains("week") || text.contains("weekly") || text.contains("周")
}

private func isShortWindow(_ window: QuotaWindowInfo) -> Bool {
    let text = "\(window.id) \(window.label)".lowercased()
    return text.contains("5-hour") || text.contains("5h") || (window.durationSeconds ?? .infinity) <= 6 * 60 * 60
}

private func accountOrder(_ lhs: AccountQuotaInfo, _ rhs: AccountQuotaInfo) -> Bool {
    if lhs.mostConstrainedPercentage != rhs.mostConstrainedPercentage {
        return lhs.mostConstrainedPercentage < rhs.mostConstrainedPercentage
    }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}

private extension Collection {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}

private extension CPAWidgetEntry {
    func localized(_ english: String, _ chinese: String) -> String {
        language.text(chinese, english)
    }

    var latestUpdate: Date {
        accounts.map(\.updatedAt).max() ?? date
    }
}

private extension CacheStatus {
    var emptyStateSymbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .authenticationFailed: "key.slash"
        case .configurationRequired: "gear.badge.questionmark"
        default: "chart.bar.xaxis"
        }
    }

    func localizedMessage(language: AppLanguage) -> String {
        switch self {
        case .fresh: language.text("已更新", "Up to date")
        case .partial: language.text("部分服务不可用", "Some providers unavailable")
        case .offline: language.text("当前离线（显示上次数据）", "Offline (showing cached data)")
        case .authenticationFailed: language.text("令牌无效", "Invalid token")
        case .configurationRequired: language.text("需要配置", "Configuration required")
        case .noData: language.text("暂无配额数据", "No quota data")
        }
    }
}

private func providerColor(_ provider: ProviderType) -> Color {
    switch provider {
    case .claude: .orange
    case .codex: .green
    case .gemini: .blue
    case .kimi: .indigo
    }
}
