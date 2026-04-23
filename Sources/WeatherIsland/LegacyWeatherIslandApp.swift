import SwiftUI
import AppKit

struct WeatherSnapshot {
    let locationName: String
    let temperature: Int
    let apparentTemperature: Int
    let humidity: Int
    let windSpeed: Int
    let conditionLabel: String
    let icon: String
    let updatedAt: String
}

struct IPLocationResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let city: String?
    let region: String?
    let country_name: String?
}

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }

    let current: Current
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var snapshot = WeatherSnapshot(
        locationName: "正在定位...",
        temperature: 0,
        apparentTemperature: 0,
        humidity: 0,
        windSpeed: 0,
        conditionLabel: "同步中",
        icon: "sun.max.fill",
        updatedAt: "--:--"
    )
    @Published var statusText = "正在准备天气活动..."
    @Published var isRefreshing = false

    private var refreshTimer: Timer?

    func start() {
        refreshWeather()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWeather()
            }
        }
    }

    func refreshWeather() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusText = "正在同步当前位置天气..."

        Task {
            defer {
                Task { @MainActor in
                    self.isRefreshing = false
                }
            }

            do {
                let location = try await fetchApproximateLocation()
                let weather = try await fetchWeather(latitude: location.latitude, longitude: location.longitude)
                let info = Self.weatherInfo(for: weather.current.weather_code)
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"

                let place = [location.city, location.region, location.country_name]
                    .compactMap { $0 }
                    .reduce(into: [String]()) { partialResult, item in
                        if !partialResult.contains(item) {
                            partialResult.append(item)
                        }
                    }
                    .prefix(2)
                    .joined(separator: " · ")

                await MainActor.run {
                    self.snapshot = WeatherSnapshot(
                        locationName: place.isEmpty ? "当前位置" : place,
                        temperature: Int(weather.current.temperature_2m.rounded()),
                        apparentTemperature: Int(weather.current.apparent_temperature.rounded()),
                        humidity: Int(weather.current.relative_humidity_2m.rounded()),
                        windSpeed: Int(weather.current.wind_speed_10m.rounded()),
                        conditionLabel: info.label,
                        icon: info.icon,
                        updatedAt: formatter.string(from: Date())
                    )
                    self.statusText = "活动常驻运行中，每 10 分钟自动更新。"
                }
            } catch {
                await MainActor.run {
                    self.statusText = "天气获取失败，请检查网络后重试。"
                    self.snapshot = WeatherSnapshot(
                        locationName: "天气不可用",
                        temperature: 0,
                        apparentTemperature: 0,
                        humidity: 0,
                        windSpeed: 0,
                        conditionLabel: "未连接",
                        icon: "wifi.exclamationmark",
                        updatedAt: "--:--"
                    )
                }
            }
        }
    }

    private func fetchApproximateLocation() async throws -> IPLocationResponse {
        let url = URL(string: "https://ipapi.co/json/")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(IPLocationResponse.self, from: data)
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    private static func weatherInfo(for code: Int) -> (label: String, icon: String) {
        switch code {
        case 0: return ("晴朗", "sun.max.fill")
        case 1: return ("大部晴", "sun.max")
        case 2: return ("局部多云", "cloud.sun.fill")
        case 3: return ("阴天", "cloud.fill")
        case 45, 48: return ("有雾", "cloud.fog.fill")
        case 51, 53, 55, 61, 63, 80, 81: return ("降雨", "cloud.drizzle.fill")
        case 65, 82, 95, 96, 99: return ("强降雨", "cloud.bolt.rain.fill")
        case 71, 73, 75: return ("降雪", "cloud.snow.fill")
        default: return ("天气更新中", "cloud.fill")
        }
    }
}

@MainActor
final class IslandWindowController: ObservableObject {
    static let collapsedSize = NSSize(width: 344, height: 52)
    static let expandedSize = NSSize(width: 440, height: 248)

    private(set) var window: NSPanel?
    private var isExpanded = false

    func show(viewModel: WeatherViewModel) {
        let contentView = WeatherIslandView(viewModel: viewModel, windowController: self)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: contentView)
        panel.setFrame(frame(for: Self.collapsedSize), display: true)
        panel.orderFrontRegardless()
        self.window = panel
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded, let window else { return }
        isExpanded = expanded
        let nextSize = expanded ? Self.expandedSize : Self.collapsedSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame(for: nextSize), display: true)
        }
    }

    private func frame(for size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 6
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

struct BlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct WeatherIslandView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var windowController: IslandWindowController
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isHovered ? 30 : 26, style: .continuous)
                .fill(.black.opacity(0.8))
                .overlay {
                    BlurView()
                        .clipShape(RoundedRectangle(cornerRadius: isHovered ? 30 : 26, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: isHovered ? 30 : 26, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 30, y: 16)

            Group {
                if isHovered {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    collapsedContent
                        .transition(.opacity)
                }
            }
            .padding(isHovered ? 14 : 8)
        }
        .frame(width: isHovered ? 440 : 344, height: isHovered ? 248 : 52)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            windowController.setExpanded(hovering)
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.4), Color(red: 0.95, green: 0.4, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 8, height: 8)

                Text("\(viewModel.snapshot.temperature)°")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 32)
            .background(.white.opacity(0.08), in: Capsule())

            Spacer(minLength: 0)

            Capsule()
                .fill(.white.opacity(0.05))
                .frame(width: 96, height: 32)
        }
        .padding(.horizontal, 8)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Weather")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(viewModel.snapshot.locationName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(viewModel.snapshot.conditionLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.83, green: 0.92, blue: 1.0))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.2, green: 0.45, blue: 0.9).opacity(0.22), in: Capsule())
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前温度")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.62))
                    HStack(alignment: .top, spacing: 4) {
                        Text("\(viewModel.snapshot.temperature)")
                            .font(.system(size: 62, weight: .bold, design: .rounded))
                        Text("°C")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .padding(.top, 12)
                    }
                    .foregroundStyle(.white)
                    Text("\(viewModel.snapshot.conditionLabel)，适合快速查看当前天气动态。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Image(systemName: viewModel.snapshot.icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Color(red: 0.95, green: 0.98, blue: 1.0))
                    .frame(width: 86, height: 86)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.63, blue: 0.98).opacity(0.36), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
            }

            HStack(spacing: 10) {
                detailCard(title: "体感", value: "\(viewModel.snapshot.apparentTemperature)°C")
                detailCard(title: "风速", value: "\(viewModel.snapshot.windSpeed) km/h")
                detailCard(title: "湿度", value: "\(viewModel.snapshot.humidity)%")
                detailCard(title: "刷新时间", value: viewModel.snapshot.updatedAt)
            }

            HStack {
                Text(viewModel.statusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Button(action: viewModel.refreshWeather) {
                    Text(viewModel.isRefreshing ? "更新中..." : "刷新天气")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.2, blue: 0.34))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.76, green: 0.9, blue: 1.0), Color(red: 0.48, green: 0.83, blue: 0.98)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRefreshing)
            }
        }
        .foregroundStyle(.white)
    }

    private func detailCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = WeatherViewModel()
    private let windowController = IslandWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.show(viewModel: viewModel)
        viewModel.start()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct WeatherIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weather Island")
                    .font(.headline)
                Text("应用启动后会在屏幕顶部显示天气岛。使用 Command+Q 退出。")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 320)
        }
    }
}
