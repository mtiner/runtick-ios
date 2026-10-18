import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let steps: [(String, String)] = [
        ("进入同一房间", "两台手机分别登录。一人创建房间，另一人输入四位房间号加入；在准备页可切换起点和终点角色。"),
        ("等待准备完成", "保持两端在线和 App 在前台，等待自动校时。网络波动时可重新校准时间。"),
        ("准备发令声音", "媒体音量调至最大，使用本机扬声器。发令使用媒体通道，可在铃声静音模式下播放。"),
        ("开始这一组", "任一端点击“开始记录”，调整各就位口令、等待时间及反应时检测开关。确认后起点自动发令，终点提前按住触控区，听到枪声起跑。底部“起跑发令”可单人训练。开启反应时检测需将手机贴靠或固定在起跑器上；小于 100 ms 标注抢跑。"),
        ("冲线时松手", "终点在运动员冲线时松手。触控取消或切换到后台不会记录成绩；提交失败时保留原始时间戳并重试。"),
        ("保存并继续", "终点填写距离并保存，成绩归入起点运动员名下。保存后点击“下一组”。PB 表示该距离当前个人最好成绩。"),
        ("查看历史与退出", "在“我的”中查看历史成绩，可筛选距离、排序和翻页。全屏页“返回房间”只返回详情，不退出房间。退出房间保留登录和已保存成绩；退出登录会清除本机登录状态。")
    ]
    var body: some View {
        RTPage {
            RTBrand(showHelp: false)
            RTHero(badge: "使用帮助", title: "RunTick 使用说明", subtitle: "从准备到冲线，让每一步都清楚。")
            RTCard {
                ForEach(steps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.subheadline.bold()).frame(width: 28, height: 28).background(RT.aqua.opacity(0.2), in: Circle())
                        VStack(alignment: .leading, spacing: 7) {
                            Text(steps[index].0).font(.headline)
                            Text(steps[index].1).font(.subheadline).foregroundStyle(RT.muted).lineSpacing(5)
                        }
                    }.padding(.vertical, 5)
                }
            }
            NavigationLink { GuideReviewView() } label: {
                Text("检查网络、声音与设备 →").font(.subheadline).underline().foregroundStyle(RT.deep)
            }.buttonStyle(.plain).frame(maxWidth: .infinity).padding(.vertical, 10)
            RTBrandFooter()
        }
        .navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}
private struct GuideReviewView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GuideView(continueTitle: "返回使用说明", showHelp: false) { dismiss() }
            .navigationTitle("设备准备").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}
