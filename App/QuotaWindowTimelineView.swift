import SwiftUI

enum QuotaWindowScale: String, CaseIterable, Identifiable {
    case weekly
    case fiveHour

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .weekly: language.text("按周", "Weekly")
        case .fiveHour: language.text("5 小时", "5-hour")
        }
    }

    func includes(_ window: QuotaWindowInfo) -> Bool {
        guard let duration = window.durationSeconds, duration > 0 else { return false }
        switch self {
        case .weekly: return duration >= 6 * 24 * 3_600 && duration <= 8 * 24 * 3_600
        case .fiveHour: return duration >= 4 * 3_600 && duration <= 6 * 3_600
        }
    }

    var badge: String {
        switch self {
        case .weekly: "7d"
        case .fiveHour: "5h"
        }
    }
}

struct QuotaWindowTimelineView: View {
    let accounts: [AccountQuotaInfo]
    let scale: QuotaWindowScale
    let language: AppLanguage
    var referenceDate = Date()

    @State private var pageOffset = 0

    private var rows: [TimelineAccount] {
        accounts.compactMap { account in
            let windows = account.windows
                .filter(scale.includes)
                .filter { $0.resetTime != nil && $0.durationSeconds != nil }
                .sorted { ($0.resetTime ?? .distantFuture) < ($1.resetTime ?? .distantFuture) }
            guard !windows.isEmpty else { return nil }
            return TimelineAccount(account: account, windows: windows)
        }
        .sorted { lhs, rhs in
            let providerOrder = lhs.account.provider.displayName.localizedCaseInsensitiveCompare(
                rhs.account.provider.displayName
            )
            if providerOrder != .orderedSame {
                return providerOrder == .orderedAscending
            }
            return lhs.account.displayName.localizedCaseInsensitiveCompare(rhs.account.displayName)
                == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            navigationBar

            if rows.isEmpty {
                Text(language.text("当前视图没有正在计时的配额窗口。", "No timed quota windows match this view."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
            } else {
                timelineGrid
                legend
            }
        }
        .onChange(of: scale) { _, _ in
            pageOffset = 0
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rangeLabel)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(scale == .weekly
                    ? language.text("两周 · 当前窗口与相邻周期", "Two weeks · current and adjacent windows")
                    : language.text("三天 · 连续 5 小时窗口", "Three days · consecutive 5-hour windows"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ControlGroup {
                Button {
                    pageOffset -= 1
                } label: {
                    Label(language.text("上一页", "Previous"), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }

                Button(language.text("今天", "Today")) {
                    pageOffset = 0
                }
                .disabled(pageOffset == 0)

                Button {
                    pageOffset += 1
                } label: {
                    Label(language.text("下一页", "Next"), systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var timelineGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(language.text("凭证", "Credential"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .frame(width: 245, alignment: .leading)

                TimelineAxis(
                    range: visibleRange,
                    scale: scale,
                    language: language,
                    referenceDate: referenceDate
                )
            }
            .frame(height: 48)

            Divider()

            ForEach(rows) { row in
                HStack(spacing: 0) {
                    TimelineAccountLabel(
                        row: row,
                        scale: scale,
                        language: language
                    )
                    .frame(width: 245)

                    WindowTrack(
                        row: row,
                        range: visibleRange,
                        referenceDate: referenceDate,
                        language: language
                    )
                }
                .frame(height: 74)

                if row.id != rows.last?.id {
                    Divider()
                }
            }
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                if visibleRange.contains(referenceDate) {
                    let trackWidth = max(proxy.size.width - 245, 0)
                    Rectangle()
                        .fill(Color.primary.opacity(0.38))
                        .frame(width: 1.5, height: proxy.size.height)
                        .offset(
                            x: 245 + timelineX(
                                for: referenceDate,
                                range: visibleRange,
                                width: trackWidth
                            )
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            TimelineLegendSwatch(style: .current)
            Text(language.text("当前窗口", "Current"))
            TimelineLegendSwatch(style: .future)
            Text(language.text("即将开始", "Upcoming"))
            TimelineLegendSwatch(style: .past)
            Text(language.text("已结束", "Ended"))
            TimelineUsageSwatch()
            Text(language.text("深色为已用额度", "Dark fill is quota used"))
            Spacer()
            Text(language.text(
                "垂直线表示现在；将已用比例与已过时间比例比较，可判断消耗快慢。",
                "The vertical line is now; compare used quota with elapsed time to judge pace."
            ))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        calendar.firstWeekday = 1
        return calendar
    }

    private var visibleRange: DateInterval {
        switch scale {
        case .weekly:
            let base = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
                ?? calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: pageOffset * 14, to: base) ?? base
            let end = calendar.date(byAdding: .day, value: 14, to: start)
                ?? start.addingTimeInterval(14 * 24 * 3_600)
            return DateInterval(start: start, end: end)
        case .fiveHour:
            let base = calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: pageOffset * 3, to: base) ?? base
            let end = calendar.date(byAdding: .day, value: 3, to: start)
                ?? start.addingTimeInterval(3 * 24 * 3_600)
            return DateInterval(start: start, end: end)
        }
    }

    private var rangeLabel: String {
        let lastMoment = visibleRange.end.addingTimeInterval(-1)
        return "\(shortDate(visibleRange.start)) – \(shortDate(lastMoment))"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

private struct TimelineAccount: Identifiable {
    let account: AccountQuotaInfo
    let windows: [QuotaWindowInfo]

    var id: String { account.id }

    var anchor: QuotaWindowInfo {
        windows.min { lhs, rhs in
            if lhs.remainingPercentage != rhs.remainingPercentage {
                return lhs.remainingPercentage < rhs.remainingPercentage
            }
            return (lhs.resetTime ?? .distantFuture) < (rhs.resetTime ?? .distantFuture)
        } ?? windows[0]
    }
}

private struct TimelineAccountLabel: View {
    let row: TimelineAccount
    let scale: QuotaWindowScale
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(timelineProviderColor(row.account.provider))
                    .frame(width: 7, height: 7)
                Text(row.account.displayName)
                    .font(.caption.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(scale.badge)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            HStack(spacing: 9) {
                ForEach(row.windows.prefix(2)) { window in
                    Text("\(language.quotaLabel(window.label)) \(window.remainingPercentage)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct TimelineAxis: View {
    let range: DateInterval
    let scale: QuotaWindowScale
    let language: AppLanguage
    let referenceDate: Date

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    let x = timelineX(for: tick, range: range, width: proxy.size.width)
                    Rectangle()
                        .fill(.separator.opacity(0.35))
                        .frame(width: 1, height: proxy.size.height)
                        .offset(x: x)

                    VStack(spacing: 1) {
                        if scale == .weekly || Calendar.current.component(.hour, from: tick) == 0 {
                            Text(weekday(for: tick))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(tickLabel(for: tick))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48)
                    .offset(x: min(max(x - 24, 0), max(proxy.size.width - 48, 0)), y: 6)
                }

            }
        }
    }

    private var ticks: [Date] {
        let step: TimeInterval = scale == .weekly ? 24 * 3_600 : 6 * 3_600
        var result: [Date] = []
        var date = range.start
        while date < range.end {
            result.append(date)
            date = date.addingTimeInterval(step)
        }
        return result
    }

    private func weekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func tickLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = scale == .weekly ? "MM/dd" : "HH:mm"
        return formatter.string(from: date)
    }
}

private struct WindowTrack: View {
    let row: TimelineAccount
    let range: DateInterval
    let referenceDate: Date
    let language: AppLanguage

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ForEach(gridDates, id: \.self) { date in
                    Rectangle()
                        .fill(.separator.opacity(0.22))
                        .frame(width: 1, height: proxy.size.height)
                        .offset(x: timelineX(for: date, range: range, width: proxy.size.width))
                }

                ForEach(segments) { segment in
                    let startX = timelineX(
                        for: max(segment.start, range.start),
                        range: range,
                        width: proxy.size.width
                    )
                    let endX = timelineX(
                        for: min(segment.end, range.end),
                        range: range,
                        width: proxy.size.width
                    )
                    let width = max(endX - startX, 3)
                    let usedEnd = segment.start.addingTimeInterval(
                        segment.end.timeIntervalSince(segment.start) * Double(usedFraction)
                    )
                    let usedEndX = timelineX(
                        for: min(max(usedEnd, range.start), range.end),
                        range: range,
                        width: proxy.size.width
                    )
                    let usedWidth = min(max(usedEndX - startX, 0), width)
                    let visibleUsedWidth = usedFraction > 0
                        ? min(max(usedWidth, 6), width)
                        : 0

                    ZStack(alignment: .leading) {
                        TimelineSegmentShape(style: segment.style, color: color)

                        if segment.style == .current, visibleUsedWidth > 0 {
                            TimelineUsedQuotaFill(color: color)
                                .frame(width: visibleUsedWidth)
                        }

                        Group {
                            if segment.style == .current, width > 92 {
                                Text("\(row.anchor.remainingPercentage)% · \(shortReset(segment.end))")
                                    .font(.caption2.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.primary.opacity(0.78))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                            } else if width > 70 {
                                Text(shortReset(segment.end))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .frame(width: width, height: 24)
                    .clipShape(Capsule())
                    .offset(x: startX)
                }
            }
        }
        .padding(.vertical, 24)
    }

    private var color: Color { timelineProviderColor(row.account.provider) }

    private var usedFraction: CGFloat {
        CGFloat(min(max(100 - row.anchor.remainingPercentage, 0), 100)) / 100
    }

    private var segments: [TimelineSegment] {
        guard let reset = row.anchor.resetTime,
              let duration = row.anchor.durationSeconds,
              duration > 0 else { return [] }

        var start = reset.addingTimeInterval(-duration)
        while start > range.start {
            start = start.addingTimeInterval(-duration)
        }
        while start.addingTimeInterval(duration) <= range.start {
            start = start.addingTimeInterval(duration)
        }

        var result: [TimelineSegment] = []
        while start < range.end {
            let end = start.addingTimeInterval(duration)
            let style: TimelineSegmentStyle
            if referenceDate >= start && referenceDate < end {
                style = .current
            } else if end <= referenceDate {
                style = .past
            } else {
                style = .future
            }
            result.append(TimelineSegment(start: start, end: end, style: style))
            start = end
        }
        return result
    }

    private var gridDates: [Date] {
        let duration = row.anchor.durationSeconds ?? 7 * 24 * 3_600
        let step: TimeInterval = duration <= 6 * 3_600 ? 6 * 3_600 : 24 * 3_600
        var dates: [Date] = []
        var date = range.start
        while date < range.end {
            dates.append(date)
            date = date.addingTimeInterval(step)
        }
        return dates
    }

    private func shortReset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = (row.anchor.durationSeconds ?? 0) <= 6 * 3_600
            ? "HH:mm"
            : "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct TimelineSegment: Identifiable {
    let start: Date
    let end: Date
    let style: TimelineSegmentStyle

    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
}

private enum TimelineSegmentStyle: Equatable {
    case current
    case future
    case past
}

private struct TimelineSegmentShape: View {
    let style: TimelineSegmentStyle
    let color: Color

    var body: some View {
        switch style {
        case .current:
            Capsule()
                .fill(color.opacity(0.24))
                .overlay { Capsule().stroke(color.opacity(0.65), lineWidth: 1) }
        case .future:
            Capsule()
                .fill(Color.clear)
                .overlay {
                    Capsule().stroke(
                        color.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                }
        case .past:
            Capsule().fill(color.opacity(0.08))
        }
    }
}

private struct TimelineLegendSwatch: View {
    let style: TimelineSegmentStyle

    var body: some View {
        TimelineSegmentShape(style: style, color: .secondary)
            .frame(width: 22, height: 8)
    }
}

private struct TimelineUsageSwatch: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.18))
            TimelineUsedQuotaFill(color: .secondary)
                .frame(width: 12)
        }
        .frame(width: 22, height: 8)
    }
}

private struct TimelineUsedQuotaFill: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.92))
            .overlay {
                Capsule().fill(Color.black.opacity(0.28))
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.58))
                    .frame(width: 1)
                    .padding(.vertical, 3)
            }
    }
}

private func timelineX(for date: Date, range: DateInterval, width: CGFloat) -> CGFloat {
    let duration = range.duration
    guard duration > 0 else { return 0 }
    let fraction = min(max(date.timeIntervalSince(range.start) / duration, 0), 1)
    return width * fraction
}

private func timelineProviderColor(_ provider: ProviderType) -> Color {
    switch provider {
    case .claude: .orange
    case .codex: .indigo
    case .gemini: .teal
    case .kimi: .blue
    }
}
