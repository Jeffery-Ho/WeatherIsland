import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = WeatherViewModel()
    private let panelController = IslandPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController.show(viewModel: viewModel)
        viewModel.start()
    }
}
