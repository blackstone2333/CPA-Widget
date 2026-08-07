import Foundation

/// A quota window averaged only with the corresponding logical window from
/// the selected accounts. This intentionally differs from `QuotaInfo`, whose
/// provider aggregate is the most constrained window for each account.
struct AggregatedQuotaWindow: Identifiable, Sendable {
    let id: String
    let category: String
    let provider: ProviderType
    let label: String
    let remainingPercentage: Int
    let resetTime: Date?
    let durationSeconds: TimeInterval?
    let accountCount: Int

    var isSpark: Bool { category == "spark" }
    var isWeekly: Bool { category == "weekly" }
}

private struct AccountQuotaWindowSample {
    let id: String
    let category: String
    let provider: ProviderType
    let label: String
    let remainingPercentage: Int
    let resetTime: Date?
    let durationSeconds: TimeInterval?
}

extension Collection where Element == AccountQuotaInfo {
    func aggregateQuotaWindows() -> [AggregatedQuotaWindow] {
        // Each account contributes at most one value to a logical window. If
        // an upstream response repeats a window, that account is not weighted
        // more heavily than the other selected accounts.
        let samples = flatMap { account in
            Dictionary(grouping: account.windows) {
                QuotaWindowAggregation.identity(for: $0, provider: account.provider)
            }
                .compactMap { key, windows -> AccountQuotaWindowSample? in
                    guard let representative = windows.sorted(
                        by: QuotaWindowAggregation.representativeOrder
                    ).first else { return nil }
                    let percentage = Double(windows.map(\.remainingPercentage).reduce(0, +))
                        / Double(windows.count)
                    return AccountQuotaWindowSample(
                        id: key,
                        category: QuotaWindowAggregation.category(for: representative),
                        provider: account.provider,
                        label: representative.label,
                        remainingPercentage: Int(percentage.rounded()),
                        resetTime: QuotaWindowAggregation.earliestUpcomingReset(in: windows),
                        durationSeconds: representative.durationSeconds
                    )
                }
        }
        let grouped = Dictionary(grouping: samples, by: \.id)

        return grouped.compactMap { key, accountSamples in
            guard !accountSamples.isEmpty else { return nil }
            let representative = accountSamples.sorted {
                $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }.first
            let percentage = Double(accountSamples.map(\.remainingPercentage).reduce(0, +))
                / Double(accountSamples.count)
            let resetTimes = accountSamples.compactMap(\.resetTime)
            let upcomingReset = resetTimes.filter { $0 > Date() }.min() ?? resetTimes.min()
            return AggregatedQuotaWindow(
                id: key,
                category: representative?.category ?? "other",
                provider: representative?.provider ?? .codex,
                label: representative?.label ?? key,
                remainingPercentage: Int(percentage.rounded()),
                resetTime: upcomingReset,
                durationSeconds: representative?.durationSeconds,
                accountCount: accountSamples.count
            )
        }
        .sorted(by: QuotaWindowAggregation.displayOrder)
    }
}

enum QuotaWindowAggregation {
    /// A stable selection identity preserves every window actually returned by
    /// CLIProxyAPI. Period categories such as `weekly` remain sorting/default
    /// hints only; using them as identity previously merged Antigravity's
    /// Gemini and Claude/GPT windows into one row.
    static func identity(for window: QuotaWindowInfo, provider: ProviderType) -> String {
        let rawID = window.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let component: String
        if provider == .gemini, looksLikeGeneratedUUID(rawID) {
            component = "label-\(normalizedComponent(window.label))"
        } else {
            component = normalizedComponent(rawID.isEmpty ? window.label : rawID)
        }
        return "\(provider.rawValue):\(component)"
    }

    static func category(for window: QuotaWindowInfo) -> String {
        let text = "\(window.id) \(window.label)".lowercased()
        if text.contains("spark") { return "spark" }
        if text.contains("week") || text.contains("weekly") || text.contains("周") {
            return "weekly"
        }
        if let duration = window.durationSeconds {
            if duration >= 6 * 24 * 3_600 && duration <= 8 * 24 * 3_600 { return "weekly" }
            if duration >= 28 * 24 * 3_600 { return "monthly" }
            if duration >= 4 * 3_600 && duration <= 6 * 3_600 { return "short" }
        }
        if text.contains("5-hour") || text.contains("5h") { return "short" }
        if text.contains("month") || text.contains("monthly") { return "monthly" }
        return "other-\(window.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func earliestUpcomingReset(in windows: [QuotaWindowInfo], now: Date = Date()) -> Date? {
        let resetTimes = windows.compactMap(\.resetTime)
        return resetTimes.filter { $0 > now }.min() ?? resetTimes.min()
    }

    static func displayOrder(_ lhs: AggregatedQuotaWindow, _ rhs: AggregatedQuotaWindow) -> Bool {
        let lhsRank = rank(lhs.category)
        let rhsRank = rank(rhs.category)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.provider.sortOrder != rhs.provider.sortOrder {
            return lhs.provider.sortOrder < rhs.provider.sortOrder
        }
        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
    }

    static func representativeOrder(_ lhs: QuotaWindowInfo, _ rhs: QuotaWindowInfo) -> Bool {
        lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
    }

    private static func rank(_ key: String) -> Int {
        switch key {
        case "weekly": 0
        case "spark": 1
        case "short": 2
        case "monthly": 3
        default: 4
        }
    }

    private static func normalizedComponent(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
    }

    private static func looksLikeGeneratedUUID(_ value: String) -> Bool {
        let candidate = value.split(separator: "-").suffix(5).joined(separator: "-")
        return UUID(uuidString: candidate) != nil
    }
}

extension Collection where Element == AggregatedQuotaWindow {
    /// Resolves new stable IDs first, then v0.5.5 semantic aliases such as
    /// `weekly`, `spark`, and `other-<label>`.
    func resolvingSelection(_ selectionID: String?) -> AggregatedQuotaWindow? {
        guard let selectionID else { return nil }
        if let exact = first(where: { $0.id == selectionID }) { return exact }
        if let category = first(where: { $0.category == selectionID }) { return category }
        return first {
            "other-\($0.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
                == selectionID
        }
    }
}
