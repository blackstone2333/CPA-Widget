import AppIntents
import notify

struct RefreshQuotaIntent: AppIntent {
    static let title: LocalizedStringResource = "刷新 CPA 配额 / Refresh CPA Quota"
    static let description = IntentDescription(
        "在后台请求 CPA Widget 主应用刷新配额。/ Ask the CPA Widget host app to refresh quota in the background."
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        notify_post(WidgetRefreshRequest.notificationName)
        return .result()
    }
}
