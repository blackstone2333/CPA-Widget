import Combine
import Foundation
import OSLog
import ServiceManagement
import WidgetKit
import notify

@MainActor
final class AppModel: ObservableObject {
    @Published var endpoint: String
    @Published var managementSecret: String
    @Published var enabledProviders: Set<ProviderType>
    @Published var refreshInterval: TimeInterval
    @Published var useMockData: Bool
    @Published var language: AppLanguage
    @Published private(set) var menuBarConfiguration: MenuBarConfiguration
    @Published private(set) var quota: [QuotaInfo]
    @Published private(set) var accountQuota: [AccountQuotaInfo]
    @Published private(set) var cacheStatus: CacheStatus
    @Published private(set) var statusMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isTestingConnection = false
    @Published private(set) var menuBarSettingsRequest = 0

    let refreshOptions: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60]
    var usesRemotePlainHTTP: Bool {
        guard let components = URLComponents(
            string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        ), components.scheme?.lowercased() == "http",
           let host = components.host?.lowercased() else {
            return false
        }
        return !["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private let settingsStore = AppSettingsStore()
    private let keychain = KeychainManager()
    private let cacheStore = CacheStore()
    private let connectionService = ConnectionService()
    private let refreshService = RefreshService()
    private let logger = Logger(subsystem: "com.cpawidget.app", category: "Refresh")
    private var hasLaunched = false
    private var widgetRefreshNotificationToken: Int32 = -1
    private var persistedManagementSecret = ""

    init() {
        let storedProviders = settingsStore.enabledProviders
        let storedMenuBarConfiguration = settingsStore.menuBarConfiguration
        menuBarConfiguration = storedMenuBarConfiguration
        let storedEndpoint = settingsStore.endpoint
        let endpointValue = storedEndpoint
            ?? (try? keychain.read(.endpoint))
            ?? "http://localhost:8317"
        let secretValue = (try? keychain.read(.managementSecret)) ?? ""
        endpoint = endpointValue
        managementSecret = secretValue
        persistedManagementSecret = secretValue
        if storedEndpoint == nil {
            settingsStore.endpoint = endpointValue
        }
        enabledProviders = storedProviders
        refreshInterval = settingsStore.refreshInterval
        useMockData = settingsStore.useMockData
        language = settingsStore.language
        quota = cacheStore.loadQuota().filter {
            storedProviders.contains($0.provider)
        }
        accountQuota = cacheStore.loadAccountQuota().filter {
            storedProviders.contains($0.provider)
        }
        cacheStatus = cacheStore.loadStatus()
    }

    deinit {
        if widgetRefreshNotificationToken >= 0 {
            notify_cancel(widgetRefreshNotificationToken)
        }
    }

    func launch() async {
        guard !hasLaunched else { return }
        hasLaunched = true
        registerForWidgetRefreshRequests()
        registerForAutomaticLaunchIfNeeded()
        await refreshQuota()
        startAutomaticRefresh()
    }

    func setProvider(_ provider: ProviderType, enabled: Bool) {
        if enabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
        quota = cacheStore.loadQuota().filter {
            enabledProviders.contains($0.provider)
        }
        accountQuota = cacheStore.loadAccountQuota().filter {
            enabledProviders.contains($0.provider)
        }
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        settingsStore.language = newLanguage
        statusMessage = newLanguage.text("语言已切换。", "Language changed.")
        reloadWidgetTimelines()
    }

    func updateMenuBarConfiguration(_ configuration: MenuBarConfiguration) {
        menuBarConfiguration = configuration
        settingsStore.saveMenuBarConfiguration(configuration)
    }

    func requestMenuBarSettings() {
        menuBarSettingsRequest &+= 1
    }

    func saveSettings(restartAutomaticRefresh: Bool = true) {
        do {
            settingsStore.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if managementSecret != persistedManagementSecret {
                try keychain.save(managementSecret, for: .managementSecret)
                persistedManagementSecret = managementSecret
            }
            settingsStore.enabledProviders = enabledProviders
            settingsStore.refreshInterval = refreshInterval
            settingsStore.useMockData = useMockData
            settingsStore.language = language
            settingsStore.warnsAboutInsecureHTTP = usesRemotePlainHTTP
            quota = cacheStore.loadQuota().filter {
                enabledProviders.contains($0.provider)
            }
            accountQuota = cacheStore.loadAccountQuota().filter {
                enabledProviders.contains($0.provider)
            }
            try cacheStore.saveQuota(quota)
            try cacheStore.saveAccountQuota(accountQuota)
            statusMessage = language.text("设置已保存。", "Settings saved.")
            if restartAutomaticRefresh {
                startAutomaticRefresh()
            }
            reloadWidgetTimelines()
        } catch {
            statusMessage = localizedError(error)
        }
    }

    func refreshQuota() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        saveSettings(restartAutomaticRefresh: false)
        let manager = makeQuotaManager()
        do {
            try await manager.refresh()
            quota = manager.getCachedQuota()
            accountQuota = manager.getCachedAccountQuota()
            cacheStatus = cacheStore.loadStatus()
            statusMessage = cacheStatus == .fresh
                ? language.text("配额已刷新。", "Quota refreshed.")
                : cacheStatus.displayMessage(language: language)
            reloadWidgetTimelines()
        } catch {
            quota = cacheStore.loadQuota().filter {
                enabledProviders.contains($0.provider)
            }
            accountQuota = cacheStore.loadAccountQuota().filter {
                enabledProviders.contains($0.provider)
            }
            cacheStatus = cacheStore.loadStatus()
            statusMessage = localizedError(error)
            reloadWidgetTimelines()
        }
    }

    func testConnection() async {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let accountCount = try await connectionService.testEndpoint(
                endpoint,
                managementSecret: managementSecret
            )
            statusMessage = language.text(
                "连接成功，共发现 \(accountCount) 个账号。",
                "Connected to the Management API (\(accountCount) account\(accountCount == 1 ? "" : "s"))."
            )
        } catch {
            statusMessage = localizedError(error)
        }
    }

    func refreshLabel(for interval: TimeInterval) -> String {
        language.text("\(Int(interval / 60)) 分钟", "\(Int(interval / 60)) min")
    }

    private func makeQuotaManager() -> QuotaManager {
        QuotaManager(
            enabledProviders: enabledProviders,
            useMockData: useMockData,
            endpoint: endpoint,
            managementSecret: managementSecret,
            cacheStore: cacheStore
        )
    }

    private func startAutomaticRefresh() {
        refreshService.start(interval: refreshInterval) { [weak self] in
            await self?.refreshQuota()
        }
    }

    private func registerForAutomaticLaunchIfNeeded() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        try? service.register()
    }

    private func registerForWidgetRefreshRequests() {
        let status = notify_register_dispatch(
            WidgetRefreshRequest.notificationName,
            &widgetRefreshNotificationToken,
            .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logger.info("Widget refresh request received")
                await self?.refreshQuota()
            }
        }
        logger.info("Widget refresh notification registration status: \(status)")
        if status != NOTIFY_STATUS_OK {
            widgetRefreshNotificationToken = -1
        }
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "CPAAccountQuotaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "CPAConfigurableAccountQuotaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "CPAQuotaTimelineWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "CPAConfigurableQuotaTimelineWidget")
    }

    private func localizedError(_ error: Error) -> String {
        guard language == .simplifiedChinese,
              let providerError = error as? QuotaProviderError else {
            return error.localizedDescription
        }

        return switch providerError {
        case .invalidConfiguration(let message): "配置无效：\(message)"
        case .adapterNotConfigured(let provider): "\(provider.displayName) 配额适配器尚未配置。"
        case .authenticationFailed: "管理密钥或账号令牌无效。"
        case .offline(let message): "无法连接 CLIProxyAPI：\(message)"
        case .invalidResponse(let message): "配额响应无效：\(message)"
        case .noProvidersEnabled: "请至少启用一个 Provider。"
        }
    }
}
