import SwiftUI
import AppKit
import QuartzCore

@MainActor
final class IslandPanelController: ObservableObject {
    enum CollapsedLayout {
        case centeredAroundNotch
        case trailingCompact
    }

    enum PresentationState: Equatable {
        case collapsed
        case peeking
        case expanded
    }

    static let topBlendInset: CGFloat = 14
    static let collapsedVisibleHeight: CGFloat = 44
    static let collapsedCenteredWidth: CGFloat = 372
    static let collapsedCompactWidth: CGFloat = 132
    static let peekingWidthDelta: CGFloat = 26
    static let peekingHeightDelta: CGFloat = 8
    static let expandedVisibleSize = NSSize(width: 500, height: 236)

    @Published private(set) var presentationState: PresentationState = .collapsed
    @Published private(set) var collapsedLayout: CollapsedLayout = .centeredAroundNotch
    @Published private(set) var hasTopNotch = true
    @Published private(set) var notchAvoidanceSize = NSSize(width: 210, height: 24)

    private(set) var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?

    func show(viewModel: WeatherViewModel) {
        let rootView = WeatherIslandView(viewModel: viewModel, panelController: self)
        refreshScreenMetrics()

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize(for: .collapsed)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar + 8
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hostingView = IslandHostingView(rootView: AnyView(rootView), panelController: self)
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.cornerRadius = cornerRadius(for: presentationState)
        panel.contentView = hostingView
        panel.setFrame(frame(for: .collapsed), display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        installScreenObserver()
    }

    func setPeeking(_ peeking: Bool) {
        guard presentationState != .expanded else { return }
        setPresentationState(peeking ? .peeking : .collapsed)
    }

    func setExpanded(_ expanded: Bool) {
        setPresentationState(expanded ? .expanded : .collapsed)
    }

    func setPresentationState(_ state: PresentationState) {
        guard panel != nil else { return }
        refreshScreenMetrics()
        guard presentationState != state else { return }
        presentationState = state
        animatePanel(to: frame(for: state), state: state)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func animatePanel(to frame: NSRect, state: PresentationState) {
        guard let panel else { return }
        let duration: TimeInterval
        let timingFunction: CAMediaTimingFunction
        switch state {
        case .collapsed:
            duration = 0.28
            timingFunction = CAMediaTimingFunction(controlPoints: 0.24, 0.8, 0.28, 1.0)
        case .peeking:
            duration = 0.18
            timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.88, 0.28, 1.0)
        case .expanded:
            duration = 0.42
            timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.22, 1.0)
        }

        animatePanelCornerRadius(for: panel, duration: duration, timingFunction: timingFunction)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    private var collapsedCornerRadius: CGFloat {
        floor((Self.collapsedVisibleHeight + Self.topBlendInset) / 2)
    }

    private var peekingCornerRadius: CGFloat {
        floor((peekingVisibleSize.height + Self.topBlendInset) / 2)
    }

    private var expandedCornerRadius: CGFloat { 30 }

    private func cornerRadius(for state: PresentationState) -> CGFloat {
        switch state {
        case .collapsed:
            0
        case .peeking:
            0
        case .expanded:
            expandedCornerRadius
        }
    }

    private func animatePanelCornerRadius(for panel: NSPanel, duration: TimeInterval, timingFunction: CAMediaTimingFunction) {
        guard let layer = panel.contentView?.layer else { return }
        let targetRadius = cornerRadius(for: presentationState)
        let currentRadius = layer.presentation()?.cornerRadius ?? layer.cornerRadius

        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = currentRadius
        animation.toValue = targetRadius
        animation.duration = duration
        animation.timingFunction = timingFunction

        layer.masksToBounds = targetRadius > 0
        layer.cornerCurve = .continuous
        layer.cornerRadius = targetRadius
        layer.add(animation, forKey: "cornerRadius")
    }

    private func visibleSize(for state: PresentationState) -> NSSize {
        switch state {
        case .collapsed:
            collapsedVisibleSize
        case .peeking:
            peekingVisibleSize
        case .expanded:
            Self.expandedVisibleSize
        }
    }

    private func panelSize(for state: PresentationState) -> NSSize {
        let size = visibleSize(for: state)
        return NSSize(width: size.width, height: size.height + Self.topBlendInset)
    }

    private func frame(for state: PresentationState) -> NSRect {
        guard let screen = panel?.screen ?? NSScreen.main else {
            return NSRect(origin: .zero, size: panelSize(for: state))
        }

        let fullFrame = screen.frame
        let size = panelSize(for: state)
        let visibleSize = visibleSize(for: state)
        let x: CGFloat

        if state != .expanded, collapsedLayout == .trailingCompact {
            if let rightArea = screen.auxiliaryTopRightArea {
                x = rightArea.maxX - visibleSize.width - 8
            } else {
                x = fullFrame.maxX - visibleSize.width - 12
            }
        } else {
            x = fullFrame.midX - size.width / 2
        }

        let y = fullFrame.maxY - visibleSize.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private var collapsedVisibleSize: NSSize {
        NSSize(
            width: collapsedLayout == .centeredAroundNotch ? Self.collapsedCenteredWidth : Self.collapsedCompactWidth,
            height: Self.collapsedVisibleHeight
        )
    }

    private var peekingVisibleSize: NSSize {
        NSSize(
            width: collapsedVisibleSize.width + Self.peekingWidthDelta,
            height: Self.collapsedVisibleHeight + Self.peekingHeightDelta
        )
    }

    fileprivate func shouldAcceptHit(at point: CGPoint, in bounds: CGRect) -> Bool {
        switch presentationState {
        case .expanded:
            return bounds.contains(point)
        case .collapsed, .peeking:
            return collapsedHitRegions(in: bounds).contains { $0.contains(point) }
        }
    }

    private func collapsedHitRegions(in bounds: CGRect) -> [CGRect] {
        let capsuleHeight: CGFloat = 24
        let contentBottomPadding: CGFloat = 8
        let capsuleY = contentBottomPadding

        switch collapsedLayout {
        case .trailingCompact:
            let horizontalPadding: CGFloat = 10
            return [
                CGRect(
                    x: horizontalPadding,
                    y: capsuleY,
                    width: bounds.width - horizontalPadding * 2,
                    height: capsuleHeight
                )
            ]
        case .centeredAroundNotch:
            let horizontalPadding: CGFloat = 10
            let gapWidth = hasTopNotch ? notchAvoidanceSize.width : 0
            let capsuleWidth = max(0, (bounds.width - gapWidth - horizontalPadding * 2) / 2)
            return [
                CGRect(x: horizontalPadding, y: capsuleY, width: capsuleWidth, height: capsuleHeight),
                CGRect(
                    x: bounds.width - horizontalPadding - capsuleWidth,
                    y: capsuleY,
                    width: capsuleWidth,
                    height: capsuleHeight
                ),
            ]
        }
    }

    private func refreshScreenMetrics() {
        guard let screen = panel?.screen ?? NSScreen.main else { return }

        let notchSize = screen.notchSize
        hasTopNotch = notchSize != .zero
        notchAvoidanceSize = notchSize == .zero ? .zero : notchSize
        collapsedLayout = preferredCollapsedLayout(for: screen)
    }

    private func preferredCollapsedLayout(for screen: NSScreen) -> CollapsedLayout {
        guard hasTopNotch else { return .centeredAroundNotch }
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return .trailingCompact
        }

        let centeredSegmentWidth = max(0, (Self.collapsedCenteredWidth - notchAvoidanceSize.width) / 2)
        let centeredHorizontalPadding: CGFloat = 24
        let canFitCenteredLayout =
            leftArea.width >= centeredSegmentWidth + centeredHorizontalPadding &&
            rightArea.width >= centeredSegmentWidth + centeredHorizontalPadding

        return canFitCenteredLayout ? .centeredAroundNotch : .trailingCompact
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshScreenMetrics()
                guard let panel = self.panel else { return }
                panel.contentView?.layer?.cornerRadius = self.cornerRadius(for: self.presentationState)
                panel.setFrame(self.frame(for: self.presentationState), display: true)
            }
        }
    }
}

private final class IslandHostingView: NSHostingView<AnyView> {
    weak var panelController: IslandPanelController?

    init(rootView: AnyView, panelController: IslandPanelController) {
        self.panelController = panelController
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panelController else { return super.hitTest(point) }
        guard panelController.shouldAcceptHit(at: point, in: bounds) else { return nil }
        return super.hitTest(point)
    }
}

private extension NSScreen {
    var notchSize: NSSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        let notchWidth = frame.width - leftPadding - rightPadding
        return NSSize(width: notchWidth, height: notchHeight)
    }
}
