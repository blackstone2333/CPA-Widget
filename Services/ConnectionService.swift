import Foundation

struct ConnectionService: Sendable {
    func testEndpoint(_ endpoint: String, managementSecret: String) async throws -> Int {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw QuotaProviderError.invalidConfiguration("Enter a valid HTTP(S) endpoint.")
        }

        let client = CLIProxyAPIQuotaClient(
            endpoint: url,
            managementSecret: managementSecret
        )
        return try await client.testConnection()
    }
}
