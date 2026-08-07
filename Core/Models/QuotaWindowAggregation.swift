import Foundation

/// A quota window averaged only with the corresponding logical window from
/// the selected accounts. This intentionally differs from `QuotaInfo`, whose
/// provider aggregate is the most constrained window for each account.
struct AggregatedQuotaWindow: Identifiable, Sendable {
    let id: String
    let label: String
    let remainingPercentage: Int
    let resetTime: Date?
    let durationSeconds: TimeInterval?
    let accountCount: Int

    var isSpark: Bool { id == "spark" }
    var isWeekly: Bool { id == "weekly" }
}

private struct AccountQuotaWindowSample {
    let id: String
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
            Dictionary(grouping: account.windows, by: QuotaWindowAggregation.key)
                .compactMap { key, windows -> AccountQuotaWindowSample? in
                    guard let representative = windows.sorted(
                        by: QuotaWindowAggregation.representativeOrder
                    ).first else { return nil }
                    let percentage = Double(windows.map(\.remainingPercentage).reduce(0, +))
                        / Double(windows.count)
                    return AccountQuotaWindowSample(
                        id: key,
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
    static func key(for window: QuotaWindowInfo) -> String {
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
        let lhsRank = rank(lhs.id)
        let rhsRank = rank(rhs.id)
        return lhsRank == rhsRank ? lhs.label < rhs.label : lhsRank < rhsRank
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
}
