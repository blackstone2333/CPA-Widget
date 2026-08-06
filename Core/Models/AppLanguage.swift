import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }

    var locale: Locale {
        switch self {
        case .simplifiedChinese: Locale(identifier: "zh_Hans_CN")
        case .english: Locale(identifier: "en_US")
        }
    }

    func relativeString(for date: Date, relativeTo referenceDate: Date = Date()) -> String {
        if abs(date.timeIntervalSince(referenceDate)) < 2 {
            return text("刚刚", "now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    func dateTimeString(for date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(locale)
        )
    }

    func quotaLabel(_ label: String) -> String {
        guard self == .simplifiedChinese else { return label }

        let replacements = [
            "Weekly Limit": "周限额",
            "5-hour Limit": "5 小时限额",
            "Seven-day Limit": "7 天限额",
            "Monthly Limit": "月限额",
            "Secondary Quota": "次级配额",
            "Gemini Models": "Gemini 模型",
            "Claude & GPT Models": "Claude 和 GPT 模型",
            "Quota": "配额"
        ]
        if let translated = replacements[label] { return translated }

        for (english, chinese) in replacements where label.hasSuffix(" \(english)") {
            return String(label.dropLast(english.count)) + chinese
        }
        return label
    }
}
