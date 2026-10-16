# RunTick iOS · 燃刻

原生 SwiftUI 双端跑步计时客户端，最低部署目标 **iOS 26.0**。兼容已有 RunTick Cloudflare Worker API，可与网页端加入同一房间。没有使用 WebView。

## 在 Xcode 中运行

需要带 iOS 26 SDK 的 Xcode 和 XcodeGen（`brew install xcodegen`）。

```sh
xcodegen generate
open RunTick.xcodeproj
```

选择 RunTick scheme 和 iPhone/iPad，在 Signing & Capabilities 中选择自己的 Team；Bundle ID 可自行调整。无需第三方 Swift 包。首次启动填写已部署 RunTick 后端的 **HTTPS 根地址**，例如 `https://你的域名`（不要填写 `/web/`）。源仓库没有记录生产域名，因此客户端不猜测服务地址。账号与网页端共用，首次 ID 登录自动注册。

`project.yml` 是工程配置源，修改后重新生成。仓库同时包含可直接打开的 `.xcodeproj`。调试后端必须提供可被手机访问且证书有效的 HTTPS 地址，应用不放开 ATS。

## 功能

- 设备引导、传感器可用性检查、原声试听；房间内前台屏幕常亮。
- 登录、会话恢复、退出、全局 401 清理；系统 Cookie 同时用于 REST 与 WebSocket。
- 创建/加入 4 位房间，双人在线状态、起点/终点角色互换，自动重连和 30 秒心跳。
- 20 次 HTTP 校时，平均偏移与 RTT、误差估计；超过 250 ms 拒绝，超过两分钟重新校时。
- 三阶段固定/随机等待（0–30 秒）、原始 WAV 硬件时钟发令、枪声时间戳。
- 终点可提前按住，全屏松手记录；触控取消、切后台均不产生事件。
- 服务端轮次同步、乱序响应保护、原始时间戳持久化和重试、成绩保存后下一组。
- 终点填写 1–100000 米整数距离，保存到起点运动员名下；PB 与提升提示。
- 自己/同房间运动员历史、距离筛选、四种排序、50 条分页、最近十次平滑趋势与逐点详情。

完整对照、验证边界见 [MIGRATION.md](MIGRATION.md)。后台不持续发令或录制；回到前台重新校时。

## 测试

```sh
xcodebuild -project RunTick.xcodeproj -scheme RunTick \
  -destination 'platform=iOS Simulator,name=你的 iOS 26 模拟器' \
  CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions 会检查 SDK 版本，再编译并运行 XCTest。若 GitHub 托管机器尚无 iOS 26 SDK，任务会明确失败；需改用安装相应 Xcode 的 runner。最低部署版本与构建 SDK 分开管理：可用更高版本 SDK 构建，但兼容性测试仍需 iOS 26 模拟器。

本次迁移在 Linux 编写，无法执行 Apple SDK 类型检查、模拟器和签名打包。Linux 的 Swift 校验不代替 iOS 构建，尚需按 MIGRATION 中的双机清单验收。

平台无关核心逻辑也可用 Swift 6 执行 `swift test`；当前 5 个用例已通过。它只编译 Core 与测试，不构建 iOS 界面或音频服务。
