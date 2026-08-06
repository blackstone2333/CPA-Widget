import AppIntents
import SwiftUI
import WidgetKit

struct CPAAccountQuotaWidget: Widget {
    let kind = "CPAAccountQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CPAWidgetTimelineProvider()) { entry in
            CPAAccountQuotaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CPA Codex Quota / CPA Codex 额度")
        .description("Default Codex quota; existing desktop widgets keep working / 默认显示 Codex，兼容现有桌面组件")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CPAConfigurableAccountQuotaWidget: Widget {
    let kind = "CPAConfigurableAccountQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: AccountQuotaWidgetIntent.self,
            provider: CPAAccountWidgetTimelineProvider()
        ) { entry in
            CPAAccountQuotaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CPA Quota (Configurable) / CPA 额度（可配置）")
        .description("Choose one provider, provider overview, or up to four accounts / 可选择服务总览或最多四个账号")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CPAQuotaTimelineWidget: Widget {
    let kind = "CPAQuotaTimelineWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: QuotaTimelineWidgetIntent.self,
            provider: CPATimelineWidgetTimelineProvider()
        ) { entry in
            CPAQuotaTimelineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CPA Quota Timeline / CPA 配额时间线")
        .description("CPA quota reset timeline / 查看 CPA 配额重置时间线")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CPAConfigurableQuotaTimelineWidget: Widget {
    let kind = "CPAConfigurableQuotaTimelineWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: QuotaTimelineWidgetIntent.self,
            provider: CPATimelineWidgetTimelineProvider()
        ) { entry in
            CPAQuotaTimelineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CPA Timeline (Configurable) / CPA 时间线（可配置）")
        .description("Choose provider, accounts and weekly or short quota window / 可选择服务、账号和配额周期")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
