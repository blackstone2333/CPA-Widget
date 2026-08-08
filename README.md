# CPA Widget — CLIProxyAPI 配额监控

<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png" width="96" alt="CPA Widget 图标">
</p>

<p align="center">
  macOS 原生 CLIProxyAPI 账号配额监控应用与桌面小组件
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README_EN.md">English</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
  <img alt="Swift 5.9+" src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white">
  <img alt="License MIT" src="https://img.shields.io/badge/License-MIT-blue.svg">
</p>

CPA Widget 通过 CLIProxyAPI Management API 读取各账号的订阅配额，按账号显示剩余比例、重置时间和配额时间线，并把常用信息放到 macOS 菜单栏与桌面 Widget。默认只启用 Codex，其他服务可以按需勾选。

> 当前版本：v0.5.9。仅支持 macOS 14 Sonoma 或更高版本。

## 实际效果

以下为真实 Widget 截图，账号信息未出现在图片中。

| 小型 · 多服务总览 | 中型 · Codex 总额度详情 |
| --- | --- |
| <img src="docs/images/widget-provider-overview.png" width="280" alt="小型多服务配额 Widget"> | <img src="docs/images/widget-codex-detail.png" width="560" alt="中型 Codex 配额详情 Widget"> |

## 功能

- 支持 Codex、Claude OAuth、Gemini CLI / Antigravity 和 Kimi Code。
- 中文与英文界面，默认简体中文。
- 按认证账号显示配额，不合并账号数据。
- 多服务总览按服务内所有账号计算平均剩余量。
- 显示周配额、短周期配额、Codex Spark 等真实返回的配额窗口。
- 配额时间线同时展示已用比例与已过时间，直观看出消耗速度是否超前。
- 5、15、30 分钟自动刷新，可手动刷新。
- 两个完全独立的菜单栏配额通道：每条都可选择服务、账号与任意真实配额窗口。
- 10 种菜单栏预设与自定义组合；图标、百分比、进度条可分别启用，信息可放在进度条同行、上方或下方。
- 深色模式、SF Symbols、Dynamic Type 和 macOS 原生 WidgetKit 样式。
- Endpoint 保存在 App Group 设置中，Management Key 存入 macOS Keychain。
- Provider OAuth Token 始终留在 CLIProxyAPI，不由本应用读取或保存。

## Widget 类型

### 额度 Widget

- 小型：单服务环形余量；最多 4 类服务环形总览；或最多 4 个账号环形总览。
- 中型：单服务平均余量与两条配额详情；最多 4 类服务总览；或最多 2 个账号详情。
- 大型：单服务与账号详情；或最多 4 类服务 / 4 个账号的 2×2 详情卡片。

### 配额时间线 Widget

- 小型：最多 3 个账号，每个显示首选配额窗口。
- 中型：最多 2 个账号的时间进度条。
- 大型：最多 3 个账号，每个最多显示 2 条真实配额窗口。
- 可在“编辑小组件”中选择服务、账号以及短周期 / 周周期。

WidgetKit 的刷新时间最终由 macOS 调度，系统可能根据电量、休眠和使用频率延后刷新。

## 菜单栏额度

在主应用的“菜单栏配额”区域打开“显示”，即可把额度常驻在 macOS 菜单栏：

- 默认显示 Codex 所有账号的周额度平均值，同时可选择 Spark 作为第二额度。
- 第一配额和第二配额拥有各自独立的全部账号、指定服务或指定账号范围，并分别选择实际读取到的任意配额窗口。
- Antigravity 的 Gemini 模型与 Claude/GPT 模型配额分别可选，不会仅因周期相同而合并。
- 内置仅图标、图标＋百分比、线性进度、双额度、双进度条、双行、环形进度等 10 种预设，也支持独立图标、百分比、进度条和上下信息布局的自定义组合。
- 单击菜单栏项目可查看完整账号列表、重置时间、更新时间和错误状态；面板内可直接刷新，不会自动打开主窗口。
- 关闭主窗口后应用仍在后台运行，继续按设置的间隔自动刷新。

## 安装

### 下载构建版本

1. 从 [Releases](https://github.com/blackstone2333/CPA-Widget/releases) 下载最新版本。
2. 解压后把 `CPA Widget.app` 拖入 `/Applications`。
3. 双击打开，填写 CLIProxyAPI 地址和 Management Key。

当前公开发布包未经过 Apple 公证。如果 macOS 提示无法验证开发者，请只在确认文件来自本仓库后执行：

```bash
sudo xattr -rd com.apple.quarantine "/Applications/CPA Widget.app"
open "/Applications/CPA Widget.app"
```

这条命令只移除 CPA Widget 的下载隔离属性，不会全局关闭 Gatekeeper。不要对来源不明的应用执行该命令。

### 添加到桌面

1. 先打开 CPA Widget，保存连接设置并完成一次“刷新全部账号”。
2. 在桌面空白处右键，选择“编辑小组件”。
3. 搜索 `CPA Widget`。
4. 选择额度或配额时间线 Widget，并添加小型、中型或大型尺寸。
5. 右键已添加的 Widget，选择“编辑小组件”来设置显示方式、服务、账号和周期。

如果 Widget 显示“暂无配额数据”，请先在主应用刷新一次，然后重新编辑或移除后再添加 Widget。

## CLIProxyAPI 配置

CLIProxyAPI 必须启用 Management API。示例 `config.yaml`：

```yaml
remote-management:
  allow-remote: false
  secret-key: "replace-with-a-strong-management-key"
```

- 同一台 Mac 使用时保持 `allow-remote: false`。
- 跨设备连接时才启用远程管理，并优先使用 HTTPS、VPN 或可信隧道。
- 应用内填写 CLIProxyAPI 根地址，例如 `http://localhost:8317`，也接受以 `/v0/management` 结尾的地址。
- 公网 HTTP 会明文传输 Management Key；应用会显示警告，但不会替你加密连接。

CPA Widget 先读取：

```text
GET /v0/management/auth-files
```

然后通过：

```text
POST /v0/management/api-call
```

让 CLIProxyAPI 使用指定认证账号请求上游配额。`$TOKEN$` 在 CLIProxyAPI 服务端替换，因此 OAuth Token 不会传给 CPA Widget。

## 自动刷新说明

- 主应用负责获取真实配额、写入本地共享缓存，并通知 Widget 重新加载。
- 安装在 `/Applications` 后，应用会尝试注册登录时启动。
- 关闭窗口不会退出应用，自动刷新仍可继续。
- 如果在菜单中选择“退出 CPA Widget”，自动获取会停止；再次打开后恢复。
- Mac 休眠、节能策略或网络中断会影响实际执行时间，不能保证精确到每 5 分钟整。

## 从源码构建

要求：macOS 14+、Xcode 15.3+、Swift 5.9+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
git clone https://github.com/blackstone2333/CPA-Widget.git
cd CPA-Widget
xcodegen generate
xcodebuild \
  -project CPAWidget.xcodeproj \
  -scheme CPAWidget \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  build
```

如果命令行提示缺少签名身份，请在 Xcode 的 Signing & Capabilities 中选择自己的 Team 后再构建。

构建结果位于：

```text
build/DerivedData/Build/Products/Release/CPA Widget.app
```

也可以用 Xcode 打开 `CPAWidget.xcodeproj`，选择 `CPAWidget` Scheme 后运行。

## 隐私与安全

- Endpoint 保存在 App Group 设置中；Management Key 保存在 macOS Keychain，应用仅在密钥变化时写入。
- 配额快照、账号显示名和非敏感设置只保存在本机 `~/Library/Application Support/CPAWidget/Shared/`。
- OAuth Token、CLIProxyAPI 认证文件和账号密钥不会写入本仓库，也不会被应用导出。
- 项目不包含遥测、广告、云同步或第三方统计 SDK。
- 远程 HTTP 不安全；跨网络使用时请配置 HTTPS 并定期轮换 Management Key。

发现安全问题请参阅 [SECURITY.md](SECURITY.md)，不要在公开 Issue 中粘贴密钥、Token、服务器地址或账号信息。

## 开发说明

主要模块：

```text
App/         macOS 主应用与设置界面
Widget/      WidgetKit Extension、布局和 App Intent 配置
Core/        数据模型、协议和共享视图
Providers/   CLIProxyAPI Provider Adapter 与响应解析
Services/    配额管理和自动刷新
Storage/     Keychain、设置和共享缓存
Resources/   图标与 Provider Logo
```

Provider 的订阅配额接口并非稳定公开 API，响应发生变化时应尽量只修改对应 Adapter。Logo 来源记录在 [Resources/PROVIDER_LOGO_SOURCES.md](Resources/PROVIDER_LOGO_SOURCES.md)。各 Provider 名称和 Logo 属于其权利人，本项目与这些服务商没有隶属或背书关系。

贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 相关项目

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) — 本项目使用的后端与 Management API。
- [CLIProxy Pool Watch](https://github.com/murasame612/CLIProxyPoolWidget) — 原生 WidgetKit 与多账号池设计参考。
- [CLIProxyAPI Quota Inspector](https://github.com/AllenReder/CLIProxyAPI-Quota-Inspector) — Management API、账号索引和配额解析参考。
- [ZeroLimit](https://github.com/0xtbug/zero-limit) — 多 Provider 配额解析参考。
- [AIUsage](https://github.com/sylearn/AIUsage) — Swift Provider 边界与 Gemini 聚合参考。
- [Quotio](https://github.com/nguyenphutrong/quotio) — macOS 原生配额 UI 与响应模型参考。

## License

代码以 [MIT License](LICENSE) 开源。Provider Logo 和商标仍归各自权利人所有。
