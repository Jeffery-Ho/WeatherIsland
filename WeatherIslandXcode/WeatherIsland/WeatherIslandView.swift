import SwiftUI

struct WeatherIslandView: View {
    private enum DisplayFontStyle: String, CaseIterable {
        case `default` = "default"
        case serif = "serif"
        case mono = "mono"

        var title: String {
            switch self {
            case .default: return "默认"
            case .serif: return "衬线"
            case .mono: return "等宽"
            }
        }

        var fontDesign: Font.Design {
            switch self {
            case .default: return .rounded
            case .serif: return .serif
            case .mono: return .monospaced
            }
        }

        var displayName: String {
            switch self {
            case .default: return "默认"
            case .serif: return "衬线"
            case .mono: return "等宽"
            }
        }
    }

    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var panelController: IslandPanelController
    @AppStorage("weatherIsland.displayFontStyle") private var displayFontStyleRawValue = DisplayFontStyle.default.rawValue
    @State private var peekTask: DispatchWorkItem?
    @State private var expandTask: DispatchWorkItem?
    @State private var collapseTask: DispatchWorkItem?
    @State private var visualScale: CGFloat = 1.0
    @State private var contentOpacity: Double = 1.0
    @State private var contentScale: CGFloat = 1.0
    @State private var contentOffsetY: CGFloat = 0
    @State private var hoverCollapseSuppressedUntil = Date.distantPast
    @State private var isMenuTracking = false

    private var selectedFontStyle: DisplayFontStyle {
        get { DisplayFontStyle(rawValue: displayFontStyleRawValue) ?? .default }
        nonmutating set { displayFontStyleRawValue = newValue.rawValue }
    }

    private var displayState: IslandPanelController.PresentationState {
        panelController.presentationState
    }

    private var isExpanded: Bool {
        displayState == .expanded
    }

    private var isPeeking: Bool {
        displayState == .peeking
    }

    private var conditionIcon: String {
        let label = viewModel.snapshot.conditionLabel
        if label.contains("晴") { return "sun.max.fill" }
        if label.contains("雨") || label.contains("雷") { return "cloud.rain.fill" }
        if label.contains("雪") { return "cloud.snow.fill" }
        if label.contains("雾") { return "cloud.fog.fill" }
        return viewModel.snapshot.icon
    }

    private var collapsedMenuBarFont: NSFont {
        NSFont.systemFont(ofSize: 13, weight: .semibold)
    }

    var body: some View {
        let visibleHeight = isExpanded
            ? IslandPanelController.expandedVisibleSize.height
            : IslandPanelController.collapsedVisibleHeight
        let visibleWidth = isExpanded
            ? IslandPanelController.expandedVisibleSize.width
            : collapsedVisibleWidth(for: panelController.collapsedLayout)

        ZStack {
            if isExpanded {
                expandedShell
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                collapsedShell(layout: panelController.collapsedLayout)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .scaleEffect(visualScale)
        .frame(width: visibleWidth, height: visibleHeight + IslandPanelController.topBlendInset)
        .animation(islandAnimation, value: displayState)
        .animation(.smooth(duration: 0.3), value: visualScale)
        .animation(.easeOut(duration: 0.25), value: contentOpacity)
        .animation(.smooth(duration: 0.28), value: contentScale)
        .animation(.smooth(duration: 0.28), value: contentOffsetY)
        .onHover { hovering in
            if hovering {
                schedulePeek()
            } else {
                handlePointerExit()
            }
        }
        .onTapGesture {
            expandImmediately()
        }
        .background {
            ClickOutsideMonitor {
                maybeScheduleCollapse()
            }
        }
    }

    private var expandedShell: some View {
        let islandShape = UnevenRoundedRectangle(
            topLeadingRadius: 30,
            bottomLeadingRadius: 30,
            bottomTrailingRadius: 30,
            topTrailingRadius: 30,
            style: .continuous
        )

        return ZStack {
            islandShape
                .fill(Color.black)

            expandedContent
                .opacity(contentOpacity)
                .scaleEffect(contentScale)
                .offset(y: contentOffsetY)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, IslandPanelController.topBlendInset + 6)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .clipShape(islandShape)
        .contentShape(islandShape)
    }

    private func collapsedShell(layout: IslandPanelController.CollapsedLayout) -> some View {
        collapsedContent(layout: layout)
            .opacity(contentOpacity)
            .scaleEffect(isPeeking ? 1.02 : contentScale)
            .offset(y: contentOffsetY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.top, IslandPanelController.topBlendInset + 6)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
    }

    private func collapsedContent(layout: IslandPanelController.CollapsedLayout) -> some View {
        Group {
            if layout == .trailingCompact {
                compactCollapsedContent
            } else {
                centeredCollapsedContent
            }
        }
    }

    private var centeredCollapsedContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: conditionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(viewModel.snapshot.conditionLabel)
                    .font(Font(collapsedMenuBarFont))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            Color.clear
                .frame(width: panelController.hasTopNotch ? panelController.notchAvoidanceSize.width : 0,
                       height: panelController.hasTopNotch ? panelController.notchAvoidanceSize.height : 0)

            Text("\(viewModel.snapshot.temperature)°")
                .font(Font(collapsedMenuBarFont))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 24)
    }

    private var compactCollapsedContent: some View {
        HStack(spacing: 6) {
            Image(systemName: conditionIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("\(viewModel.snapshot.temperature)°")
                .font(Font(collapsedMenuBarFont))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            notchAwareHeader
                .frame(height: 30)
                .padding(.top, 2)

            HStack(spacing: 12) {
                expandedCard(title: "当前温度", accent: viewModel.snapshot.conditionLabel) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(viewModel.snapshot.temperature)")
                                .font(.system(size: 48, weight: .bold, design: selectedFontStyle.fontDesign))
                            Text("°C")
                                .font(.system(size: 17, weight: .semibold, design: selectedFontStyle.fontDesign))
                                .padding(.top, 10)
                        }
                        Text(viewModel.snapshot.nextThreeHoursRainHint)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Color.white)
                }

                expandedCard(title: "当前位置", accent: viewModel.isRefreshing ? "正在刷新" : viewModel.snapshot.updatedAt) {
                    Text(viewModel.snapshot.locationName)
                        .font(.system(size: 40, weight: .bold, design: selectedFontStyle.fontDesign))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notchAwareHeader: some View {
        HStack(spacing: 0) {
            Text("WeatherIsland")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

            Color.clear
                .frame(width: panelController.hasTopNotch ? panelController.notchAvoidanceSize.width : 0,
                       height: panelController.hasTopNotch ? panelController.notchAvoidanceSize.height : 0)

            fontSwitcher
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func collapsedVisibleWidth(for layout: IslandPanelController.CollapsedLayout) -> CGFloat {
        switch layout {
        case .centeredAroundNotch:
            IslandPanelController.collapsedCenteredWidth
        case .trailingCompact:
            IslandPanelController.collapsedCompactWidth
        }
    }

    private var fontSwitcher: some View {
        Menu {
            ForEach(DisplayFontStyle.allCases, id: \.rawValue) { style in
                Button {
                    suppressAutoCollapse(for: 1.2)
                    selectedFontStyle = style
                } label: {
                    HStack(spacing: 10) {
                        Text(style.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer(minLength: 12)
                        Text("Ag")
                            .font(.system(size: 16, weight: .bold, design: style.fontDesign))
                            .foregroundStyle(Color.secondary)
                        if style == selectedFontStyle {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("字体")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(selectedFontStyle.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.white.opacity(0.05), in: Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuTracking = true
            suppressAutoCollapse(for: 4.0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isMenuTracking = false
            suppressAutoCollapse(for: 0.9)
        }
    }

    private func expandedCard<Content: View>(title: String, accent: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(Color.white.opacity(0.56))

            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Image(systemName: title == "当前温度" ? conditionIcon : "location.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(accent)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func expandIfNeeded() {
        guard !isExpanded else { return }
        cancelPeek()
        viewModel.refreshWeather()
        suppressAutoCollapse(for: 0.45)
        visualScale = 1.015
        contentOpacity = 0
        contentScale = 0.965
        contentOffsetY = 6
        panelController.setExpanded(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            contentOpacity = 1
            contentScale = 1
            contentOffsetY = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            visualScale = 1
        }
    }

    private func collapseIfNeeded() {
        guard displayState != .collapsed else { return }
        cancelPeek()
        visualScale = 0.985
        contentOpacity = 0
        contentScale = 0.94
        contentOffsetY = 0
        panelController.setPresentationState(.collapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            visualScale = 1
            contentOpacity = 1
            contentScale = 1
            contentOffsetY = 0
        }
    }

    private func peekIfNeeded() {
        guard displayState == .collapsed else { return }
        visualScale = 1.008
        panelController.setPeeking(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard displayState == .peeking else { return }
            visualScale = 1
        }
    }

    private func collapsePeekIfNeeded() {
        guard displayState == .peeking else { return }
        cancelPeek()
        visualScale = 1
        panelController.setPeeking(false)
    }

    private func schedulePeek() {
        guard displayState == .collapsed else {
            if isPeeking { scheduleExpand() }
            return
        }
        cancelCollapse()
        cancelPeek()
        let task = DispatchWorkItem {
            peekIfNeeded()
            scheduleExpand()
        }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: task)
    }

    private func scheduleExpand() {
        guard !isExpanded else { return }
        cancelCollapse()
        cancelExpand()
        let task = DispatchWorkItem { expandIfNeeded() }
        expandTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (isPeeking ? 0.12 : 0.2), execute: task)
    }

    private func scheduleCollapse() {
        guard isExpanded else {
            cancelExpand()
            return
        }
        guard canAutoCollapse else { return }
        cancelExpand()
        cancelCollapse()
        let task = DispatchWorkItem {
            guard canAutoCollapse else { return }
            collapseIfNeeded()
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private func maybeScheduleCollapse() {
        guard canAutoCollapse else { return }
        scheduleCollapse()
    }

    private func expandImmediately() {
        cancelPeek()
        cancelExpand()
        cancelCollapse()
        if isExpanded { return }
        if !isPeeking { peekIfNeeded() }
        expandIfNeeded()
    }

    private func handlePointerExit() {
        if isExpanded {
            guard Date() >= hoverCollapseSuppressedUntil else { return }
            scheduleCollapse()
        } else {
            cancelExpand()
            collapsePeekIfNeeded()
        }
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
    }

    private func cancelExpand() {
        expandTask?.cancel()
        expandTask = nil
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private var canAutoCollapse: Bool {
        Date() >= hoverCollapseSuppressedUntil && !isMenuTracking
    }

    private func suppressAutoCollapse(for duration: TimeInterval) {
        hoverCollapseSuppressedUntil = max(hoverCollapseSuppressedUntil, Date().addingTimeInterval(duration))
        cancelCollapse()
    }

    private var islandAnimation: Animation {
        switch displayState {
        case .collapsed:
            .smooth(duration: 0.28)
        case .peeking:
            .snappy(duration: 0.18, extraBounce: 0.05)
        case .expanded:
            .snappy(duration: 0.42, extraBounce: 0.03)
        }
    }
}

private struct ClickOutsideMonitor: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> ClickOutsideView {
        let view = ClickOutsideView()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ nsView: ClickOutsideView, context: Context) {
        nsView.isEnabled = true
        nsView.onOutsideClick = onOutsideClick
    }
}

final class ClickOutsideView: NSView {
    var onOutsideClick: (() -> Void)?
    var isEnabled = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    private func installMonitorIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                self.handleLocalClick(event)
                return event
            }
        }

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleGlobalClick(event)
            }
        }

        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.onOutsideClick?()
            }
        }
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard isEnabled, let window else { return }
        if window.contentView?.hitTest(event.locationInWindow) == nil {
            onOutsideClick?()
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        guard isEnabled, let window else { return }
        if !window.frame.contains(event.locationInWindow) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEnabled else { return }
                self.onOutsideClick?()
            }
        }
    }
}
