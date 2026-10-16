# 迁移记录与验收

源：`mtiner/runtick`，commit `5f2d6abf143dab1c7de342d0c22461dfc7097b3b`。

| 网页端来源 | iOS 实现 |
| --- | --- |
| auth store、api.ts | AppModel、APIClient、Models |
| rooms、room-entry、路由退出逻辑 | RootView、AppModel.leave |
| RoomDetail、useRoomSocket | RoomView、RoomModel，REST 轮次每秒轮询，WebSocket 成员推送 |
| useClock | ClockMapping、MonotonicClock、RoomModel.calibrate |
| starterSettings、starterAudio、SoundCheck | StageDelay、StarterAudio（AVAudioEngine）、RoomView |
| RacePanel | RoomModel、RoomView、FinishPad、TouchCapture |
| DistanceSave、PbCelebration | 距离校验、预设距离、PB 奖杯、触觉反馈与提升提示 |
| HistoryView、HistoryTrend、smoothCurve | HistoryView、Swift Charts 单调插值、逐点列表 |
| Guide、device permissions、wake lock | GuideView、CoreMotion 可用性、系统 Cookie、idle timer |

原站 `/start`、`/finish`、`/result` 为旧静态示例且被路由重定向；没有把示例虚构数据作为真实功能。原生应用不需要浏览器 AudioContext 解锁、网页 Cookie 探测和添加到主屏幕教程，分别以系统音频会话、URLSession Cookie 和已安装 App 替代。传感器在现有网页实际计时链路中不参与起跑检测，原生也不制造自动检测功能。

后端仍由原 runtick 仓库维护，包含身份、角色互斥、双人限制、计时有效性、幂等事件、PB 和历史权限；本仓库不另行部署/复制一套生产数据库。API 路径和字段与源仓库保持兼容，原生请求不带浏览器 Origin。原始 WAV 从源仓库原样复制。

## 时间与持久化

使用进程启动时的 epoch + systemUptime，避免设备墙钟跳变影响计时。校时公式与网页相同，枪声按 AVAudioEngine 的 hostTime 排程。音频输出延迟由 AVAudioSession 估计，再加入 20 ms 音频误差预算；这不等于实际扬声器延迟保证，必须真机测量，尤其不能把蓝牙输出视为可精确计时。人工反应误差单独由使用者承担。

待提交事件以服务地址、用户 ID、房间隔离，持久化事件时间而非重试时重新取时间。恢复登录时在离开旧房间之前先补交该用户待提交事件。服务端永久拒绝的事件保留以便诊断，错误不会静默丢弃。非当前用户不重放。Cookie 交给系统保存，不保存密码。进入后台取消按压/音频，回前台重新校时。

## 尚需在 Apple 环境验收

- 使用 iOS 26 SDK 完整构建、XCTest、无障碍/Dynamic Type 与 iPhone/iPad 布局。
- 两台真机及一台网页混合加入：角色互换、在线离线、房间满员、退出与重连。
- 起点试听后发令，终点提前按住，松开得到相同成绩；后台/系统打断不能误记。
- 固定/随机等待、零等待、最大等待、音频路由变化与扬声器枪声时间实测。
- 断网松手，恢复网络补交原始时间戳；杀进程再启动补交；重复提交保持幂等。
- 终点早于枪声、超一小时、连续下一组、仅终点保存距离、PB 提升和并列。
- 历史运动员权限、距离、四种排序、50 条分页、趋势跨页不变与空记录。
- 401 清理、服务不可达、Cookie 恢复、切换服务地址账号隔离。

CI 明确要求 iOS 26 SDK；没有在当前 Linux 环境声称 Apple 构建/真机验收已经通过。

## 本次已执行验证

- Swift 6.2 Linux 前端对全部应用和测试 Swift 源文件语法解析通过。
- `swift test`：5 个 XCTest 用例全部通过（偏移/误差公式、不可用网络样本、等待设置、原始时间戳持久化、乱序响应保护）。
- 使用真实 FoundationNetworking/Observation 对 APIClient、AppModel/RoomModel 做 Linux 类型检查通过；仅将 Apple 专用音频服务替换为签名相同的验证桩，此项不覆盖 AVFoundation/SwiftUI 类型检查。
- 三个 WAV 与源仓库逐字节一致；工程源文件、音频引用、scheme XML 与 YAML 配置做静态检查。

## 最低系统版本调整

最低部署版本由 iOS 27.0 调整为 iOS 26.0，应用与测试 target、生成脚本和 CI 同步更新。现有代码使用 SwiftUI/Observation、Swift Charts、URLSession WebSocket、AVAudioEngine 和 UIKit 触控，没有采用 iOS 27 专属 API，因此无需删减业务功能。iOS 26 及以上均可安装；iOS 27 的实际表现仍需对应系统验收。

计时精度取决于设备、音频路由、网络波动和人工反应；不能仅凭系统版本宣称 iOS 27 更准确。CI 允许 iOS 26 或更新 SDK，但测试明确选择 iOS 26 runtime。

## H5 底部导航同步与 Liquid Glass

参考 `mtiner/runtick-app` commit `74ed2ee105033b0726214d1ddbb3d62b1e2be5bd` 的 BottomNav、ProfileView 和 currentRoom API。

- iOS 使用原生 `TabView` / `Tab`，对应“房间详情”“我的”。使用 iOS 26+ SDK 构建后由系统绘制 Liquid Glass 标签栏，不覆盖其背景或复制 H5 固定高度。
- “我的”显示头像首字母、账号、登录状态、历史成绩及退出登录；历史页保留在该标签的独立 NavigationStack。
- 点击房间标签先查询 `GET /api/rooms/current`；有房间则恢复，无房间则进入入口。查询失败保留当前标签和错误提示。切换到“我的”取消本机发令和按压，但保留房间连接。
- 终点触控继续使用全屏 presentation 遮住底部标签栏；返回和重新校时按钮使用系统 `.glass` 按钮样式。
- 保留系统无障碍与减少透明度行为；不对主触控平面叠加玻璃，避免影响对比度。

新增 currentRoom 空房间/现有房间响应解码测试。仍需 Xcode 26+ 构建与真机检查玻璃外观、深浅色、减少透明度、标签切换和全屏触控恢复。

## H5 视觉与动效迁移

以 runtick-app 的 main.css 和实际页面为基准：`#65DDD5` 薄荷青、`#E6F56B` 柠檬黄、`#173E3B` 深色文字、`#F7FBF9` 背景；24pt 白色卡片、16pt 按钮、柔和投影和背景光晕。引导、登录、房间入口、房间准备、发令设置、成绩、历史、个人页及声音确认全部采用共享 DesignSystem，移除默认 Form/List 的表单外观。内容维持 H5 浅色视觉；系统标签栏继续使用原生 Liquid Glass。大屏内容限制宽度，页面可滚动，支持字体放大。

动画包括分层上浮入场、按钮弹性按压、成绩揭晓、PB 奖杯与放射彩带、终点按住时的光圈和颜色过渡。全部入场/缩放/颜色动画遵守系统 Reduce Motion，不延迟时间戳采集。业务请求、校时和音频时间映射保持原实现。CI 新增引导/登录模拟器实机渲染截图产物，供视觉检查。

品牌组件进一步同步 H5 `ca4b534`：定制中英文字标由原始 SVG 多边形直接转换为原生矢量 Shape，保持轮廓与 even-odd 填充；登录和引导页增加淡色品牌页脚。

## 冷启动品牌页

LaunchContainer 每次进程冷启动显示一次品牌页，复用 RTBackdrop（网站同款薄荷/柠檬径向渐变）、网站原始 apple-touch-icon，以及原生矢量中英字标。图标、名称与浅灰 slogan 居中排列。采用“为每一次认真训练而生”。轻微淡入缩放与退场遵守减少动态效果。

会话恢复与约 1.3 秒品牌展示并行，网络异常不会无限停留在品牌页；随后进入原有使用引导或登录/房间入口。后台回到前台不会重播。系统启动画面仍由 iOS 生成，该品牌页是首帧后的原生启动过渡，不冒充系统 Launch Screen。DEBUG 专用 --brand-preview 仅用于 CI 截图。

## Apple Icon Composer 图标

接入用户提供的 runtick.icon 原始包（icon.json 与 SVG 图层保持原样），ASSETCATALOG_COMPILER_APPICON_NAME 设为 runtick，系统负责默认、深色、着色与透明外观。冷启动页使用用户提供的 Default 1024px 导出图，替换旧网页低分辨率图标。六种原始 PNG 导出归档在 Design/IconComposerExports，未重新绘制或修改。CI 同时检查编译后的图标元数据与音频资源。
