import Foundation

struct CacheStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var cacheURL: URL {
        AppSettingsStore.sharedContainerURL(fileManager: fileManager)
            .appendingPathComponent("quota.json", isDirectory: false)
    }

    private var accountCacheURL: URL {
        AppSettingsStore.sharedContainerURL(fileManager: fileManager)
            .appendingPathComponent("account-quota.json", isDirectory: false)
    }

    private var statusURL: URL {
        AppSettingsStore.sharedContainerURL(fileManager: fileManager)
            .appendingPathComponent("status.txt", isDirectory: false)
    }

    func saveQuota(_ quota: [QuotaInfo]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(quota)

        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: cacheURL, options: .atomic)
    }

    func loadQuota() -> [QuotaInfo] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([QuotaInfo].self, from: data)) ?? []
    }

    func clearQuota() throws {
        try saveQuota([])
        try saveAccountQuota([])
    }

    func saveAccountQuota(_ accounts: [AccountQuotaInfo]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(accounts)

        let directory = accountCacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: accountCacheURL, options: .atomic)
    }

    func loadAccountQuota() -> [AccountQuotaInfo] {
        guard let data = try? Data(contentsOf: accountCacheURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AccountQuotaInfo].self, from: data)) ?? []
    }

    func saveStatus(_ status: CacheStatus) {
        let directory = statusURL.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? Data(status.rawValue.utf8).write(to: statusURL, options: .atomic)
    }

    func loadStatus() -> CacheStatus {
        guard let data = try? Data(contentsOf: statusURL),
              let rawValue = String(data: data, encoding: .utf8),
              let status = CacheStatus(rawValue: rawValue) else {
            return loadAccountQuota().isEmpty && loadQuota().isEmpty ? .noData : .fresh
        }
        return status
    }
}
