import CryptoKit
import Foundation

/// Reads account metadata from CLIProxyAPI's Management API and asks
/// CLIProxyAPI to perform credential-scoped upstream quota requests. OAuth
/// tokens never leave CLIProxyAPI: `$TOKEN$` is substituted server-side.
actor CLIProxyAPIQuotaClient: QuotaFetchingClient {
    private let endpoint: URL
    private let managementSecret: String
    private let session: URLSession

    private var authFiles: [AuthFile]?
    private var authFilesTask: Task<[AuthFile], Error>?

    init(
        endpoint: URL,
        managementSecret: String,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.managementSecret = managementSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func testConnection() async throws -> Int {
        try await loadAuthFiles().count
    }

    func fetchAccountQuotas(for provider: ProviderType) async throws -> [AccountQuotaInfo] {
        let accounts = try await loadAuthFiles().filter {
            !$0.disabled && $0.authIndex != nil
                && $0.supportsSubscriptionQuota && $0.matches(provider)
        }

        guard !accounts.isEmpty else {
            throw QuotaProviderError.invalidConfiguration(
                "No enabled \(provider.displayName) accounts were found in CLIProxyAPI."
            )
        }

        var snapshots: [AccountQuotaInfo] = []
        var failures: [QuotaProviderError] = []

        // Account calls are intentionally serialized. The Management API owns
        // token refresh and some deployments enforce a low api-call concurrency.
        for (index, account) in accounts.enumerated() {
            do {
                let snapshot = try await fetchAccountSnapshot(account, provider: provider)
                snapshots.append(AccountQuotaInfo(
                    id: Self.stableAccountID(provider: provider, authIndex: account.authIndex),
                    provider: provider,
                    displayName: account.displayName(
                        fallback: "\(provider.displayName) Account \(index + 1)"
                    ),
                    planName: snapshot.planName ?? account.planName,
                    windows: snapshot.windows.map { window in
                        QuotaWindowInfo(
                            id: "\(provider.rawValue)-\(window.id)",
                            label: window.label,
                            remainingPercentage: Int(window.remainingPercentage.rounded()),
                            resetTime: window.resetTime,
                            durationSeconds: window.durationSeconds
                        )
                    },
                    updatedAt: Date()
                ))
            } catch let error as QuotaProviderError {
                failures.append(error)
            } catch {
                failures.append(.offline(error.localizedDescription))
            }
        }

        guard !snapshots.isEmpty else {
            if failures.contains(where: { $0.isAuthenticationFailure }) {
                throw QuotaProviderError.authenticationFailed
            }
            throw failures.first ?? QuotaProviderError.invalidResponse(
                "No usable \(provider.displayName) quota response"
            )
        }

        return snapshots
    }

    private func loadAuthFiles() async throws -> [AuthFile] {
        if let authFiles { return authFiles }
        if let authFilesTask { return try await authFilesTask.value }

        let endpoint = endpoint
        let managementSecret = managementSecret
        let session = session
        let task = Task {
            try await Self.requestAuthFiles(
                endpoint: endpoint,
                managementSecret: managementSecret,
                session: session
            )
        }
        authFilesTask = task

        do {
            let files = try await task.value
            authFiles = files
            authFilesTask = nil
            return files
        } catch {
            authFilesTask = nil
            throw error
        }
    }

    private static func requestAuthFiles(
        endpoint: URL,
        managementSecret: String,
        session: URLSession
    ) async throws -> [AuthFile] {
        guard !managementSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuotaProviderError.invalidConfiguration("Management Key is required.")
        }

        let url = try managementURL(endpoint: endpoint, path: "auth-files")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(managementSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request, session: session)
        do {
            return try JSONDecoder().decode(AuthFilesResponse.self, from: data).files
        } catch {
            throw QuotaProviderError.invalidResponse("Invalid /auth-files response")
        }
    }

    private func fetchAccountSnapshot(
        _ account: AuthFile,
        provider: ProviderType
    ) async throws -> AccountQuota {
        guard let authIndex = account.authIndex else {
            throw QuotaProviderError.invalidConfiguration("Missing auth_index")
        }

        let windows: [QuotaWindow]
        var planName = account.planName
        switch provider {
        case .claude:
            let response = try await callUpstream(
                authIndex: authIndex,
                method: "GET",
                url: "https://api.anthropic.com/api/oauth/usage",
                headers: [
                    "Authorization": "Bearer $TOKEN$",
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "anthropic-beta": "oauth-2025-04-20"
                ]
            )
            windows = try quotaWindows(
                from: response,
                parser: Self.parseClaudeQuota
            )

        case .codex:
            var headers = [
                "Authorization": "Bearer $TOKEN$",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal"
            ]
            if let accountID = account.idToken?.chatgptAccountID {
                headers["Chatgpt-Account-Id"] = accountID
            }
            let response = try await callUpstream(
                authIndex: authIndex,
                method: "GET",
                url: "https://chatgpt.com/backend-api/wham/usage",
                headers: headers
            )
            windows = try quotaWindows(
                from: response,
                parser: Self.parseCodexQuota
            )
            if let object = try? Self.jsonObject(response.body) {
                planName = Self.string(object["plan_type"] ?? object["planType"])
                    ?? planName
            }

        case .gemini:
            if account.isAntigravity {
                windows = try await fetchAntigravityQuota(
                    authIndex: authIndex,
                    projectID: account.projectID
                )
            } else {
                let projectID = try await resolveGeminiProjectID(
                    account.projectID,
                    authIndex: authIndex
                )
                let body = try Self.jsonString(
                    projectID.map { ["project": $0] } ?? [:]
                )
                let response = try await callUpstream(
                    authIndex: authIndex,
                    method: "POST",
                    url: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
                    headers: [
                        "Authorization": "Bearer $TOKEN$",
                        "Content-Type": "application/json"
                    ],
                    body: body
                )
                windows = try quotaWindows(
                    from: response,
                    parser: Self.parseGeminiQuota
                )
            }

        case .kimi:
            let response = try await callUpstream(
                authIndex: authIndex,
                method: "GET",
                url: "https://api.kimi.com/coding/v1/usages",
                headers: [
                    "Authorization": "Bearer $TOKEN$"
                ]
            )
            windows = try quotaWindows(
                from: response,
                parser: Self.parseKimiQuota
            )
        }

        guard !windows.isEmpty else {
            throw QuotaProviderError.invalidResponse(
                "No quota windows returned for \(provider.displayName)"
            )
        }

        return AccountQuota(
            windows: windows,
            planName: planName
        )
    }

    private func fetchAntigravityQuota(
        authIndex: String,
        projectID: String?
    ) async throws -> [QuotaWindow] {
        let endpoints = [
            "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
            "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:retrieveUserQuotaSummary",
            "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
            "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
            "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
            "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
        ]
        let body = try Self.jsonString(["project": projectID ?? ""])
        var lastError: QuotaProviderError?

        for upstreamURL in endpoints {
            do {
                let response = try await callUpstream(
                    authIndex: authIndex,
                    method: "POST",
                    url: upstreamURL,
                    headers: [
                        "Authorization": "Bearer $TOKEN$",
                        "Content-Type": "application/json",
                        "User-Agent": "antigravity/1.11.5 windows/amd64"
                    ],
                    body: body
                )
                return try quotaWindows(
                    from: response,
                    parser: Self.parseAntigravityQuota
                )
            } catch let error as QuotaProviderError {
                lastError = error
            } catch {
                lastError = .offline(error.localizedDescription)
            }
        }

        throw lastError ?? QuotaProviderError.invalidResponse(
            "No usable Antigravity quota response"
        )
    }

    private func resolveGeminiProjectID(
        _ existing: String?,
        authIndex: String
    ) async throws -> String? {
        if let existing = existing?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        let metadata: [String: String] = [
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI"
        ]
        let response = try await callUpstream(
            authIndex: authIndex,
            method: "POST",
            url: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
            headers: [
                "Authorization": "Bearer $TOKEN$",
                "Content-Type": "application/json"
            ],
            body: try Self.jsonString(["metadata": metadata])
        )

        guard (200..<300).contains(response.statusCode),
              let object = try? Self.jsonObject(response.body) else {
            return nil
        }

        if let project = Self.string(object["cloudaicompanionProject"]) {
            return project
        }
        if let project = object["cloudaicompanionProject"] as? [String: Any] {
            return Self.string(project["id"] ?? project["projectId"])
        }
        return nil
    }

    private func callUpstream(
        authIndex: String,
        method: String,
        url: String,
        headers: [String: String],
        body: String? = nil
    ) async throws -> APICallResponse {
        let managementURL = try Self.managementURL(
            endpoint: endpoint,
            path: "api-call"
        )
        let payload = APICallRequest(
            authIndex: authIndex,
            method: method,
            url: url,
            header: headers,
            data: body
        )

        var request = URLRequest(url: managementURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("Bearer \(managementSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await Self.perform(request, session: session)
        do {
            return try JSONDecoder().decode(APICallResponse.self, from: data)
        } catch {
            throw QuotaProviderError.invalidResponse("Invalid /api-call response")
        }
    }

    private func quotaWindows(
        from response: APICallResponse,
        parser: (String) throws -> [QuotaWindow]
    ) throws -> [QuotaWindow] {
        if let windows = try? parser(response.body), !windows.isEmpty {
            return windows
        }

        switch response.statusCode {
        case 401, 403:
            throw QuotaProviderError.authenticationFailed
        case 429:
            return [QuotaWindow(
                id: "rate-limit",
                label: "Quota",
                remainingPercentage: 0,
                resetTime: Self.retryDate(from: response.header),
                durationSeconds: nil
            )]
        case 500...599:
            throw QuotaProviderError.offline("Upstream HTTP \(response.statusCode)")
        default:
            throw QuotaProviderError.invalidResponse(
                "Upstream HTTP \(response.statusCode)"
            )
        }
    }

    private static func perform(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw QuotaProviderError.invalidResponse("Non-HTTP response")
            }

            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw QuotaProviderError.authenticationFailed
            case 404:
                throw QuotaProviderError.invalidConfiguration(
                    "CLIProxyAPI Management API is unavailable. Configure remote-management.secret-key."
                )
            case 500...599:
                throw QuotaProviderError.offline("HTTP \(http.statusCode)")
            default:
                throw QuotaProviderError.invalidResponse("HTTP \(http.statusCode)")
            }
        } catch let error as QuotaProviderError {
            throw error
        } catch {
            throw QuotaProviderError.offline(error.localizedDescription)
        }
    }

    private static func managementURL(endpoint: URL, path: String) throws -> URL {
        guard let scheme = endpoint.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              endpoint.host != nil,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw QuotaProviderError.invalidConfiguration(
                "Enter a valid HTTP(S) CLIProxyAPI Endpoint."
            )
        }

        let base = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let managementPath: String
        if base.lowercased().hasSuffix("v0/management") {
            managementPath = base
        } else {
            managementPath = [base, "v0/management"]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        }
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [managementPath, suffix]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw QuotaProviderError.invalidConfiguration("Invalid Management API URL.")
        }
        return url
    }

    private static func parseClaudeQuota(_ body: String) throws -> [QuotaWindow] {
        let object = try jsonObject(body)
        let definitions: [(key: String, label: String, duration: TimeInterval)] = [
            ("five_hour", "5-hour Limit", 5 * 3_600),
            ("seven_day", "Weekly Limit", 7 * 24 * 3_600),
            ("seven_day_oauth_apps", "OAuth Apps Weekly Limit", 7 * 24 * 3_600),
            ("seven_day_opus", "Opus Weekly Limit", 7 * 24 * 3_600),
            ("seven_day_sonnet", "Sonnet Weekly Limit", 7 * 24 * 3_600),
            ("seven_day_cowork", "Cowork Weekly Limit", 7 * 24 * 3_600),
            ("iguana_necktie", "Iguana Necktie", 7 * 24 * 3_600)
        ]
        return definitions.compactMap { definition in
            let key = definition.key
            guard let usage = object[key] as? [String: Any],
                  let utilization = double(usage["utilization"]) else {
                return nil
            }
            return QuotaWindow(
                id: key,
                label: definition.label,
                remainingPercentage: clamp(100 - utilization),
                resetTime: date(usage["resets_at"]),
                durationSeconds: definition.duration
            )
        }
    }

    private static func parseCodexQuota(_ body: String) throws -> [QuotaWindow] {
        let object = try jsonObject(body)
        var windows: [QuotaWindow] = []

        if let rateLimit = dictionary(object["rate_limit"] ?? object["rateLimit"]) {
            windows += codexWindows(
                rateLimit: rateLimit,
                idPrefix: "codex",
                namePrefix: nil
            )
        }

        if let additional = (object["additional_rate_limits"]
            ?? object["additionalRateLimits"]) as? [[String: Any]] {
            for (index, entry) in additional.enumerated() {
                guard let rateLimit = dictionary(entry["rate_limit"] ?? entry["rateLimit"]) else {
                    continue
                }
                let name = string(
                    entry["limit_name"] ?? entry["limitName"]
                        ?? entry["metered_feature"] ?? entry["meteredFeature"]
                ) ?? "Additional \(index + 1)"
                windows += codexWindows(
                    rateLimit: rateLimit,
                    idPrefix: "additional-\(index)",
                    namePrefix: name
                )
            }
        }

        return windows
    }

    private static func parseGeminiQuota(_ body: String) throws -> [QuotaWindow] {
        let object = try jsonObject(body)
        guard let buckets = object["buckets"] as? [[String: Any]] else { return [] }

        return buckets.compactMap { bucket in
            guard let fraction = double(
                bucket["remainingFraction"] ?? bucket["remaining_fraction"]
            ) else { return nil }
            return QuotaWindow(
                id: string(bucket["modelId"] ?? bucket["model_id"]) ?? UUID().uuidString,
                label: string(bucket["modelId"] ?? bucket["model_id"]) ?? "Gemini Quota",
                remainingPercentage: clamp(fraction * 100),
                resetTime: date(bucket["resetTime"] ?? bucket["reset_time"]),
                durationSeconds: nil
            )
        }
    }

    private static func parseAntigravityQuota(_ body: String) throws -> [QuotaWindow] {
        let object = try jsonObject(body)
        if let groups = object["groups"] as? [[String: Any]] {
            let windows = antigravitySummaryWindows(groups)
            if !windows.isEmpty { return windows }
        }

        guard let models = object["models"] as? [String: Any] else { return [] }

        return antigravityModelWindows(models)
    }

    private static func antigravitySummaryWindows(
        _ groups: [[String: Any]]
    ) -> [QuotaWindow] {
        var entries: [String: [(remaining: Double, resetTime: Date?, duration: TimeInterval?)]] = [:]

        for group in groups {
            guard let kind = antigravityGroupKind(group) else { continue }
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }

            for bucket in buckets {
                guard let fraction = quotaFraction(
                    bucket["remainingFraction"] ?? bucket["remaining_fraction"]
                ) else {
                    continue
                }
                entries[kind, default: []].append((
                    remaining: clamp(fraction * 100),
                    resetTime: date(bucket["resetTime"] ?? bucket["reset_time"]),
                    duration: antigravityDuration(bucket["window"])
                ))
            }
        }

        return ["gemini", "claude-gpt"].compactMap { kind in
            guard let values = entries[kind], !values.isEmpty else { return nil }
            return QuotaWindow(
                id: "antigravity-\(kind)",
                label: kind == "gemini" ? "Gemini Models" : "Claude & GPT Models",
                remainingPercentage: values.map(\.remaining).min() ?? 0,
                resetTime: earliestReset(values.map(\.resetTime)),
                durationSeconds: values.compactMap(\.duration).max()
            )
        }
    }

    private static func antigravityModelWindows(
        _ models: [String: Any]
    ) -> [QuotaWindow] {
        var entries: [String: [(remaining: Double, resetTime: Date?, duration: TimeInterval?)]] = [:]

        for (modelID, value) in models {
            guard let model = value as? [String: Any],
                  (model["isInternal"] as? Bool) != true else {
                continue
            }

            let apiProvider = string(model["apiProvider"] ?? model["api_provider"])
            guard apiProvider?.caseInsensitiveCompare("API_PROVIDER_INTERNAL") != .orderedSame else {
                continue
            }

            let searchText = [
                modelID,
                string(model["displayName"] ?? model["display_name"]),
                string(model["model"]),
                apiProvider,
                string(model["modelProvider"] ?? model["model_provider"])
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            let kind: String?
            if searchText.contains("gemini") {
                kind = "gemini"
            } else if ["claude", "gpt", "openai", "anthropic"].contains(where: searchText.contains) {
                kind = "claude-gpt"
            } else {
                kind = nil
            }
            guard let kind else { continue }

            let quota = dictionary(model["quotaInfo"] ?? model["quota_info"]) ?? model
            guard let fraction = quotaFraction(
                quota["remainingFraction"] ?? quota["remaining_fraction"]
            ) else {
                continue
            }
            entries[kind, default: []].append((
                remaining: clamp(fraction * 100),
                resetTime: date(quota["resetTime"] ?? quota["reset_time"]),
                duration: 7 * 24 * 3_600
            ))
        }

        return ["gemini", "claude-gpt"].compactMap { kind in
            guard let values = entries[kind], !values.isEmpty else { return nil }
            return QuotaWindow(
                id: "antigravity-\(kind)",
                label: kind == "gemini" ? "Gemini Models" : "Claude & GPT Models",
                remainingPercentage: values.map(\.remaining).min() ?? 0,
                resetTime: earliestReset(values.map(\.resetTime)),
                durationSeconds: 7 * 24 * 3_600
            )
        }
    }

    private static func antigravityGroupKind(_ group: [String: Any]) -> String? {
        let text = [
            string(group["displayName"] ?? group["display_name"]),
            string(group["description"])
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("gemini") { return "gemini" }
        if ["claude", "gpt", "openai", "anthropic"].contains(where: text.contains) {
            return "claude-gpt"
        }
        return nil
    }

    private static func earliestReset(_ dates: [Date?]) -> Date? {
        dates.compactMap { $0 }.min()
    }

    private static func antigravityDuration(_ value: Any?) -> TimeInterval? {
        guard let window = string(value)?.lowercased() else { return nil }
        if window.contains("week") || window == "7d" { return 7 * 24 * 3_600 }
        if window.contains("5h") || window.contains("five-hour") || window.contains("five_hour") {
            return 5 * 3_600
        }
        return nil
    }

    private static func parseKimiQuota(_ body: String) throws -> [QuotaWindow] {
        let object = try jsonObject(body)
        var windows: [QuotaWindow] = []

        if let usage = dictionary(object["usage"]),
           let window = kimiQuotaWindow(
               id: "usage",
               label: string(usage["name"] ?? usage["title"]) ?? "Weekly Limit",
               detail: usage,
               window: nil,
               durationOverride: 7 * 24 * 3_600
           ) {
            windows.append(window)
        }

        if let limits = object["limits"] as? [[String: Any]] {
            for (index, item) in limits.enumerated() {
                let detail = dictionary(item["detail"]) ?? item
                let window = dictionary(item["window"])
                let duration = kimiDurationSeconds(window)
                let label = string(detail["name"] ?? detail["title"])
                    ?? string(item["name"] ?? item["title"] ?? item["scope"])
                    ?? kimiWindowLabel(duration: duration, index: index)
                if let quotaWindow = kimiQuotaWindow(
                    id: "limit-\(index)",
                    label: label,
                    detail: detail,
                    window: window,
                    durationOverride: duration
                ) {
                    windows.append(quotaWindow)
                }
            }
        }

        return windows
    }

    private static func kimiQuotaWindow(
        id: String,
        label: String,
        detail: [String: Any],
        window: [String: Any]?,
        durationOverride: TimeInterval? = nil
    ) -> QuotaWindow? {
        guard let limit = double(detail["limit"]), limit > 0 else { return nil }

        let remainingPercentage: Double
        if let used = double(detail["used"]) {
            remainingPercentage = clamp(100 - (used / limit * 100))
        } else if let remaining = double(detail["remaining"]) {
            remainingPercentage = clamp(remaining / limit * 100)
        } else {
            return nil
        }

        let resetTime = date(
            detail["reset_at"] ?? detail["resetAt"]
                ?? detail["reset_time"] ?? detail["resetTime"]
        ) ?? relativeDate(detail["reset_in"] ?? detail["resetIn"] ?? detail["ttl"])
        return QuotaWindow(
            id: id,
            label: label,
            remainingPercentage: remainingPercentage,
            resetTime: resetTime,
            durationSeconds: durationOverride ?? kimiDurationSeconds(window)
        )
    }

    private static func kimiWindowLabel(duration: TimeInterval?, index: Int) -> String {
        guard let duration else { return "Kimi Limit \(index + 1)" }
        if duration >= 6 * 24 * 3_600 && duration <= 8 * 24 * 3_600 {
            return "Weekly Limit"
        }
        if duration >= 4 * 3_600 && duration <= 6 * 3_600 {
            return "5-hour Limit"
        }
        return "Kimi Limit \(index + 1)"
    }

    private static func kimiDurationSeconds(_ window: [String: Any]?) -> TimeInterval? {
        guard let window,
              let duration = double(window["duration"]), duration > 0 else {
            return nil
        }
        let unit = string(window["timeUnit"] ?? window["time_unit"])?.uppercased() ?? ""
        if unit.contains("MINUTE") { return duration * 60 }
        if unit.contains("HOUR") { return duration * 3_600 }
        if unit.contains("DAY") { return duration * 24 * 3_600 }
        return duration
    }

    private static func codexWindows(
        rateLimit: [String: Any],
        idPrefix: String,
        namePrefix: String?
    ) -> [QuotaWindow] {
        let candidates: [(String, Any?)] = [
            ("primary", rateLimit["primary_window"] ?? rateLimit["primaryWindow"]),
            ("secondary", rateLimit["secondary_window"] ?? rateLimit["secondaryWindow"])
        ]

        return candidates.compactMap { slot, value in
            guard let window = dictionary(value) else { return nil }
            let remaining: Double?
            if let used = double(window["used_percent"] ?? window["usedPercent"]) {
                remaining = clamp(100 - used)
            } else if let count = double(window["remaining_count"] ?? window["remainingCount"]),
                      let total = double(window["total_count"] ?? window["totalCount"]),
                      total > 0 {
                remaining = clamp((count / total) * 100)
            } else {
                remaining = nil
            }
            guard let remaining else { return nil }

            let duration = double(
                window["limit_window_seconds"] ?? window["limitWindowSeconds"]
            )
            let baseLabel: String
            if let duration, duration <= 6 * 3_600 {
                baseLabel = "5-hour Limit"
            } else if let duration, duration >= 28 * 24 * 3_600 {
                baseLabel = "Monthly Limit"
            } else if let duration, duration >= 6 * 24 * 3_600 {
                baseLabel = "Weekly Limit"
            } else {
                baseLabel = slot == "primary" ? "Quota" : "Secondary Quota"
            }

            let resetTime = date(window["reset_at"] ?? window["resetAt"])
                ?? relativeDate(window["reset_after_seconds"] ?? window["resetAfterSeconds"])
            return QuotaWindow(
                id: "\(idPrefix)-\(slot)",
                label: namePrefix.map { "\($0) \(baseLabel)" } ?? baseLabel,
                remainingPercentage: remaining,
                resetTime: resetTime,
                durationSeconds: duration
            )
        }
    }

    private static func jsonObject(_ body: String) throws -> [String: Any] {
        guard let data = body.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaProviderError.invalidResponse("Upstream returned invalid JSON")
        }
        return object
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw QuotaProviderError.invalidResponse("Could not encode request body")
        }
        return string
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }

    private static func quotaFraction(_ value: Any?) -> Double? {
        if let value = double(value) { return value }
        guard let value = string(value), value.hasSuffix("%") else { return nil }
        return Double(value.dropLast()).map { $0 / 100 }
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = double(value), number > 0 {
            let seconds = number > 10_000_000_000 ? number / 1_000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = string(value) else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }

    private static func relativeDate(_ value: Any?) -> Date? {
        guard let seconds = double(value), seconds > 0 else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private static func retryDate(from headers: [String: [String]]?) -> Date? {
        guard let headers else { return nil }
        let value = headers.first { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame }?
            .value.first
        guard let value else { return nil }
        if let seconds = TimeInterval(value) {
            return Date().addingTimeInterval(seconds)
        }
        return date(value)
    }

    private static func stableAccountID(
        provider: ProviderType,
        authIndex: String?
    ) -> String {
        let source = "\(provider.rawValue):\(authIndex ?? "missing")"
        let digest = SHA256.hash(data: Data(source.utf8))
        let shortHash = digest.prefix(10)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(provider.rawValue)-\(shortHash)"
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

private struct AuthFilesResponse: Decodable, Sendable {
    let files: [AuthFile]
}

private struct AuthFile: Decodable, Sendable {
    let authIndex: String?
    let provider: String?
    let type: String?
    let disabled: Bool
    let projectID: String?
    let idToken: CodexIDTokenClaims?
    let accountType: String?
    let name: String?
    let email: String?
    let label: String?
    let planType: String?
    let chatGPTPlanType: String?

    enum CodingKeys: String, CodingKey {
        case provider, type, disabled, name, email, label
        case authIndex = "auth_index"
        case projectID = "project_id"
        case idToken = "id_token"
        case accountType = "account_type"
        case planType = "plan_type"
        case chatGPTPlanType = "chatgpt_plan_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authIndex = try container.decodeIfPresent(String.self, forKey: .authIndex)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        idToken = try container.decodeIfPresent(CodexIDTokenClaims.self, forKey: .idToken)
        accountType = try container.decodeIfPresent(String.self, forKey: .accountType)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        chatGPTPlanType = try container.decodeIfPresent(String.self, forKey: .chatGPTPlanType)
    }

    var normalizedProvider: String {
        (provider ?? type ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var supportsSubscriptionQuota: Bool {
        guard let accountType = accountType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !accountType.isEmpty else {
            return true
        }
        return accountType == "oauth"
    }

    var isAntigravity: Bool {
        normalizedProvider == "antigravity"
            || normalizedProvider.contains("antigravity")
    }

    var planName: String? {
        [planType, chatGPTPlanType, accountType]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.lowercased() != "oauth" }
    }

    func displayName(fallback: String) -> String {
        [name, label, email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallback
    }

    func matches(_ provider: ProviderType) -> Bool {
        switch provider {
        case .claude:
            normalizedProvider == "claude" || normalizedProvider == "anthropic"
                || normalizedProvider.contains("claude")
                || normalizedProvider.contains("anthropic")
        case .codex:
            normalizedProvider == "codex" || normalizedProvider.contains("openai")
        case .gemini:
            normalizedProvider == "gemini" || normalizedProvider == "gemini-cli"
                || normalizedProvider.contains("gemini") || isAntigravity
        case .kimi:
            normalizedProvider == "kimi" || normalizedProvider.contains("kimi")
        }
    }
}

private struct CodexIDTokenClaims: Decodable, Sendable {
    let chatgptAccountID: String?

    enum CodingKeys: String, CodingKey {
        case chatgptAccountID = "chatgpt_account_id"
    }
}

private struct APICallRequest: Encodable, Sendable {
    let authIndex: String
    let method: String
    let url: String
    let header: [String: String]
    let data: String?

    enum CodingKeys: String, CodingKey {
        case method, url, header, data
        case authIndex = "auth_index"
    }
}

private struct APICallResponse: Decodable, Sendable {
    let statusCode: Int
    let header: [String: [String]]?
    let body: String

    enum CodingKeys: String, CodingKey {
        case header, body
        case statusCode = "status_code"
    }
}

private struct QuotaWindow: Sendable {
    let id: String
    let label: String
    let remainingPercentage: Double
    let resetTime: Date?
    let durationSeconds: TimeInterval?
}

private struct AccountQuota: Sendable {
    let windows: [QuotaWindow]
    let planName: String?
}

private extension QuotaProviderError {
    var isAuthenticationFailure: Bool {
        if case .authenticationFailed = self { return true }
        return false
    }
}
