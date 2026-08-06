import Foundation

enum CacheStatus: String, Codable, Sendable {
    case fresh
    case partial
    case offline
    case authenticationFailed
    case configurationRequired
    case noData

    var displayMessage: String {
        switch self {
        case .fresh: "Up to date"
        case .partial: "Some providers unavailable"
        case .offline: "Offline"
        case .authenticationFailed: "Invalid Token"
        case .configurationRequired: "Configuration Required"
        case .noData: "No quota data"
        }
    }

    func displayMessage(language: AppLanguage) -> String {
        switch self {
        case .fresh: language.text("已是最新", "Up to date")
        case .partial: language.text("部分账号不可用", "Some accounts unavailable")
        case .offline: language.text("无法连接", "Offline")
        case .authenticationFailed: language.text("密钥无效", "Invalid Token")
        case .configurationRequired: language.text("需要配置", "Configuration Required")
        case .noData: language.text("暂无配额数据", "No quota data")
        }
    }
}
