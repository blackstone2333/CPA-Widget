import AppKit
import SwiftUI

struct MenuBarQuotaStatusItem: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let summary = MenuBarQuotaSummary(
            configuration: model.menuBarConfiguration,
            accounts: model.accountQuota
        )
        MenuBarQuotaLabel(
            configuration: model.menuBarConfiguration,
            summary: summary,
            usesApplicationIconForGlobalScope: true
        )
        .help(tooltip(summary: summary))
        .accessibilityLabel(tooltip(summary: summary))
    }

    private func tooltip(summary: MenuBarQuotaSummary) -> String {
        if let primary = summary.primary {
            return model.language.text(
                "CPA 配额：\(primary.remainingPercentage)% 剩余。点击查看详情。",
                "CPA quota: \(primary.remainingPercentage)% remaining. Click for details."
            )
        }
        return model.language.text("CPA 配额：暂无数据。点击查看详情。", "CPA quota: no data. Click for details.")
    }
}

struct MenuBarQuotaPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let configuration = model.menuBarConfiguration
        let summary = MenuBarQuotaSummary(configuration: configuration, accounts: model.accountQuota)

        VStack(alignment: .leading, spacing: 12) {
            header(summary: summary)

            if let updatedAt = summary.accounts.map(\.updatedAt).max() {
                Text(t(
                    "更新于 \(model.language.relativeString(for: updatedAt))",
                    "Updated \(model.language.relativeString(for: updatedAt))"
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if model.cacheStatus != .fresh, let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(configuration.visiblePanelSections.enumerated()), id: \.element.id) { index, section in
                        panelSection(section, summary: summary, configuration: configuration)
                        if index < configuration.visiblePanelSections.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(height: panelContentHeight(summary: summary, configuration: configuration))

            Divider()

            HStack(spacing: 10) {
                Button {
                    Task { await model.refreshQuota() }
                } label: {
                    Label(
                        t("刷新", "Refresh"),
                        systemImage: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                    )
                }
                .disabled(model.isRefreshing || model.enabledProviders.isEmpty)

                Spacer()

                Button {
                    openMenuBarSettings()
                } label: {
                    Label(t("配置显示", "Configure"), systemImage: "slider.horizontal.3")
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 365)
    }

    @ViewBuilder
    private func panelSection(
        _ section: MenuBarConfiguration.PanelSection,
        summary: MenuBarQuotaSummary,
        configuration: MenuBarConfiguration
    ) -> some View {
        switch section {
        case .aggregate:
            VStack(alignment: .leading, spacing: 9) {
                panelSectionHeader(t("总额度", "Quota summary"), symbol: "gauge.with.dots.needle.67percent")
                aggregateQuota(summary: summary, display: configuration.display)
            }
        case .timeline:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                MenuBarQuotaTimelineSection(
                    accounts: summary.accounts,
                    scale: configuration.effectivePanelTimelineScale,
                    accountLimit: configuration.effectivePanelTimelineAccountLimit,
                    language: model.language,
                    referenceDate: context.date
                )
            }
        case .accounts:
            VStack(alignment: .leading, spacing: 9) {
                panelSectionHeader(t("账号详情", "Account details"), symbol: "person.text.rectangle")
                if summary.accounts.isEmpty {
                    Text(t("暂无所选账号数据。", "No selected account data."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    accountRows(summary.accounts)
                }
            }
        }
    }

    private func panelSectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func panelContentHeight(
        summary: MenuBarQuotaSummary,
        configuration: MenuBarConfiguration
    ) -> CGFloat {
        var estimate: CGFloat = 0
        for section in configuration.visiblePanelSections {
            switch section {
            case .aggregate:
                estimate += summary.primary == nil ? 135 : 150
            case .timeline:
                let accountCount = min(
                    summary.accounts.count,
                    configuration.effectivePanelTimelineAccountLimit
                )
                estimate += 44 + CGFloat(max(accountCount, 1)) * 102
            case .accounts:
                estimate += 32 + summary.accounts.reduce(CGFloat.zero) { height, account in
                    height + 58 + CGFloat(min(account.windows.count, 2)) * 21
                } + CGFloat(max(0, summary.accounts.count - 1)) * 10
            }
        }
        estimate += CGFloat(max(0, configuration.visiblePanelSections.count - 1)) * 15
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        return min(max(estimate, 150), max(240, min(650, visibleHeight - 180)))
    }

    @ViewBuilder
    private func header(summary: MenuBarQuotaSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MenuBarScopeIcon(summary: summary, size: 22)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title(language: model.language))
                    .font(.headline)
                    .lineLimit(1)
                Text(summary.subtitle(language: model.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    model.cacheStatus.displayMessage(language: model.language),
                    systemImage: statusSymbol
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
            }
        }
    }

    @ViewBuilder
    private func aggregateQuota(
        summary: MenuBarQuotaSummary,
        display: MenuBarConfiguration.Display
    ) -> some View {
        if let primary = summary.primary {
            VStack(alignment: .leading, spacing: 8) {
                MenuBarAggregateRow(
                    window: primary,
                    color: summary.color,
                    language: model.language,
                    prominent: true
                )
                if let spark = summary.spark, spark.id != primary.id {
                    MenuBarAggregateRow(
                        window: spark,
                        color: summary.color.opacity(0.82),
                        language: model.language
                    )
                } else if display.showsSecondaryQuota, let secondary = summary.secondary {
                    MenuBarAggregateRow(
                        window: secondary,
                        color: summary.color.opacity(0.82),
                        language: model.language
                    )
                }
            }
        } else {
            ContentUnavailableView(
                model.cacheStatus.displayMessage(language: model.language),
                systemImage: emptyStateSymbol,
                description: Text(t("刷新后将在这里显示所选账号的配额。", "Refresh to show quota for the selected accounts."))
            )
            .frame(maxWidth: .infinity, minHeight: 118)
        }
    }

    private func accountRows(_ accounts: [AccountQuotaInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(accounts) { account in
                MenuBarAccountRow(account: account, language: model.language)
            }
        }
    }

    private var statusSymbol: String {
        switch model.cacheStatus {
        case .fresh: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .offline: "wifi.slash"
        case .authenticationFailed: "key.slash"
        case .configurationRequired: "gear.badge.questionmark"
        case .noData: "chart.bar.xaxis"
        }
    }

    private var statusColor: Color {
        switch model.cacheStatus {
        case .fresh: .green
        case .partial: .orange
        default: .secondary
        }
    }

    private var emptyStateSymbol: String {
        switch model.cacheStatus {
        case .offline: "wifi.slash"
        case .authenticationFailed: "key.slash"
        case .configurationRequired: "gear.badge.questionmark"
        default: "chart.bar.xaxis"
        }
    }

    private func openMenuBarSettings() {
        model.requestMenuBarSettings()
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func t(_ chinese: String, _ english: String) -> String {
        model.language.text(chinese, english)
    }
}

struct MenuBarConfigurationEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let summary = MenuBarQuotaSummary(
            configuration: configuration,
            accounts: model.accountQuota
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(t("菜单栏配额", "Menu Bar Quota"), systemImage: "menubar.rectangle")
                    .font(.headline)
                Spacer()
                Toggle(t("显示", "Show"), isOn: binding(\.isEnabled))
                    .toggleStyle(.switch)
            }

            if configuration.isEnabled {
                Picker(t("显示范围", "Scope"), selection: binding(\.scope)) {
                    Text(t("全部账号", "All accounts")).tag(MenuBarConfiguration.Scope.allAccounts)
                    Text(t("指定服务", "Provider")).tag(MenuBarConfiguration.Scope.provider)
                    Text(t("指定账号", "Accounts")).tag(MenuBarConfiguration.Scope.accounts)
                }

                if configuration.scope != .allAccounts {
                    Picker(t("服务", "Provider"), selection: binding(\.provider)) {
                        ForEach(ProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                }

                if configuration.scope == .accounts {
                    accountPicker
                }

                if !summary.windows.isEmpty {
                    quotaWindowPickers(summary.windows)
                }

                Picker(t("外观", "Appearance"), selection: binding(\.preset)) {
                    ForEach(MenuBarConfiguration.Preset.allCases) { preset in
                        Text(presetTitle(preset)).tag(preset)
                    }
                }

                if configuration.preset == .custom {
                    customComposer
                }

                HStack(spacing: 12) {
                    Text(t("实时预览", "Live preview"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    MenuBarQuotaLabel(
                        configuration: configuration,
                        summary: summary,
                        usesApplicationIconForGlobalScope: true
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    Text("~\(Int(estimatedStatusWidth.rounded())) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                panelComposer
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(t("账号", "Accounts"))
                .font(.subheadline.weight(.medium))
            if model.accountQuota.isEmpty {
                Text(t("刷新后可选择账号。", "Refresh to choose accounts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(model.accountQuota.filter { $0.provider == configuration.provider }) { account in
                            Toggle(isOn: accountBinding(account.id)) {
                                HStack(spacing: 6) {
                                    ProviderLogo(provider: account.provider, size: 14)
                                    Text(account.displayName)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(account.provider.displayName)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var customComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("自定义元素", "Custom elements"))
                .font(.subheadline.weight(.medium))
            Toggle(t("图标", "Icon"), isOn: customBinding(\.showsIcon))
            Toggle(t("主配额百分比", "Primary percentage"), isOn: customBinding(\.showsPrimaryPercentage))
            Toggle(t("主配额进度条", "Primary linear bar"), isOn: customBinding(\.showsPrimaryLinearBar))
            Toggle(t("主配额圆环", "Primary ring"), isOn: customBinding(\.showsPrimaryRing))
            Toggle(t("次级配额", "Secondary quota"), isOn: customBinding(\.showsSecondaryQuota))
            Toggle(
                t("次级配额百分比", "Secondary percentage"),
                isOn: customSecondaryPercentageBinding
            )
            .disabled(!configuration.customDisplay.showsSecondaryQuota)
            Toggle(
                t("次级配额进度条", "Secondary linear bar"),
                isOn: customSecondaryLinearBarBinding
            )
            .disabled(!configuration.customDisplay.showsSecondaryQuota)
            Toggle(t("两行布局", "Two-line layout"), isOn: customBinding(\.usesTwoLines))
                .disabled(!configuration.customDisplay.showsSecondaryQuota)
            Picker(t("元素顺序", "Element order"), selection: customBinding(\.elementOrder)) {
                Text(t("图标在前", "Icon first")).tag(MenuBarConfiguration.ElementOrder.iconFirst)
                Text(t("数值在前", "Value first")).tag(MenuBarConfiguration.ElementOrder.valueFirst)
            }
            .pickerStyle(.segmented)
        }
        .font(.caption)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var panelComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(t("下拉面板内容", "Click panel contents"))
                .font(.subheadline.weight(.semibold))

            ForEach(configuration.orderedPanelSections) { section in
                HStack(spacing: 8) {
                    Toggle(isOn: panelSectionBinding(section)) {
                        Label(panelSectionTitle(section), systemImage: panelSectionSymbol(section))
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    Button {
                        movePanelSection(section, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(configuration.orderedPanelSections.first == section)

                    Button {
                        movePanelSection(section, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(configuration.orderedPanelSections.last == section)
                }
                .font(.caption)
            }

            if configuration.visiblePanelSections.contains(.timeline) {
                Picker(t("时间线周期", "Timeline period"), selection: panelTimelineScaleBinding) {
                    Text(t("按周", "Weekly")).tag(MenuBarConfiguration.PanelTimelineScale.weekly)
                    Text(t("5 小时", "5-hour")).tag(MenuBarConfiguration.PanelTimelineScale.fiveHour)
                }

                Picker(t("时间线账号", "Timeline accounts"), selection: panelTimelineLimitBinding) {
                    ForEach([2, 4, 6, 8], id: \.self) { count in
                        Text(t("最多 \(count) 个", "Up to \(count)")).tag(count)
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func quotaWindowPickers(_ windows: [AggregatedQuotaWindow]) -> some View {
        VStack(spacing: 8) {
            Picker(
                t("主配额", "Primary quota"),
                selection: windowBinding(\.primaryWindowID, availableWindows: windows)
            ) {
                Text(t("自动（周额度优先）", "Automatic (weekly first)"))
                    .tag(String?.none)
                ForEach(windows) { window in
                    Text(model.language.quotaLabel(window.label)).tag(Optional(window.id))
                }
            }

            Picker(
                t("第二配额", "Secondary quota"),
                selection: windowBinding(\.secondaryWindowID, availableWindows: windows)
            ) {
                Text(t("自动（Spark 优先）", "Automatic (Spark first)"))
                    .tag(String?.none)
                ForEach(windows) { window in
                    Text(model.language.quotaLabel(window.label)).tag(Optional(window.id))
                }
            }
        }
    }

    private var configuration: MenuBarConfiguration { model.menuBarConfiguration }

    private var estimatedStatusWidth: CGFloat {
        let summary = MenuBarQuotaSummary(
            configuration: configuration,
            accounts: model.accountQuota
        )
        return MenuBarStatusImageRenderer.pointSize(
            configuration: configuration,
            summary: summary
        ).width
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: keyPath] },
            set: { value in
                var updated = configuration
                updated[keyPath: keyPath] = value
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private func customBinding<Value>(
        _ keyPath: WritableKeyPath<MenuBarConfiguration.Display, Value>
    ) -> Binding<Value> {
        Binding(
            get: { configuration.customDisplay[keyPath: keyPath] },
            set: { value in
                var updated = configuration
                updated.customDisplay[keyPath: keyPath] = value
                updated.customDisplay = updated.customDisplay.normalized()
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private var customSecondaryPercentageBinding: Binding<Bool> {
        Binding(
            get: { configuration.customDisplay.displaysSecondaryPercentage },
            set: { value in
                var updated = configuration
                updated.customDisplay.showsSecondaryPercentage = value
                updated.customDisplay = updated.customDisplay.normalized()
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private var customSecondaryLinearBarBinding: Binding<Bool> {
        Binding(
            get: { configuration.customDisplay.displaysSecondaryLinearBar },
            set: { value in
                var updated = configuration
                updated.customDisplay.showsSecondaryLinearBar = value
                updated.customDisplay = updated.customDisplay.normalized()
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private func windowBinding(
        _ keyPath: WritableKeyPath<MenuBarConfiguration, String?>,
        availableWindows: [AggregatedQuotaWindow]
    ) -> Binding<String?> {
        let availableIDs = Set(availableWindows.map(\.id))
        return Binding(
            get: {
                guard let configured = configuration[keyPath: keyPath],
                      availableIDs.contains(configured) else {
                    return nil
                }
                return configured
            },
            set: { value in
                var updated = configuration
                updated[keyPath: keyPath] = value
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private func accountBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { configuration.accountIDs.contains(id) },
            set: { selected in
                var updated = configuration
                if selected {
                    updated.accountIDs = Array(Set(updated.accountIDs).union([id])).sorted()
                } else {
                    updated.accountIDs.removeAll { $0 == id }
                }
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private func panelSectionBinding(_ section: MenuBarConfiguration.PanelSection) -> Binding<Bool> {
        Binding(
            get: { configuration.visiblePanelSections.contains(section) },
            set: { isVisible in
                let currentlyVisible = configuration.visiblePanelSections
                if !isVisible && currentlyVisible.count == 1 && currentlyVisible.first == section {
                    return
                }
                var updated = configuration
                var hidden = updated.hiddenPanelSections ?? []
                if isVisible {
                    hidden.remove(section)
                } else {
                    hidden.insert(section)
                }
                updated.hiddenPanelSections = hidden
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private var panelTimelineScaleBinding: Binding<MenuBarConfiguration.PanelTimelineScale> {
        Binding(
            get: { configuration.effectivePanelTimelineScale },
            set: { value in
                var updated = configuration
                updated.panelTimelineScale = value
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private var panelTimelineLimitBinding: Binding<Int> {
        Binding(
            get: { configuration.effectivePanelTimelineAccountLimit },
            set: { value in
                var updated = configuration
                updated.panelTimelineAccountLimit = value
                model.updateMenuBarConfiguration(updated)
            }
        )
    }

    private func movePanelSection(
        _ section: MenuBarConfiguration.PanelSection,
        offset: Int
    ) {
        var order = configuration.orderedPanelSections
        guard let index = order.firstIndex(of: section) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        var updated = configuration
        updated.panelSectionOrder = order
        model.updateMenuBarConfiguration(updated)
    }

    private func panelSectionTitle(_ section: MenuBarConfiguration.PanelSection) -> String {
        switch section {
        case .aggregate: t("总额度", "Quota summary")
        case .timeline: t("配额时间线", "Quota timeline")
        case .accounts: t("账号详情", "Account details")
        }
    }

    private func panelSectionSymbol(_ section: MenuBarConfiguration.PanelSection) -> String {
        switch section {
        case .aggregate: "gauge.with.dots.needle.67percent"
        case .timeline: "calendar.day.timeline.leading"
        case .accounts: "person.text.rectangle"
        }
    }

    private func presetTitle(_ preset: MenuBarConfiguration.Preset) -> String {
        switch preset {
        case .iconOnly: t("仅图标", "Icon only")
        case .iconAndPercentage: t("图标 + 百分比", "Icon + percentage")
        case .iconAndLinearProgress: t("图标 + 进度条", "Icon + linear progress")
        case .iconLinearProgressAndPercentage: t("图标 + 进度条 + 百分比", "Icon + linear progress + percentage")
        case .progressAndPercentage: t("进度条 + 百分比", "Progress + percentage")
        case .dualQuota: t("双配额", "Dual quota")
        case .dualProgress: t("双进度条", "Dual progress bars")
        case .twoLine: t("两行", "Two-line")
        case .ring: t("圆环", "Ring")
        case .ringAndPercentage: t("圆环 + 百分比", "Ring + percentage")
        case .custom: t("自定义", "Custom")
        }
    }

    private func t(_ chinese: String, _ english: String) -> String {
        model.language.text(chinese, english)
    }
}

private struct MenuBarQuotaSummary {
    let configuration: MenuBarConfiguration
    let accounts: [AccountQuotaInfo]
    let windows: [AggregatedQuotaWindow]

    init(configuration: MenuBarConfiguration, accounts: [AccountQuotaInfo]) {
        self.configuration = configuration
        self.accounts = configuration.selectedAccounts(from: accounts)
        windows = self.accounts.aggregateQuotaWindows()
    }

    var primary: AggregatedQuotaWindow? {
        if let selectedID = configuration.primaryWindowID,
           let selected = windows.first(where: { $0.id == selectedID }) {
            return selected
        }
        return windows.first(where: { $0.isWeekly }) ?? windows.first
    }

    var spark: AggregatedQuotaWindow? {
        windows.first(where: { $0.isSpark })
    }

    var secondary: AggregatedQuotaWindow? {
        if let selectedID = configuration.secondaryWindowID,
           let selected = windows.first(where: { $0.id == selectedID && $0.id != primary?.id }) {
            return selected
        }
        return spark.flatMap { $0.id == primary?.id ? nil : $0 }
            ?? windows.first { $0.id != primary?.id }
    }

    var color: Color {
        guard configuration.scope != .allAccounts else { return .accentColor }
        return menuBarProviderColor(configuration.provider)
    }

    func title(language: AppLanguage) -> String {
        switch configuration.scope {
        case .allAccounts: language.text("全部账号", "All accounts")
        case .provider: "\(configuration.provider.displayName) · \(language.text("全部账号", "all accounts"))"
        case .accounts: language.text("所选账号", "Selected accounts")
        }
    }

    func subtitle(language: AppLanguage) -> String {
        language.text(
            "\(accounts.count) 个账号 · 同类窗口取平均",
            "\(accounts.count) accounts · matching windows averaged"
        )
    }
}

private struct MenuBarQuotaLabel: View {
    let configuration: MenuBarConfiguration
    let summary: MenuBarQuotaSummary
    let usesApplicationIconForGlobalScope: Bool

    var body: some View {
        let image = MenuBarStatusImageRenderer.render(
            configuration: configuration,
            summary: summary,
            usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
        )
        Image(nsImage: image)
            .renderingMode(.template)
            .interpolation(.high)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

private struct MenuBarPrimaryVisual: View {
    let window: AggregatedQuotaWindow?
    let color: Color
    let display: MenuBarConfiguration.Display
    var compact = false

    var body: some View {
        let percentage = window?.remainingPercentage ?? 0
        HStack(spacing: compact ? 2 : 3) {
            if display.showsPrimaryRing {
                StatusBarRingGlyph(
                    percentage: percentage,
                    size: compact ? 7 : 11
                )
            }
            if display.showsPrimaryLinearBar {
                StatusBarLinearGlyph(
                    percentage: percentage,
                    width: compact ? 19 : 25,
                    height: compact ? 3 : 4
                )
            }
            if display.showsPrimaryPercentage {
                Text(window.map { "\($0.remainingPercentage)%" } ?? "—")
                    .font(.system(
                        size: compact ? 7 : 10,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .lineLimit(1)
            }
        }
    }
}

/// SwiftUI `Shape` views can receive an unconstrained proposal when hosted by
/// `MenuBarExtra`, even when their descendants carry a frame. These AppKit
/// template images have an intrinsic point size, so the status item cannot
/// expand a ring or meter to the source asset/display height.
private struct StatusBarLinearGlyph: View {
    let percentage: Int
    var width: CGFloat = 25
    var height: CGFloat = 4

    var body: some View {
        Image(nsImage: image)
            .interpolation(.high)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private var image: NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let radius = rect.height / 2
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

            let fraction = CGFloat(max(0, min(percentage, 100))) / 100
            guard fraction > 0 else { return true }
            let fillWidth = max(rect.width * fraction, min(rect.height, rect.width))
            let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct StatusBarRingGlyph: View {
    let percentage: Int
    var size: CGFloat = 11

    var body: some View {
        Image(nsImage: image)
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var image: NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth = max(size * 0.16, 1.25)
            let ringRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)

            NSColor.labelColor.withAlphaComponent(0.24).setStroke()
            let background = NSBezierPath(ovalIn: ringRect)
            background.lineWidth = lineWidth
            background.stroke()

            let fraction = CGFloat(max(0, min(percentage, 100))) / 100
            guard fraction > 0 else { return true }
            let foreground = NSBezierPath()
            foreground.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: max((size - lineWidth) / 2, 0.5),
                startAngle: 90,
                endAngle: 90 - (360 * fraction),
                clockwise: true
            )
            foreground.lineWidth = lineWidth
            foreground.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            foreground.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct StatusBarTwoLineGlyph: View {
    let primaryLabel: String
    let primaryPercentage: Int?
    let secondaryLabel: String
    let secondaryPercentage: Int?
    let showsPrimaryLinearBar: Bool

    private let width: CGFloat = 54
    private let height: CGFloat = 16

    var body: some View {
        Image(nsImage: image)
            .interpolation(.high)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private var image: NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let font = NSFont.monospacedSystemFont(ofSize: 7, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
            let primaryText = "\(primaryLabel) \(primaryPercentage.map(String.init) ?? "—")%"
            let secondaryText = "\(secondaryLabel) \(secondaryPercentage.map(String.init) ?? "—")%"
            (primaryText as NSString).draw(
                in: NSRect(x: 0, y: 8, width: showsPrimaryLinearBar ? 31 : rect.width, height: 8),
                withAttributes: attributes
            )
            (secondaryText as NSString).draw(
                in: NSRect(x: 0, y: 0, width: rect.width, height: 8),
                withAttributes: attributes
            )

            if showsPrimaryLinearBar {
                let meterRect = NSRect(x: 34, y: 10.5, width: 19, height: 2.5)
                let radius = meterRect.height / 2
                NSColor.labelColor.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: meterRect, xRadius: radius, yRadius: radius).fill()
                let fraction = CGFloat(max(0, min(primaryPercentage ?? 0, 100))) / 100
                if fraction > 0 {
                    let filled = NSRect(
                        x: meterRect.minX,
                        y: meterRect.minY,
                        width: max(meterRect.width * fraction, meterRect.height),
                        height: meterRect.height
                    )
                    NSColor.labelColor.setFill()
                    NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Renders the complete status item into one intrinsic-size bitmap. A
/// `MenuBarExtra` label proposes different sizes than the in-app preview, so
/// no original Provider asset or child SwiftUI layout is handed to it.
private enum MenuBarStatusImageRenderer {
    private static let height: CGFloat = 18
    private static let iconSize: CGFloat = 16
    private static let spacing: CGFloat = 3
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    private enum FontRole {
        case primary
        case secondary
        case compact
    }

    private enum Element {
        case icon
        case ring(percentage: Int, size: CGFloat)
        case linear(percentage: Int, width: CGFloat, height: CGFloat)
        case text(String, FontRole)
    }

    private enum Content {
        case single([Element])
        case twoLine(top: [Element], bottom: [Element], showsIcon: Bool, iconFirst: Bool)
    }

    private struct Layout {
        let size: NSSize
        let content: Content
    }

    static func pointSize(
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary
    ) -> NSSize {
        layout(configuration: configuration, summary: summary).size
    }

    static func render(
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary,
        usesApplicationIconForGlobalScope: Bool
    ) -> NSImage {
        let resolved = layout(configuration: configuration, summary: summary)
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 2)
        let key = cacheKey(
            configuration: configuration,
            summary: summary,
            usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope,
            scale: scale
        )
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let pixelsWide = max(Int(ceil(resolved.size.width * scale)), 1)
        let pixelsHigh = max(Int(ceil(resolved.size.height * scale)), 1)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return fallbackImage()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        context.cgContext.scaleBy(x: scale, y: scale)
        context.shouldAntialias = true
        context.imageInterpolation = .high
        draw(
            resolved,
            configuration: configuration,
            summary: summary,
            usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        representation.size = resolved.size
        let image = NSImage(size: resolved.size)
        image.addRepresentation(representation)
        image.isTemplate = true
        imageCache.setObject(image, forKey: key)
        return image
    }

    private static func cacheKey(
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary,
        usesApplicationIconForGlobalScope: Bool,
        scale: CGFloat
    ) -> NSString {
        let display = configuration.display
        return [
            configuration.scope.rawValue,
            configuration.provider.rawValue,
            display.showsIcon.description,
            display.showsPrimaryPercentage.description,
            display.showsPrimaryLinearBar.description,
            display.showsPrimaryRing.description,
            display.showsSecondaryQuota.description,
            display.displaysSecondaryPercentage.description,
            display.displaysSecondaryLinearBar.description,
            display.usesTwoLines.description,
            display.elementOrder.rawValue,
            summary.primary?.id ?? "none",
            summary.primary.map { String($0.remainingPercentage) } ?? "none",
            summary.primary?.label ?? "none",
            summary.secondary?.id ?? "none",
            summary.secondary.map { String($0.remainingPercentage) } ?? "none",
            summary.secondary?.label ?? "none",
            usesApplicationIconForGlobalScope.description,
            String(format: "%.2f", scale)
        ].joined(separator: "|") as NSString
    }

    private static func layout(
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary
    ) -> Layout {
        var display = configuration.display
        if display.usesTwoLines,
           (!display.showsSecondaryQuota || summary.secondary == nil) {
            display.usesTwoLines = false
        }

        if display.usesTwoLines, let secondary = summary.secondary {
            var top: [Element] = []
            let primaryPercentage = summary.primary?.remainingPercentage ?? 0
            if display.showsPrimaryRing {
                top.append(.ring(percentage: primaryPercentage, size: 7))
            }
            if display.showsPrimaryLinearBar {
                top.append(.linear(percentage: primaryPercentage, width: 19, height: 2.5))
            }
            if display.showsPrimaryPercentage {
                let primaryText = summary.primary.map {
                    "\(shortLabel($0)) \($0.remainingPercentage)%"
                } ?? "—"
                top.append(.text(primaryText, .compact))
            }
            var bottom: [Element] = []
            if display.displaysSecondaryLinearBar {
                bottom.append(.linear(
                    percentage: secondary.remainingPercentage,
                    width: 19,
                    height: 2.5
                ))
            }
            if display.displaysSecondaryPercentage {
                bottom.append(.text(
                    "\(shortLabel(secondary)) \(secondary.remainingPercentage)%",
                    .compact
                ))
            }
            let contentWidth = max(rowWidth(top), rowWidth(bottom), 1)
            let totalWidth = display.showsIcon
                ? iconSize + spacing + contentWidth
                : contentWidth
            return Layout(
                size: NSSize(width: ceil(totalWidth), height: height),
                content: .twoLine(
                    top: top,
                    bottom: bottom,
                    showsIcon: display.showsIcon,
                    iconFirst: display.elementOrder == .iconFirst
                )
            )
        }

        var values: [Element] = []
        let primaryPercentage = summary.primary?.remainingPercentage ?? 0
        let canCombineDualText = display.displaysSecondaryPercentage
            && !display.displaysSecondaryLinearBar
            && display.showsPrimaryPercentage
            && !display.showsPrimaryLinearBar
            && !display.showsPrimaryRing
            && summary.primary != nil
            && summary.secondary != nil

        if canCombineDualText,
           let primary = summary.primary,
           let secondary = summary.secondary {
            values.append(.text(
                "\(shortLabel(primary)) \(primary.remainingPercentage)% · "
                    + "\(shortLabel(secondary)) \(secondary.remainingPercentage)%",
                .secondary
            ))
        } else {
            if display.showsPrimaryRing {
                values.append(.ring(percentage: primaryPercentage, size: 11))
            }
            if display.showsPrimaryLinearBar {
                values.append(.linear(percentage: primaryPercentage, width: 25, height: 4))
            }
            if display.showsPrimaryPercentage {
                values.append(.text(
                    summary.primary.map { "\($0.remainingPercentage)%" } ?? "—",
                    .primary
                ))
            }
            if let secondary = summary.secondary {
                if display.displaysSecondaryLinearBar {
                    values.append(.linear(
                        percentage: secondary.remainingPercentage,
                        width: 25,
                        height: 4
                    ))
                }
                if display.displaysSecondaryPercentage {
                    values.append(.text(
                        "\(shortLabel(secondary)) \(secondary.remainingPercentage)%",
                        .secondary
                    ))
                }
            }
        }

        var elements = values
        if display.showsIcon {
            if display.elementOrder == .iconFirst {
                elements.insert(.icon, at: 0)
            } else {
                elements.append(.icon)
            }
        }
        if elements.isEmpty {
            elements = [.icon]
        }
        return Layout(
            size: NSSize(width: ceil(rowWidth(elements)), height: height),
            content: .single(elements)
        )
    }

    private static func draw(
        _ layout: Layout,
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary,
        usesApplicationIconForGlobalScope: Bool
    ) {
        switch layout.content {
        case .single(let elements):
            drawRow(
                elements,
                x: 0,
                y: 0,
                rowHeight: height,
                configuration: configuration,
                summary: summary,
                usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
            )
        case .twoLine(let top, let bottom, let showsIcon, let iconFirst):
            let contentWidth = max(rowWidth(top), rowWidth(bottom), 1)
            let contentX: CGFloat
            let iconX: CGFloat
            if showsIcon && iconFirst {
                iconX = 0
                contentX = iconSize + spacing
            } else if showsIcon {
                contentX = 0
                iconX = contentWidth + spacing
            } else {
                contentX = 0
                iconX = 0
            }
            if showsIcon {
                drawIcon(
                    x: iconX,
                    y: (height - iconSize) / 2,
                    configuration: configuration,
                    summary: summary,
                    usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
                )
            }
            drawRow(
                top,
                x: contentX,
                y: 9,
                rowHeight: 9,
                configuration: configuration,
                summary: summary,
                usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
            )
            drawRow(
                bottom,
                x: contentX,
                y: 0,
                rowHeight: 9,
                configuration: configuration,
                summary: summary,
                usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
            )
        }
    }

    private static func drawRow(
        _ elements: [Element],
        x: CGFloat,
        y: CGFloat,
        rowHeight: CGFloat,
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary,
        usesApplicationIconForGlobalScope: Bool
    ) {
        var cursor = x
        for (index, element) in elements.enumerated() {
            if index > 0 { cursor += spacing }
            switch element {
            case .icon:
                drawIcon(
                    x: cursor,
                    y: y + (rowHeight - iconSize) / 2,
                    configuration: configuration,
                    summary: summary,
                    usesApplicationIconForGlobalScope: usesApplicationIconForGlobalScope
                )
            case .ring(let percentage, let size):
                drawRing(
                    percentage: percentage,
                    rect: NSRect(x: cursor, y: y + (rowHeight - size) / 2, width: size, height: size)
                )
            case .linear(let percentage, let width, let elementHeight):
                drawLinear(
                    percentage: percentage,
                    rect: NSRect(
                        x: cursor,
                        y: y + (rowHeight - elementHeight) / 2,
                        width: width,
                        height: elementHeight
                    )
                )
            case .text(let text, let role):
                drawText(text, role: role, x: cursor, y: y, rowHeight: rowHeight)
            }
            cursor += elementWidth(element)
        }
    }

    private static func drawIcon(
        x: CGFloat,
        y: CGFloat,
        configuration: MenuBarConfiguration,
        summary: MenuBarQuotaSummary,
        usesApplicationIconForGlobalScope: Bool
    ) {
        let isGlobal = configuration.scope == .allAccounts && usesApplicationIconForGlobalScope
        let source: NSImage?
        let opticalScale: CGFloat
        if isGlobal {
            source = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: nil
            )
            opticalScale = 1
        } else {
            source = NSImage(named: NSImage.Name(configuration.provider.logoAssetName))
            opticalScale = providerOpticalScale(configuration.provider)
        }
        guard let source else { return }

        let targetSize = iconSize * opticalScale
        let target = NSRect(
            x: x + (iconSize - targetSize) / 2,
            y: y + (iconSize - targetSize) / 2,
            width: targetSize,
            height: targetSize
        )
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            source.draw(in: target)
            return
        }
        let fitScale = min(target.width / sourceSize.width, target.height / sourceSize.height)
        let fitted = NSSize(width: sourceSize.width * fitScale, height: sourceSize.height * fitScale)
        let fittedRect = NSRect(
            x: target.midX - fitted.width / 2,
            y: target.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
        source.draw(
            in: fittedRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private static func drawRing(percentage: Int, rect: NSRect) {
        let lineWidth = max(rect.width * 0.16, 1.2)
        let ringRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        NSColor.black.withAlphaComponent(0.24).setStroke()
        let background = NSBezierPath(ovalIn: ringRect)
        background.lineWidth = lineWidth
        background.stroke()

        let fraction = CGFloat(max(0, min(percentage, 100))) / 100
        guard fraction > 0 else { return }
        let foreground = NSBezierPath()
        foreground.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: max((rect.width - lineWidth) / 2, 0.5),
            startAngle: 90,
            endAngle: 90 - (360 * fraction),
            clockwise: true
        )
        foreground.lineWidth = lineWidth
        foreground.lineCapStyle = .round
        NSColor.black.setStroke()
        foreground.stroke()
    }

    private static func drawLinear(percentage: Int, rect: NSRect) {
        let radius = rect.height / 2
        NSColor.black.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let fraction = CGFloat(max(0, min(percentage, 100))) / 100
        guard fraction > 0 else { return }
        let fillRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width * fraction, rect.height),
            height: rect.height
        )
        NSColor.black.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private static func drawText(
        _ text: String,
        role: FontRole,
        x: CGFloat,
        y: CGFloat,
        rowHeight: CGFloat
    ) {
        let attributes = textAttributes(role)
        let measured = (text as NSString).size(withAttributes: attributes)
        let drawHeight = min(max(measured.height, 1), rowHeight)
        (text as NSString).draw(
            in: NSRect(
                x: x,
                y: y + (rowHeight - drawHeight) / 2,
                width: ceil(measured.width) + 1,
                height: drawHeight
            ),
            withAttributes: attributes
        )
    }

    private static func rowWidth(_ elements: [Element]) -> CGFloat {
        guard !elements.isEmpty else { return 0 }
        return elements.reduce(0) { $0 + elementWidth($1) }
            + CGFloat(elements.count - 1) * spacing
    }

    private static func elementWidth(_ element: Element) -> CGFloat {
        switch element {
        case .icon: iconSize
        case .ring(_, let size): size
        case .linear(_, let width, _): width
        case .text(let text, let role):
            ceil((text as NSString).size(withAttributes: textAttributes(role)).width) + 1
        }
    }

    private static func textAttributes(_ role: FontRole) -> [NSAttributedString.Key: Any] {
        let font: NSFont
        switch role {
        case .primary:
            font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        case .secondary:
            font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        case .compact:
            font = .monospacedSystemFont(ofSize: 7, weight: .semibold)
        }
        return [
            .font: font,
            .foregroundColor: NSColor.black
        ]
    }

    private static func shortLabel(_ window: AggregatedQuotaWindow) -> String {
        if window.isSpark { return "Spark" }
        if window.isWeekly { return "7d" }
        let lowered = window.label.lowercased()
        if lowered.contains("hour") || lowered.contains("小时") { return "5h" }
        return String(window.label.prefix(8))
    }

    private static func providerOpticalScale(_ provider: ProviderType) -> CGFloat {
        switch provider {
        case .claude, .codex, .gemini, .kimi: 1
        }
    }

    private static func fallbackImage() -> NSImage {
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: nil
        ) ?? NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.size = NSSize(width: iconSize, height: iconSize)
        image.isTemplate = true
        return image
    }
}

private struct MenuBarScopeIcon: View {
    let summary: MenuBarQuotaSummary
    var usesApplicationIconForGlobalScope = true
    var size: CGFloat = 11
    var statusItem = false

    var body: some View {
        Group {
            if statusItem,
               summary.configuration.scope == .allAccounts,
               usesApplicationIconForGlobalScope {
                // NSApplication.applicationIconImage carries large AppIcon
                // representations that MenuBarExtra may host at their source
                // size. Use the logo's monochrome gauge mark for the fixed-
                // height status item instead.
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .scaleEffect(0.88)
            } else if statusItem {
                Image(summary.configuration.provider.logoAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(opticalScale)
            } else if summary.configuration.scope == .allAccounts && usesApplicationIconForGlobalScope {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProviderLogo(provider: summary.configuration.provider, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var opticalScale: CGFloat {
        switch summary.configuration.provider {
        case .codex: 0.78
        case .claude: 0.84
        case .gemini: 0.88
        case .kimi: 0.82
        }
    }
}

private struct MenuBarLinearMeter: View {
    let percentage: Int
    let color: Color
    var width: CGFloat = 30
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.22))
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(
                        width: max(width * CGFloat(max(0, min(percentage, 100))) / 100, 1.5),
                        height: height
                    )
            }
    }
}

private struct MenuBarRing: View {
    let percentage: Int
    let color: Color
    var size: CGFloat = 11

    var body: some View {
        Circle()
            .stroke(Color.secondary.opacity(0.24), lineWidth: max(size * 0.16, 1.25))
            .overlay {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(percentage, 100))) / 100)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: max(size * 0.16, 1.25), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
    }
}

private struct MenuBarAggregateRow: View {
    let window: AggregatedQuotaWindow
    let color: Color
    let language: AppLanguage
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.quotaLabel(window.label))
                    .font(prominent ? .subheadline.weight(.semibold) : .caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(window.remainingPercentage)%")
                    .font((prominent ? Font.title3 : Font.subheadline).monospacedDigit().weight(.bold))
                if let reset = window.resetTime {
                    Text(language.relativeString(for: reset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            QuotaRemainingBar(percentage: window.remainingPercentage, color: color)
            Text(language.text(
                "\(window.accountCount) 个账号的同类窗口平均 · 重置时间以最早可用时间显示",
                "Average of this window across \(window.accountCount) accounts · earliest available reset"
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct MenuBarAccountRow: View {
    let account: AccountQuotaInfo
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ProviderLogo(provider: account.provider, size: 15)
                Text(account.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(account.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(account.windows.sorted { $0.remainingPercentage < $1.remainingPercentage }.prefix(2)) { window in
                HStack(spacing: 7) {
                    Text(language.quotaLabel(window.label))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    MenuBarLinearMeter(percentage: window.remainingPercentage, color: menuBarProviderColor(account.provider))
                    Text("\(window.remainingPercentage)%")
                        .monospacedDigit()
                    if let reset = window.resetTime {
                        Text(language.relativeString(for: reset))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }
            Text(language.text("更新于 \(language.relativeString(for: account.updatedAt))", "Updated \(language.relativeString(for: account.updatedAt))"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct MenuBarQuotaTimelineSection: View {
    let accounts: [AccountQuotaInfo]
    let scale: MenuBarConfiguration.PanelTimelineScale
    let accountLimit: Int
    let language: AppLanguage
    let referenceDate: Date

    private var entries: [MenuBarTimelineEntry] {
        accounts.prefix(accountLimit).flatMap { account in
            account.windows
                .filter(scale.includes)
                .filter { $0.resetTime != nil && $0.durationSeconds != nil }
                .sorted {
                    if $0.remainingPercentage != $1.remainingPercentage {
                        return $0.remainingPercentage < $1.remainingPercentage
                    }
                    return ($0.resetTime ?? .distantFuture) < ($1.resetTime ?? .distantFuture)
                }
                .prefix(2)
                .map { MenuBarTimelineEntry(account: account, window: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(
                    language.text("配额时间线", "Quota timeline"),
                    systemImage: "calendar.day.timeline.leading"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(scale.label(language: language))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if entries.isEmpty {
                Text(language.text(
                    "当前周期没有正在计时的配额窗口。",
                    "No timed quota windows match this period."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ForEach(entries) { entry in
                    MenuBarTimelineRow(
                        entry: entry,
                        language: language,
                        referenceDate: referenceDate
                    )
                }

                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.primary.opacity(0.58))
                        .frame(width: 17, height: 5)
                    Text(language.text("深色为已用额度", "Dark fill is quota used"))
                    Rectangle()
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: 1, height: 9)
                    Text(language.text("竖线为当前时间", "Line is current time"))
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MenuBarTimelineEntry: Identifiable {
    let account: AccountQuotaInfo
    let window: QuotaWindowInfo

    var id: String { "\(account.id)-\(window.id)" }
}

private struct MenuBarTimelineRow: View {
    let entry: MenuBarTimelineEntry
    let language: AppLanguage
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProviderLogo(provider: entry.account.provider, size: 12)
                Text(entry.account.displayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(language.quotaLabel(entry.window.label))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(entry.window.remainingPercentage)%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }

            HStack(spacing: 7) {
                MenuBarTimelinePaceTrack(
                    remainingPercentage: entry.window.remainingPercentage,
                    elapsedFraction: elapsedFraction,
                    color: isOverPace ? .orange : menuBarProviderColor(entry.account.provider)
                )
                if let reset = entry.window.resetTime {
                    Text(language.relativeString(for: reset))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    }

    private var elapsedFraction: CGFloat {
        guard let reset = entry.window.resetTime,
              let duration = entry.window.durationSeconds,
              duration > 0 else { return 0 }
        let start = reset.addingTimeInterval(-duration)
        return CGFloat(min(max(referenceDate.timeIntervalSince(start) / duration, 0), 1))
    }

    private var isOverPace: Bool {
        let used = CGFloat(min(max(100 - entry.window.remainingPercentage, 0), 100)) / 100
        return used > elapsedFraction + 0.05
    }
}

private struct MenuBarTimelinePaceTrack: View {
    let remainingPercentage: Int
    let elapsedFraction: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let usedFraction = CGFloat(min(max(100 - remainingPercentage, 0), 100)) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.16))
                Capsule()
                    .fill(color.opacity(0.78))
                    .frame(width: max(proxy.size.width * usedFraction, usedFraction > 0 ? 2 : 0))
                Rectangle()
                    .fill(Color.primary.opacity(0.72))
                    .frame(width: 1.25, height: 12)
                    .offset(x: min(max(proxy.size.width * elapsedFraction - 0.6, 0), proxy.size.width - 1.25))
            }
        }
        .frame(height: 10)
    }
}

private extension MenuBarConfiguration.PanelTimelineScale {
    func includes(_ window: QuotaWindowInfo) -> Bool {
        guard let duration = window.durationSeconds, duration > 0 else { return false }
        switch self {
        case .weekly: return duration >= 6 * 24 * 3_600 && duration <= 8 * 24 * 3_600
        case .fiveHour: return duration >= 4 * 3_600 && duration <= 6 * 3_600
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .weekly: language.text("按周", "Weekly")
        case .fiveHour: language.text("5 小时", "5-hour")
        }
    }
}

private func menuBarProviderColor(_ provider: ProviderType) -> Color {
    switch provider {
    case .claude: .orange
    case .codex: .indigo
    case .gemini: .teal
    case .kimi: .blue
    }
}
