import SwiftUI

struct AboutView: View {
    var body: some View {
        RTPage {
            RTBrand(); RTHero(badge: "关于", title: "RunTick · 燃刻", subtitle: "为每一次认真训练而生")
            RTCard("让每一次出发，有迹可循") {
                Text("双端短跑计时、单人原声发令、起跑反应检测与训练成绩管理。")
                Text("反应时如何测量").font(.headline)
                Text("将起点手机贴靠或固定在起跑器上并保持稳定。App 用本机音频时钟、加速度计和陀螺仪，计算枪声到检测到手机移动的时间差。")
                Text("这是设备运动检测估算，受安装方式、采样率、扬声器振动和系统音频延迟影响，不能替代专业起跑器，不能用于正式比赛或判罚。未检测到移动不会记作 0 ms；枪响前移动会单独标记。").font(.footnote).foregroundStyle(RT.muted)
                Text("数据与权限").font(.headline)
                Text("运动采样仅在本机处理，服务器只保存时间差、检测状态和发令设置。单人模式不需要另一台手机；联网登录后同步记录。")
                Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")").font(.caption).foregroundStyle(RT.muted)
                Link("访问官网 ↗", destination: URL(string: "https://runtick.cc")!)
            }
        }.navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
    }
}
