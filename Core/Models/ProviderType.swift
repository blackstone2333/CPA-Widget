import Foundation

enum ProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini
    case kimi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Antigravity"
        case .kimi: "Kimi"
        }
    }

    var logoAssetName: String {
        switch self {
        case .claude: "ClaudeLogo"
        case .codex: "CodexLogo"
        case .gemini: "AntigravityLogo"
        case .kimi: "KimiLogo"
        }
    }

    var sortOrder: Int {
        switch self {
        case .claude: 0
        case .codex: 1
        case .gemini: 2
        case .kimi: 3
        }
    }
}
