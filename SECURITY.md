# Security Policy / 安全策略

## Supported versions / 支持版本

Security fixes currently target the latest v0.5.x release and the `main` branch.

安全修复目前面向最新的 v0.5.x 版本和 `main` 分支。

## Reporting a vulnerability / 报告漏洞

Please use GitHub's **Security → Report a vulnerability** flow to submit a private security advisory. Do not publish credentials, private endpoints, account identifiers, cached quota files, or exploit details in a public issue.

请使用 GitHub 仓库的 **Security → Report a vulnerability** 私下提交安全报告。不要在公开 Issue 中发布凭据、私人服务器地址、账号标识、配额缓存或漏洞利用细节。

Include the affected version, macOS version, reproduction steps, expected impact, and a minimal sanitized example when possible.

如果可以，请提供受影响版本、macOS 版本、复现步骤、影响范围以及经过脱敏的最小示例。

## Credential safety / 凭据安全

- CPA Widget stores its CLIProxyAPI Endpoint and Management Key in macOS Keychain.
- Provider OAuth tokens stay inside CLIProxyAPI and are substituted server-side.
- Remote plain HTTP exposes the Management Key to network interception. Use HTTPS, a VPN, or a trusted tunnel.
- Never attach `account-quota.json`, Keychain exports, CLIProxyAPI auth files, or unredacted screenshots to a report.

- CPA Widget 将 CLIProxyAPI 地址和 Management Key 保存在 macOS Keychain。
- Provider OAuth Token 始终留在 CLIProxyAPI，由服务端完成替换。
- 远程明文 HTTP 可能导致 Management Key 被窃听，请使用 HTTPS、VPN 或可信隧道。
- 请勿上传 `account-quota.json`、Keychain 导出、CLIProxyAPI 认证文件或未脱敏截图。
