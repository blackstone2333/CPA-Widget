import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var timelineScope: QuotaWindowScale = .weekly
    @State private var showsConnectionSettings = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    providerBar
                    accountSection
                    timelineSection
                    MenuBarConfigurationEditor()
                        .id("menu-bar-settings")
                    connectionSection
                }
                .padding(28)
            }
            .onChange(of: model.menuBarSettingsRequest) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("menu-bar-settings", anchor: .center)
                }
            }
            .onAppear {
                guard model.menuBarSettingsRequest > 0 else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo("menu-bar-settings", anchor: .center)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(t("CPA 配额管理", "CPA Quota Center"))
                    .font(.title2.weight(.semibold))
                Text(t(
                    "按账号查看 CLIProxyAPI 的实时配额与重置窗口",
                    "Live CLIProxyAPI quota and reset windows by account"
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { model.language },
                set: { model.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 128)

            Button {
                Task { await model.refreshQuota() }
            } label: {
                Label(
                    t("刷新全部账号", "Refresh Accounts"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRefreshing || model.enabledProviders.isEmpty)
        }
    }

    private var providerBar: some View {
        HStack(spacing: 10) {
            Label(
                t("已加载 \(model.accountQuota.count) 个账号", "\(model.accountQuota.count) accounts loaded"),
                systemImage: model.cacheStatus == .fresh
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(model.cacheStatus == .fresh ? .green : .orange)

            Divider().frame(height: 24)

            Label(
                t(
                    "每 \(Int(model.refreshInterval / 60)) 分钟自动刷新",
                    "Auto-refresh every \(Int(model.refreshInterval / 60)) min"
                ),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider().frame(height: 24)

            ForEach(ProviderType.allCases) { provider in
                ProviderToggleChip(
                    provider: provider,
                    isEnabled: model.enabledProviders.contains(provider),
                    language: model.language
                ) {
                    model.setProvider(
                        provider,
                        enabled: !model.enabledProviders.contains(provider)
                    )
                    model.saveSettings()
                }
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(t("正在刷新配额", "Refreshing quota"))
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                t("账号配额", "Account Quota"),
                subtitle: t("每张卡片对应一个认证账号，不合并、不平均", "One card per credential; no merging or averaging"),
                symbol: "person.text.rectangle"
            )

            if model.accountQuota.isEmpty {
                ContentUnavailableView(
                    model.cacheStatus.displayMessage(language: model.language),
                    systemImage: emptyStateSymbol,
                    description: Text(t(
                        "请展开连接设置并刷新配额。",
                        "Open connection settings, then refresh quota."
                    ))
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 350), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(model.accountQuota) { account in
                        AccountQuotaCard(account: account, language: model.language)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                sectionHeader(
                    t("配额窗口", "Quota Windows"),
                    subtitle: t(
                        "与管理中心一致：完整窗口、当前时间线和相邻周期",
                        "Management Center-style windows, current time, and adjacent cycles"
                    ),
                    symbol: "calendar.day.timeline.leading"
                )

                Spacer()

                Picker("", selection: $timelineScope) {
                    ForEach(QuotaWindowScale.allCases) { scope in
                        Text(scope.label(language: model.language)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                QuotaWindowTimelineView(
                    accounts: model.accountQuota,
                    scale: timelineScope,
                    language: model.language,
                    referenceDate: context.date
                )
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsConnectionSettings.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label(
                        t("连接与显示设置", "Connection & Display Settings"),
                        systemImage: "gearshape"
                    )
                    .font(.headline)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsConnectionSettings ? 90 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                t("连接与显示设置", "Connection & Display Settings")
            )
            .accessibilityValue(
                showsConnectionSettings
                    ? t("已展开", "Expanded")
                    : t("已收起", "Collapsed")
            )

            if showsConnectionSettings {
                VStack(alignment: .leading, spacing: 16) {
                Divider()

                LabeledContent(t("CLIProxyAPI 地址", "CLIProxyAPI Endpoint")) {
                    TextField("http://localhost:8317", text: $model.endpoint)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                }

                LabeledContent(t("管理密钥", "Management Key")) {
                    SecureField(t("管理密钥", "Management key"), text: $model.managementSecret)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                }

                HStack {
                    Button {
                        Task { await model.testConnection() }
                    } label: {
                        Label(t("测试连接", "Test Connection"), systemImage: "network")
                    }
                    .disabled(model.isTestingConnection)

                    Picker(t("刷新间隔", "Refresh Interval"), selection: $model.refreshInterval) {
                        ForEach(model.refreshOptions, id: \.self) { interval in
                            Text(model.refreshLabel(for: interval)).tag(interval)
                        }
                    }
                    .frame(width: 220)

                    Toggle(t("示例数据", "Sample Data"), isOn: $model.useMockData)

                    Spacer()

                    Button(t("保存设置", "Save Settings")) {
                        model.saveSettings()
                    }
                }

                if model.usesRemotePlainHTTP {
                    Label(
                        t(
                            "当前公网 HTTP 会明文传输管理密钥，建议改用 HTTPS。",
                            "Public HTTP sends the Management Key without encryption. Prefer HTTPS."
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if let message = model.statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(
        _ title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private func t(_ chinese: String, _ english: String) -> String {
        model.language.text(chinese, english)
    }
}

private struct ProviderToggleChip: View {
    let provider: ProviderType
    let isEnabled: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ProviderLogo(provider: provider, size: 16)
                Text(provider == .gemini
                    ? language.text("Antigravity", "Antigravity")
                    : provider.displayName)
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .background(
                isEnabled ? Color.accentColor.opacity(0.14) : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text(
            "\(provider.displayName) \(isEnabled ? "已启用" : "未启用")",
            "\(provider.displayName) \(isEnabled ? "enabled" : "disabled")"
        ))
    }
}

private struct AccountQuotaCard: View {
    let account: AccountQuotaInfo
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ProviderLogo(provider: account.provider, size: 20)
                    .frame(width: 28, height: 28)
                    .background(providerColor(account.provider).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 7) {
                        Text(account.provider.displayName)
                        if let plan = account.planName {
                            Text(plan.uppercased())
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(account.mostConstrainedPercentage)%")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(account.mostConstrainedPercentage < 20 ? .orange : .primary)
            }

            ForEach(displayedWindows) { window in
                QuotaWindowRow(window: window, provider: account.provider, language: language)
            }

            HStack {
                Text(language.text("更新于", "Updated"))
                Text(language.relativeString(for: account.updatedAt))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(providerColor(account.provider).opacity(0.15), lineWidth: 1)
        }
    }

    private var displayedWindows: [QuotaWindowInfo] {
        account.windows
            .sorted { $0.remainingPercentage < $1.remainingPercentage }
            .prefix(5)
            .map { $0 }
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindowInfo
    let provider: ProviderType
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.quotaLabel(window.label))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(window.remainingPercentage)%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if let reset = window.resetTime {
                    Text(language.relativeString(for: reset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            QuotaRemainingBar(
                percentage: window.remainingPercentage,
                color: window.remainingPercentage < 20 ? .orange : providerColor(provider)
            )
        }
    }
}

private func providerColor(_ provider: ProviderType) -> Color {
    switch provider {
    case .claude: .orange
    case .codex: .indigo
    case .gemini: .teal
    case .kimi: .blue
    }
}
