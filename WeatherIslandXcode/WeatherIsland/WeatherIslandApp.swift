import SwiftUI
import AppKit

@main
struct WeatherIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weather Island")
                .font(.headline)
            Text("应用启动后会藏在 MacBook notch 下方显示，中间会预留约 210 x 24 的避让区，内容仅分布在 notch 两侧与下方。鼠标移入可展开详细信息，使用 Command+Q 退出。")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}
