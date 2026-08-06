# Contributing / 参与贡献

Thanks for helping improve CPA Widget. 欢迎为 CPA Widget 提交改进。

## Before opening a change / 提交前

1. Use macOS 14+, Xcode 15.3+, Swift 5.9+, and XcodeGen.
2. Keep provider-specific response parsing inside `Providers/`.
3. Preserve both Simplified Chinese and English UI copy.
4. Never commit a real Management Key, private endpoint, OAuth token, account email, auth filename, Keychain export, or quota cache.
5. Use synthetic fixtures and fully redacted screenshots.

1. 使用 macOS 14+、Xcode 15.3+、Swift 5.9+ 和 XcodeGen。
2. Provider 专用响应解析应保留在 `Providers/` 内。
3. 界面改动需同时维护简体中文和英文。
4. 禁止提交真实 Management Key、私人地址、OAuth Token、账号邮箱、认证文件名、Keychain 导出或配额缓存。
5. 测试数据必须为合成数据，截图必须完全脱敏。

## Build / 构建

```bash
xcodegen generate
xcodebuild \
  -project CPAWidget.xcodeproj \
  -scheme CPAWidget \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

If `project.yml` changes, regenerate and commit `CPAWidget.xcodeproj` in the same change.

修改 `project.yml` 后，请重新生成并在同一次提交中更新 `CPAWidget.xcodeproj`。

## Pull requests / Pull Request

- Explain the user-visible behavior and Provider/API assumptions.
- Include verification steps and the build result.
- Keep unrelated formatting or refactors out of the change.
- For UI changes, attach sanitized before/after screenshots.

- 说明用户可见变化和 Provider/API 假设。
- 写明验证步骤和构建结果。
- 不要混入无关格式化或重构。
- UI 改动请附上脱敏前后截图。
