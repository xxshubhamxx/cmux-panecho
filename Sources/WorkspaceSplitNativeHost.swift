import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
enum WorkspaceLayoutTabChromeDebugSettings {
    static let closeGlyphDXKey = "workspaceTabChrome.closeGlyphDX"
    static let closeGlyphDYKey = "workspaceTabChrome.closeGlyphDY"
    static let closeCircleDXKey = "workspaceTabChrome.closeCircleDX"
    static let closeCircleDYKey = "workspaceTabChrome.closeCircleDY"
    static let closeCircleSizeDeltaKey = "workspaceTabChrome.closeCircleSizeDelta"
    static let defaultCloseGlyphDX = 0.0
    static let defaultCloseGlyphDY = 0.0
    static let defaultCloseCircleDX = 0.0
    static let defaultCloseCircleDY = 0.0
    static let defaultCloseCircleSizeDelta = 0.0
    static let closeGlyphOffsetRange: ClosedRange<Double> = -4...4
    static let closeCircleSizeDeltaRange: ClosedRange<Double> = -6...8

    static func clamped(_ value: Double) -> Double {
        min(max(value, closeGlyphOffsetRange.lowerBound), closeGlyphOffsetRange.upperBound)
    }

    static func clampedCircleSizeDelta(_ value: Double) -> Double {
        min(max(value, closeCircleSizeDeltaRange.lowerBound), closeCircleSizeDeltaRange.upperBound)
    }

    static func closeGlyphDX(userDefaults: UserDefaults = .standard) -> CGFloat {
        CGFloat(
            clamped(
                userDefaults.object(forKey: closeGlyphDXKey) as? Double
                    ?? defaultCloseGlyphDX
            )
        )
    }

    static func closeGlyphDY(userDefaults: UserDefaults = .standard) -> CGFloat {
        CGFloat(
            clamped(
                userDefaults.object(forKey: closeGlyphDYKey) as? Double
                    ?? defaultCloseGlyphDY
            )
        )
    }

    static func closeCircleDX(userDefaults: UserDefaults = .standard) -> CGFloat {
        CGFloat(
            clamped(
                userDefaults.object(forKey: closeCircleDXKey) as? Double
                    ?? defaultCloseCircleDX
            )
        )
    }

    static func closeCircleDY(userDefaults: UserDefaults = .standard) -> CGFloat {
        CGFloat(
            clamped(
                userDefaults.object(forKey: closeCircleDYKey) as? Double
                    ?? defaultCloseCircleDY
            )
        )
    }

    static func closeCircleSizeDelta(userDefaults: UserDefaults = .standard) -> CGFloat {
        CGFloat(
            clampedCircleSizeDelta(
                userDefaults.object(forKey: closeCircleSizeDeltaKey) as? Double
                    ?? defaultCloseCircleSizeDelta
            )
        )
    }
}

private enum WorkspaceLayoutTabChromeAccessoryMetrics {
    static let baseDY = CGFloat(-0.359375)
    static let basePointSizeDelta = CGFloat(0.09375)
    static let baseCloseCircleDY = CGFloat(-1)
}

private func workspaceLayoutDebugPreview(_ text: String, limit: Int = 120) -> String {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    if escaped.count <= limit {
        return escaped
    }
    return "\(escaped.prefix(limit))..."
}

private struct WorkspaceLayoutTabChromeDebugTuning {
    let titleDX: CGFloat
    let titleDY: CGFloat
    let titlePointSizeDelta: CGFloat
    let titleKern: CGFloat
    let iconDX: CGFloat
    let iconDY: CGFloat
    let iconPointSizeDelta: CGFloat
    let accessoryDX: CGFloat
    let accessoryDY: CGFloat
    let accessoryPointSizeDelta: CGFloat
    let closeGlyphDX: CGFloat
    let closeGlyphDY: CGFloat
    let closeCircleDX: CGFloat
    let closeCircleDY: CGFloat
    let closeCircleSizeDelta: CGFloat

    static var current: WorkspaceLayoutTabChromeDebugTuning {
        WorkspaceLayoutTabChromeDebugTuning()
    }

    private init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        titleDX = Self.cgFloat("CMUX_TAB_CHROME_TITLE_DX", environment: environment, defaultValue: 1)
        titleDY = Self.cgFloat("CMUX_TAB_CHROME_TITLE_DY", environment: environment, defaultValue: 0.375)
        titlePointSizeDelta = Self.cgFloat("CMUX_TAB_CHROME_TITLE_POINT_SIZE_DELTA", environment: environment)
        titleKern = Self.cgFloat("CMUX_TAB_CHROME_TITLE_KERN", environment: environment)
        iconDX = Self.cgFloat("CMUX_TAB_CHROME_ICON_DX", environment: environment, defaultValue: -1)
        iconDY = Self.cgFloat("CMUX_TAB_CHROME_ICON_DY", environment: environment, defaultValue: -0.875)
        iconPointSizeDelta = Self.cgFloat("CMUX_TAB_CHROME_ICON_POINT_SIZE_DELTA", environment: environment, defaultValue: -0.5)
        accessoryDX = Self.cgFloat("CMUX_TAB_CHROME_ACCESSORY_DX", environment: environment)
        accessoryDY = Self.cgFloat(
            "CMUX_TAB_CHROME_ACCESSORY_DY",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeAccessoryMetrics.baseDY
        )
        accessoryPointSizeDelta = Self.cgFloat(
            "CMUX_TAB_CHROME_ACCESSORY_POINT_SIZE_DELTA",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeAccessoryMetrics.basePointSizeDelta
        )
        closeGlyphDX = Self.cgFloat(
            "CMUX_TAB_CHROME_CLOSE_GLYPH_DX",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeDebugSettings.closeGlyphDX()
        )
        closeGlyphDY = Self.cgFloat(
            "CMUX_TAB_CHROME_CLOSE_GLYPH_DY",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeDebugSettings.closeGlyphDY()
        )
        closeCircleDX = Self.cgFloat(
            "CMUX_TAB_CHROME_CLOSE_CIRCLE_DX",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeDebugSettings.closeCircleDX()
        )
        closeCircleDY = Self.cgFloat(
            "CMUX_TAB_CHROME_CLOSE_CIRCLE_DY",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeAccessoryMetrics.baseCloseCircleDY
                + WorkspaceLayoutTabChromeDebugSettings.closeCircleDY()
        )
        closeCircleSizeDelta = Self.cgFloat(
            "CMUX_TAB_CHROME_CLOSE_CIRCLE_SIZE_DELTA",
            environment: environment,
            defaultValue: WorkspaceLayoutTabChromeDebugSettings.closeCircleSizeDelta()
        )
    }

    private static func cgFloat(
        _ key: String,
        environment: [String: String],
        defaultValue: CGFloat = 0
    ) -> CGFloat {
        guard let raw = environment[key], let value = Double(raw) else {
            return defaultValue
        }
        return CGFloat(value)
    }
}

private enum WorkspaceLayoutTabChromeTitleRenderer: String {
    case stringDraw
    case textKit

    static let current: WorkspaceLayoutTabChromeTitleRenderer = {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["CMUX_TAB_CHROME_TITLE_RENDERER"],
           let renderer = WorkspaceLayoutTabChromeTitleRenderer(rawValue: raw) {
            return renderer
        }
#endif
        return .stringDraw
    }()
}

private enum WorkspaceLayoutTabChromeTitleDrawMode: String {
    case current
    case noLeading
    case deviceMetrics
    case noLeadingDeviceMetrics
    case disableScreenFontSubstitution

    static let selected: WorkspaceLayoutTabChromeTitleDrawMode = {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["CMUX_TAB_CHROME_TITLE_DRAW_MODE"],
           let mode = WorkspaceLayoutTabChromeTitleDrawMode(rawValue: raw) {
            return mode
        }
#endif
        return .current
    }()

    var options: NSString.DrawingOptions {
        switch self {
        case .current:
            return [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        case .noLeading:
            return [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        case .deviceMetrics:
            return [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine, .usesDeviceMetrics]
        case .noLeadingDeviceMetrics:
            return [.usesLineFragmentOrigin, .truncatesLastVisibleLine, .usesDeviceMetrics]
        case .disableScreenFontSubstitution:
            return [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine, .disableScreenFontSubstitution]
        }
    }
}

private enum WorkspaceLayoutTabChromeContentRenderer: String {
    case customDraw
    case appKitSubviews

    static let current: WorkspaceLayoutTabChromeContentRenderer = {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["CMUX_TAB_CHROME_CONTENT_RENDERER"],
           let renderer = WorkspaceLayoutTabChromeContentRenderer(rawValue: raw) {
            return renderer
        }
#endif
        return .appKitSubviews
    }()
}

private enum WorkspaceLayoutTabChromeSubviewTitleRenderer: String {
    case label
    case draw

    static let current: WorkspaceLayoutTabChromeSubviewTitleRenderer = {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["CMUX_TAB_CHROME_SUBVIEW_TITLE_RENDERER"],
           let renderer = WorkspaceLayoutTabChromeSubviewTitleRenderer(rawValue: raw) {
            return renderer
        }
#endif
        return .draw
    }()
}

private enum WorkspaceLayoutTabChromeTitleSource: String {
    case auto
    case draw
    case label

    static let current: WorkspaceLayoutTabChromeTitleSource = {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["CMUX_TAB_CHROME_TITLE_SOURCE"],
           let source = WorkspaceLayoutTabChromeTitleSource(rawValue: raw) {
            return source
        }
#endif
        return .draw
    }()
}
#endif

@MainActor
struct WorkspaceLayoutNativeHost: NSViewRepresentable {
    @Bindable private var controller: WorkspaceLayoutController
    private let renderSnapshot: WorkspaceLayoutRenderSnapshot
    private let showSplitButtons: Bool
    private let onGeometryChange: ((_ isDragging: Bool) -> Void)?

    init(
        controller: WorkspaceLayoutController,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        showSplitButtons: Bool,
        onGeometryChange: ((_ isDragging: Bool) -> Void)?
    ) {
        self.controller = controller
        self.renderSnapshot = renderSnapshot
        self.showSplitButtons = showSplitButtons
        self.onGeometryChange = onGeometryChange
    }

    func makeNSView(context: Context) -> WorkspaceLayoutRootHostView {
        let view = WorkspaceLayoutRootHostView(
            controller: controller,
            renderSnapshot: renderSnapshot,
            showSplitButtons: showSplitButtons,
            onGeometryChange: onGeometryChange
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: WorkspaceLayoutRootHostView, context: Context) {
        nsView.update(
            controller: controller,
            renderSnapshot: renderSnapshot,
            showSplitButtons: showSplitButtons,
            onGeometryChange: onGeometryChange
        )
    }
}

@MainActor
final class WorkspaceLayoutRootHostView: NSView {
    private var controller: WorkspaceLayoutController
    private var renderSnapshot: WorkspaceLayoutRenderSnapshot
    private var showSplitButtons: Bool
    private var onGeometryChange: ((_ isDragging: Bool) -> Void)?

    private var currentRootView: NSView?
    private var paneHosts: [UUID: WorkspaceLayoutPaneHostView] = [:]
    private var splitHosts: [UUID: WorkspaceLayoutNativeSplitView] = [:]
    private var renderedPaneIds: Set<UUID> = []
    private var renderedSplitIds: Set<UUID> = []
    private var lastContainerFrame: CGRect = .zero

    init(
        controller: WorkspaceLayoutController,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        showSplitButtons: Bool,
        onGeometryChange: ((_ isDragging: Bool) -> Void)?
    ) {
        self.controller = controller
        self.renderSnapshot = renderSnapshot
        self.showSplitButtons = showSplitButtons
        self.onGeometryChange = onGeometryChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        updateBackground()
        rebuildTree()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        controller: WorkspaceLayoutController,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        showSplitButtons: Bool,
        onGeometryChange: ((_ isDragging: Bool) -> Void)?
    ) {
        self.controller = controller
        self.renderSnapshot = renderSnapshot
        self.showSplitButtons = showSplitButtons
        self.onGeometryChange = onGeometryChange
        isHidden = !controller.isInteractive
        updateBackground()
        rebuildTree()
        syncContainerFrameIfNeeded(isDragging: false)
    }

    override func layout() {
        super.layout()
        currentRootView?.frame = bounds
        syncContainerFrameIfNeeded(isDragging: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
#if DEBUG
        startupLog(
            "startup.root.windowMove host=\(Unmanaged.passUnretained(self).toOpaque()) " +
                "inWindow=\(window != nil ? 1 : 0)"
        )
#endif
        if window != nil {
            rebuildTree()
        }
        syncContainerFrameIfNeeded(isDragging: false)
    }

    private func updateBackground() {
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: controller.configuration.appearance
        ).cgColor
    }

    fileprivate func notifyGeometryChanged(isDragging: Bool) {
        syncContainerFrameIfNeeded(isDragging: isDragging)
        onGeometryChange?(isDragging)
    }

    private func syncContainerFrameIfNeeded(isDragging: Bool) {
        let frame = convert(bounds, to: nil)
        guard frame != lastContainerFrame else { return }
        lastContainerFrame = frame
        controller.setContainerFrame(frame)
        if !isDragging {
            onGeometryChange?(false)
        }
    }

    private func rebuildTree() {
        let nextPaneIds = renderSnapshot.root.paneIds
        let nextSplitIds = renderSnapshot.root.splitIds
        let topologyChanged = nextPaneIds != renderedPaneIds || nextSplitIds != renderedSplitIds

        if topologyChanged {
#if DEBUG
            startupLog(
                "startup.host.topologyChanged panes=\(nextPaneIds.count) splits=\(nextSplitIds.count)"
            )
            latencyLog(
                "cmd_d.host.topologyChanged",
                data: [
                    "panes": String(nextPaneIds.count),
                    "splits": String(nextSplitIds.count),
                ]
            )
#endif
        }

        let nextRootView = hostView(for: renderSnapshot.root)

        if currentRootView !== nextRootView {
            currentRootView?.removeFromSuperview()
            addSubview(nextRootView)
            currentRootView = nextRootView
        }

        currentRootView?.frame = bounds
        renderedPaneIds = nextPaneIds
        renderedSplitIds = nextSplitIds
        cleanupUnusedHosts()
    }

    private func cleanupUnusedHosts() {
        let livePaneIds = renderSnapshot.root.paneIds
        let liveSplitIds = renderSnapshot.root.splitIds

        for (id, host) in paneHosts where !livePaneIds.contains(id) {
            host.prepareForRemoval()
            if host.superview != nil {
                host.removeFromSuperview()
            }
            paneHosts.removeValue(forKey: id)
        }

        for (id, host) in splitHosts where !liveSplitIds.contains(id) {
            host.removeAllChildren()
            if host.superview != nil {
                host.removeFromSuperview()
            }
            splitHosts.removeValue(forKey: id)
        }
    }

    private func hostView(for node: WorkspaceLayoutRenderNodeSnapshot) -> NSView {
        switch node {
        case .pane(let snapshot):
            return paneHost(for: snapshot)
        case .split(let snapshot):
            return splitHost(for: snapshot)
        }
    }

    private func paneHost(for snapshot: WorkspaceLayoutPaneRenderSnapshot) -> WorkspaceLayoutPaneHostView {
        if let existing = paneHosts[snapshot.paneId.id] {
            existing.update(
                snapshot: snapshot,
                controller: controller
            )
            return existing
        }

        let host = WorkspaceLayoutPaneHostView(
            rootHost: self,
            snapshot: snapshot,
            controller: controller
        )
        paneHosts[snapshot.paneId.id] = host
        return host
    }

    private func splitHost(for snapshot: WorkspaceLayoutSplitRenderSnapshot) -> WorkspaceLayoutNativeSplitView {
        guard let split = workspaceSplitFindSplitState(
            in: controller.internalController.rootNode,
            id: snapshot.splitId
        ) else {
            preconditionFailure("Missing live split state for snapshot \(snapshot.splitId)")
        }

        if let existing = splitHosts[split.id] {
            existing.update(
                splitState: split,
                rootHost: self,
                firstChild: hostView(for: snapshot.first),
                secondChild: hostView(for: snapshot.second),
                appearance: controller.configuration.appearance
            )
            return existing
        }

        let host = WorkspaceLayoutNativeSplitView(
            splitState: split,
            rootHost: self,
            firstChild: hostView(for: snapshot.first),
            secondChild: hostView(for: snapshot.second),
            appearance: controller.configuration.appearance
        )
        splitHosts[split.id] = host
        return host
    }
}

private func workspaceSplitFindSplitState(in node: SplitNode, id: UUID) -> SplitState? {
    switch node {
    case .pane:
        return nil
    case .split(let split):
        if split.id == id {
            return split
        }
        return workspaceSplitFindSplitState(in: split.first, id: id)
            ?? workspaceSplitFindSplitState(in: split.second, id: id)
    }
}

@MainActor
private final class WorkspaceLayoutNativeSplitView: NSSplitView, NSSplitViewDelegate {
    private weak var rootHost: WorkspaceLayoutRootHostView?
    private var splitState: SplitState
    private var splitAppearance: WorkspaceLayoutConfiguration.Appearance

    private let firstContainer = NSView(frame: .zero)
    private let secondContainer = NSView(frame: .zero)
    private weak var firstChild: NSView?
    private weak var secondChild: NSView?

    private var lastAppliedPosition: CGFloat
    private var isSyncingProgrammatically = false
    private var didApplyInitialDividerPosition = false
    private var initialDividerApplyAttempts = 0
    private var isAnimatingEntry = false

    init(
        splitState: SplitState,
        rootHost: WorkspaceLayoutRootHostView,
        firstChild: NSView,
        secondChild: NSView,
        appearance: WorkspaceLayoutConfiguration.Appearance
    ) {
        self.splitState = splitState
        self.rootHost = rootHost
        self.splitAppearance = appearance
        self.lastAppliedPosition = splitState.dividerPosition
        super.init(frame: .zero)
        delegate = self
        dividerStyle = .thin
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isVertical = splitState.orientation == .horizontal
        addArrangedSubview(firstContainer)
        addArrangedSubview(secondContainer)
        configure(container: firstContainer)
        configure(container: secondContainer)
        install(child: firstChild, in: firstContainer, current: &self.firstChild)
        install(child: secondChild, in: secondContainer, current: &self.secondChild)
        updateDividerColor()
        applyInitialDividerPositionIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        splitState: SplitState,
        rootHost: WorkspaceLayoutRootHostView,
        firstChild: NSView,
        secondChild: NSView,
        appearance: WorkspaceLayoutConfiguration.Appearance
    ) {
        if self.splitState.id != splitState.id {
            didApplyInitialDividerPosition = false
            initialDividerApplyAttempts = 0
            isAnimatingEntry = false
        }

        self.splitState = splitState
        self.rootHost = rootHost
        self.splitAppearance = appearance
        isHidden = rootHost.isHidden
        isVertical = splitState.orientation == .horizontal
        updateDividerColor()
        install(child: firstChild, in: firstContainer, current: &self.firstChild)
        install(child: secondChild, in: secondContainer, current: &self.secondChild)
        syncDividerPosition()
    }

    func removeAllChildren() {
        firstChild?.removeFromSuperview()
        secondChild?.removeFromSuperview()
    }

    override func layout() {
        super.layout()
        firstContainer.frame = arrangedSubviews.first?.frame ?? .zero
        secondContainer.frame = arrangedSubviews.dropFirst().first?.frame ?? .zero
        applyInitialDividerPositionIfNeeded()
    }

    private func configure(container: NSView) {
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = true
    }

    private func install(child: NSView, in container: NSView, current: inout NSView?) {
        if current !== child {
            current?.removeFromSuperview()
            if child.superview !== container {
                child.removeFromSuperview()
                container.addSubview(child)
            }
            current = child
        } else if child.superview !== container {
            child.removeFromSuperview()
            container.addSubview(child)
        }
        child.frame = container.bounds
        child.autoresizingMask = [.width, .height]
    }

    private func updateDividerColor() {
        if let layer {
            layer.backgroundColor = NSColor.clear.cgColor
        }
        needsDisplay = true
    }

    override var dividerColor: NSColor {
        TabBarColors.nsColorSeparator(for: splitAppearance)
    }

    private func applyInitialDividerPositionIfNeeded() {
        guard !didApplyInitialDividerPosition else { return }

        let available = availableSplitSize
        guard available > 0 else {
            initialDividerApplyAttempts += 1
            guard initialDividerApplyAttempts < 8 else {
                didApplyInitialDividerPosition = true
                splitState.animationOrigin = nil
                return
            }
            Task { @MainActor [weak self] in
                self?.applyInitialDividerPositionIfNeeded()
            }
            return
        }

        didApplyInitialDividerPosition = true
        let targetPosition = round(available * splitState.dividerPosition)

        guard splitAppearance.enableAnimations,
              let animationOrigin = splitState.animationOrigin else {
            setDividerPosition(targetPosition, layout: false)
            splitState.animationOrigin = nil
            return
        }

        let startPosition: CGFloat = animationOrigin == .fromFirst ? 0 : available
        splitState.animationOrigin = nil
        isAnimatingEntry = true
        setDividerPosition(startPosition, layout: true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            SplitAnimator.shared.animate(
                splitView: self,
                from: startPosition,
                to: targetPosition,
                duration: self.splitAppearance.animationDuration
            ) { [weak self] in
                guard let self else { return }
                self.isAnimatingEntry = false
                self.splitState.dividerPosition = min(max(self.splitState.dividerPosition, 0.1), 0.9)
                self.lastAppliedPosition = self.splitState.dividerPosition
                self.rootHost?.notifyGeometryChanged(isDragging: false)
            }
        }
    }

    private var availableSplitSize: CGFloat {
        let total = isVertical ? bounds.width : bounds.height
        return max(0, total - dividerThickness)
    }

    private func setDividerPosition(_ position: CGFloat, layout: Bool) {
        guard arrangedSubviews.count >= 2 else { return }
        isSyncingProgrammatically = true
        setPosition(position, ofDividerAt: 0)
        if layout {
            layoutSubtreeIfNeeded()
        }
        isSyncingProgrammatically = false
        lastAppliedPosition = availableSplitSize > 0 ? position / availableSplitSize : splitState.dividerPosition
    }

    private func syncDividerPosition() {
        guard !isAnimatingEntry else { return }
        let available = availableSplitSize
        guard available > 0 else { return }
        let desired = min(max(splitState.dividerPosition, 0.1), 0.9)
        guard abs(desired - lastAppliedPosition) > 0.0005 else { return }
        setDividerPosition(round(available * desired), layout: false)
    }

    private func normalizedDividerPosition() -> CGFloat {
        guard arrangedSubviews.count >= 2 else { return splitState.dividerPosition }
        let firstFrame = arrangedSubviews[0].frame
        let available = availableSplitSize
        guard available > 0 else { return splitState.dividerPosition }
        let occupied = isVertical ? firstFrame.width : firstFrame.height
        return min(max(occupied / available, 0.1), 0.9)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isSyncingProgrammatically else { return }
        let next = normalizedDividerPosition()
        splitState.dividerPosition = next
        lastAppliedPosition = next
        let eventType = NSApp.currentEvent?.type
        let isDragging = eventType == .leftMouseDragged
        rootHost?.notifyGeometryChanged(isDragging: isDragging)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let minimum = isVertical ? splitAppearance.minimumPaneWidth : splitAppearance.minimumPaneHeight
        return minimum
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let minimum = isVertical ? splitAppearance.minimumPaneWidth : splitAppearance.minimumPaneHeight
        let total = isVertical ? splitView.bounds.width : splitView.bounds.height
        return max(minimum, total - minimum - splitView.dividerThickness)
    }
}

@MainActor
private final class WorkspaceLayoutPaneHostView: NSView {
    private weak var rootHost: WorkspaceLayoutRootHostView?
    private var snapshot: WorkspaceLayoutPaneRenderSnapshot
    private var controller: WorkspaceLayoutController

    private let tabBarView = WorkspaceLayoutNativeTabBarView(frame: .zero)
    private let contentContainer = NSView(frame: .zero)
    private let dropOverlayView = WorkspaceLayoutPaneDropOverlayView(frame: .zero)
    private var mountedTabContent: [UUID: WorkspaceLayoutMountedPaneContent] = [:]
    private var activeDropZone: DropZone? = nil

    init(
        rootHost: WorkspaceLayoutRootHostView,
        snapshot: WorkspaceLayoutPaneRenderSnapshot,
        controller: WorkspaceLayoutController
    ) {
        self.rootHost = rootHost
        self.snapshot = snapshot
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(contentContainer)
        addSubview(tabBarView)
        addSubview(dropOverlayView)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        dropOverlayView.hitTestPassthroughEnabled = true
        update(
            snapshot: snapshot,
            controller: controller
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        snapshot: WorkspaceLayoutPaneRenderSnapshot,
        controller: WorkspaceLayoutController
    ) {
        self.snapshot = snapshot
        self.controller = controller
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: controller.configuration.appearance
        ).cgColor

        tabBarView.update(
            snapshot: snapshot.chrome,
            controller: controller
        )
        tabBarView.onTabMutation = { [weak self] in
            self?.refreshContent()
            self?.rootHost?.notifyGeometryChanged(isDragging: false)
        }

        dropOverlayView.update(
            paneId: snapshot.paneId,
            controller: controller,
            activeDropZone: activeDropZone,
            onZoneChanged: { [weak self] zone in
                self?.setActiveDropZone(zone)
            },
            onDropPerformed: { [weak self] in
                self?.setActiveDropZone(nil)
                self?.refreshContent()
                self?.rootHost?.notifyGeometryChanged(isDragging: false)
            }
        )

        refreshContent()
        needsLayout = true
    }

    func prepareForRemoval() {
        removeAllMountedTabContent()
    }

    override func layout() {
        super.layout()
        let barHeight = controller.configuration.appearance.tabBarHeight
        let topY = max(0, bounds.height - barHeight)
        tabBarView.frame = CGRect(x: 0, y: topY, width: bounds.width, height: barHeight)
        contentContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: topY)
        dropOverlayView.frame = contentContainer.frame
        for content in mountedTabContent.values {
            content.slotView.frame = contentContainer.bounds
        }
    }

    private func setActiveDropZone(_ zone: DropZone?) {
        guard activeDropZone != zone else { return }
        activeDropZone = zone
        dropOverlayView.activeDropZone = zone
        refreshContent()
    }

    private func refreshContent() {
        guard !snapshot.chrome.tabs.isEmpty else {
            removeAllMountedTabContent()
            refreshEmptyPaneContent()
            return
        }

        let selectedId = snapshot.chrome.selectedTabId ?? snapshot.chrome.tabs.first?.tab.id.id
        let targetIds = Set(snapshot.chrome.tabs.map(\.tab.id.id))
        for tabSnapshot in snapshot.chrome.tabs {
            refreshContent(for: tabSnapshot.tab, selectedId: selectedId)
        }

        for (tabId, content) in mountedTabContent where !targetIds.contains(tabId) {
            tearDownMountedContent(content)
            mountedTabContent.removeValue(forKey: tabId)
        }
    }

    private func refreshEmptyPaneContent() {
        dropOverlayView.prefersNativeDropOverlay = false
        guard let emptyPaneContent = snapshot.emptyPaneContent else { return }
        refreshHostedContent(
            rootView: rootView(for: emptyPaneContent),
            for: snapshot.paneId.id,
            isSelected: true
        )
    }

    private func removeAllMountedTabContent() {
        for content in mountedTabContent.values {
            tearDownMountedContent(content)
        }
        mountedTabContent.removeAll()
    }

    private func refreshContent(for tab: WorkspaceLayout.Tab, selectedId: UUID?) {
        let isSelected = tab.id.id == selectedId

        let paneContent = snapshot.paneContent(tabId: tab.id.id)
        if isSelected {
            dropOverlayView.prefersNativeDropOverlay = paneContent.prefersNativeDropOverlay
        }

        switch paneContent {
        case .terminal(let descriptor):
            refreshTerminalContent(
                descriptor,
                for: tab.id.id,
                isSelected: isSelected
            )
        case .browser(let descriptor):
            refreshBrowserContent(
                descriptor,
                for: tab.id.id,
                isSelected: isSelected
            )
        case .markdown(let descriptor):
            refreshHostedContent(rootView: rootView(for: .markdown(descriptor), isSelected: isSelected), for: tab.id.id, isSelected: isSelected)
        case .placeholder(let descriptor):
            refreshHostedContent(rootView: rootView(for: .placeholder(descriptor), isSelected: isSelected), for: tab.id.id, isSelected: isSelected)
        }
#if DEBUG
        if isSelected {
            let paneShort = String(snapshot.paneId.id.uuidString.prefix(5))
            let tabShort = String(tab.id.id.uuidString.prefix(5))
            startupLog(
                "startup.host.refreshContent pane=\(paneShort) " +
                    "tab=\(tabShort)"
            )
        }
#endif
    }

    private func rootView(for paneContent: WorkspacePaneContent, isSelected: Bool = true) -> AnyView {
        switch paneContent {
        case .markdown(let descriptor):
            return AnyView(
                MarkdownPanelView(
                    panel: descriptor.panel,
                    isVisibleInUI: descriptor.isVisibleInUI,
                    onRequestPanelFocus: descriptor.onRequestPanelFocus
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.paneDropZone, isSelected ? activeDropZone : nil)
                .transaction { tx in
                    tx.disablesAnimations = true
                }
                .animation(nil, value: snapshot.chrome.selectedTabId)
            )
        case .placeholder(let descriptor):
            return AnyView(
                EmptyPanelView(descriptor: descriptor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transaction { tx in
                        tx.disablesAnimations = true
                    }
                    .animation(nil, value: snapshot.chrome.selectedTabId)
            )
        case .terminal, .browser:
            preconditionFailure("Native pane content should not be hosted through NSHostingController")
        }
    }

    private func refreshTerminalContent(
        _ descriptor: WorkspaceTerminalPaneContent,
        for tabId: UUID,
        isSelected: Bool
    ) {
        let slotView: WorkspaceLayoutPaneContentSlotView
        if let existing = mountedTabContent[tabId],
           case .terminal(let previousDescriptor, let existingSlotView) = existing,
           previousDescriptor.panel === descriptor.panel {
            slotView = existingSlotView
        } else {
            if let existing = mountedTabContent[tabId] {
                tearDownMountedContent(existing)
            }
            let nextSlotView = WorkspaceLayoutPaneContentSlotView(frame: contentContainer.bounds)
            nextSlotView.autoresizingMask = [.width, .height]
            contentContainer.addSubview(nextSlotView)
            slotView = nextSlotView
        }

        mountedTabContent[tabId] = .terminal(descriptor: descriptor, slotView: slotView)
        applyTerminalContent(
            descriptor,
            slotView: slotView,
            isSelected: isSelected
        )
    }

    private func applyTerminalContent(
        _ descriptor: WorkspaceTerminalPaneContent,
        slotView: WorkspaceLayoutPaneContentSlotView,
        isSelected: Bool
    ) {
        if slotView.superview !== contentContainer {
            slotView.removeFromSuperview()
            contentContainer.addSubview(slotView)
        }
        slotView.frame = contentContainer.bounds

        let panel = descriptor.panel
        let hostedView = descriptor.panel.hostedView
        let hostIsWindowed = slotView.window != nil || contentContainer.window != nil
        if !hostIsWindowed {
            slotView.isHidden = !isSelected
#if DEBUG
            if isSelected {
                let paneShort = String(snapshot.paneId.id.uuidString.prefix(5))
                let panelShort = String(panel.id.uuidString.prefix(5))
                startupLog(
                    "startup.host.applyTerminal.skipOffWindow pane=\(paneShort) " +
                        "panel=\(panelShort) " +
                        "host=\(Unmanaged.passUnretained(self).toOpaque()) " +
                        "root=\(rootHost.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) } ?? "nil")"
                )
            }
#endif
            return
        }

        slotView.installContentView(hostedView)
        slotView.isHidden = !isSelected

        contentContainer.layoutSubtreeIfNeeded()
        slotView.layoutSubtreeIfNeeded()
        hostedView.layoutSubtreeIfNeeded()
        hostedView.attachSurface(panel.surface)

        let canWarmStartRuntime =
            panel.surface.surface == nil &&
            (isSelected || descriptor.isVisibleInUI) &&
            slotView.bounds.width > 1 &&
            slotView.bounds.height > 1
        if canWarmStartRuntime {
            _ = hostedView.reconcileGeometryNow()
            panel.surface.requestBackgroundSurfaceStartIfNeeded()
        }
        hostedView.setFocusHandler { descriptor.onFocus() }
        hostedView.setTriggerFlashHandler(descriptor.onTriggerFlash)
        hostedView.setInactiveOverlay(
            color: descriptor.appearance.unfocusedOverlayNSColor,
            opacity: CGFloat(descriptor.appearance.unfocusedOverlayOpacity),
            visible: descriptor.isSplit && !descriptor.isFocused
        )
        hostedView.setNotificationRing(visible: descriptor.hasUnreadNotification)
        hostedView.setSearchOverlay(searchState: panel.searchState)
        hostedView.syncKeyStateIndicator(text: descriptor.panel.surface.currentKeyStateIndicatorText)
        hostedView.setDropZoneOverlay(zone: isSelected ? activeDropZone : nil)
        hostedView.setVisibleInUI(isSelected ? descriptor.isVisibleInUI : false)
        hostedView.setActive(isSelected ? descriptor.isFocused : false)
        hostedView.resumeReparentFocusIfSuppressed()
#if DEBUG
        if isSelected {
            let paneShort = String(snapshot.paneId.id.uuidString.prefix(5))
            let panelShort = String(panel.id.uuidString.prefix(5))
            let visible = descriptor.isVisibleInUI ? 1 : 0
            let focused = descriptor.isFocused ? 1 : 0
            let hostWindow = slotView.window != nil ? 1 : 0
            let hostedWindow = hostedView.window != nil ? 1 : 0
            let runtime = panel.surface.surface != nil ? 1 : 0
            startupLog(
                "startup.host.applyTerminal pane=\(paneShort) panel=\(panelShort) " +
                    "visible=\(visible) focused=\(focused) hostWindow=\(hostWindow) " +
                    "hostedWindow=\(hostedWindow) runtime=\(runtime) " +
                    "host=\(Unmanaged.passUnretained(self).toOpaque()) " +
                    "root=\(rootHost.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) } ?? "nil")"
            )
            latencyLog(
                "cmd_d.host.applyTerminal",
                data: [
                    "focused": String(focused),
                    "hostWindow": String(hostWindow),
                    "hostedWindow": String(hostedWindow),
                    "pane": paneShort,
                    "panel": panelShort,
                    "runtime": String(runtime),
                    "visible": String(visible),
                ]
            )
        }
#endif
    }

    private func refreshBrowserContent(
        _ descriptor: WorkspaceBrowserPaneContent,
        for tabId: UUID,
        isSelected: Bool
    ) {
        let entry: WorkspaceLayoutMountedPaneContent
        if let existing = mountedTabContent[tabId],
           case .browser(let hostView, let slotView) = existing {
            hostView.update(
                descriptor: descriptor,
                activeDropZone: isSelected ? activeDropZone : nil,
                selectedTabId: snapshot.chrome.selectedTabId
            )
            slotView.installContentView(hostView)
            entry = .browser(hostView: hostView, slotView: slotView)
        } else {
            if let existing = mountedTabContent[tabId] {
                tearDownMountedContent(existing)
            }
            let hostView = BrowserPanelWorkspaceContentView(frame: contentContainer.bounds)
            hostView.update(
                descriptor: descriptor,
                activeDropZone: isSelected ? activeDropZone : nil,
                selectedTabId: snapshot.chrome.selectedTabId
            )

            let slotView = WorkspaceLayoutPaneContentSlotView(frame: contentContainer.bounds)
            slotView.autoresizingMask = [.width, .height]
            slotView.installContentView(hostView)
            contentContainer.addSubview(slotView)

            entry = .browser(hostView: hostView, slotView: slotView)
            mountedTabContent[tabId] = entry
        }

        guard case .browser(let hostView, let slotView) = entry else { return }
        if slotView.superview !== contentContainer {
            slotView.removeFromSuperview()
            contentContainer.addSubview(slotView)
        }
        hostView.frame = contentContainer.bounds
        slotView.frame = contentContainer.bounds
        slotView.isHidden = !isSelected
    }

    private func refreshHostedContent(
        rootView: AnyView,
        for tabId: UUID,
        isSelected: Bool
    ) {
        let entry: WorkspaceLayoutMountedPaneContent
        if let existing = mountedTabContent[tabId],
           case .hosting(let hostingController, let slotView) = existing {
            hostingController.rootView = rootView
            slotView.installContentView(hostingController.view)
            entry = .hosting(hostingController: hostingController, slotView: slotView)
        } else {
            if let existing = mountedTabContent[tabId] {
                tearDownMountedContent(existing)
            }
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = true
            hostingController.view.autoresizingMask = [.width, .height]
            hostingController.view.frame = contentContainer.bounds

            let slotView = WorkspaceLayoutPaneContentSlotView(frame: contentContainer.bounds)
            slotView.autoresizingMask = [.width, .height]
            slotView.installContentView(hostingController.view)
            contentContainer.addSubview(slotView)

            entry = .hosting(hostingController: hostingController, slotView: slotView)
            mountedTabContent[tabId] = entry
        }

        guard case .hosting(_, let slotView) = entry else { return }
        if slotView.superview !== contentContainer {
            slotView.removeFromSuperview()
            contentContainer.addSubview(slotView)
        }
        slotView.frame = contentContainer.bounds
        slotView.isHidden = !isSelected
    }

    private func tearDownMountedContent(_ content: WorkspaceLayoutMountedPaneContent) {
        switch content {
        case .terminal(let descriptor, let slotView):
            let hostedView = descriptor.panel.hostedView
            hostedView.setDropZoneOverlay(zone: nil)
            hostedView.setVisibleInUI(false)
            hostedView.setActive(false)
            hostedView.setFocusHandler(nil)
            hostedView.setTriggerFlashHandler(nil)
            hostedView.removeFromSuperview()
            slotView.removeFromSuperview()
        case .browser(let hostView, let slotView):
            hostView.prepareForRemoval(reason: "workspaceHostRemoval")
            hostView.removeFromSuperview()
            slotView.removeFromSuperview()
        case .hosting(let hostingController, let slotView):
            hostingController.view.removeFromSuperview()
            slotView.removeFromSuperview()
        }
    }
}

@MainActor
private final class WorkspaceLayoutPaneContentSlotView: NSView {
    private var installedContentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installContentView(_ view: NSView) {
        if installedContentView !== view {
            installedContentView?.removeFromSuperview()
            if view.superview !== self {
                view.removeFromSuperview()
                addSubview(view)
            }
            installedContentView = view
        } else if view.superview !== self {
            view.removeFromSuperview()
            addSubview(view)
        }

        view.frame = bounds
        view.autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        installedContentView?.frame = bounds
    }
}

@MainActor
private enum WorkspaceLayoutMountedPaneContent {
    case terminal(descriptor: WorkspaceTerminalPaneContent, slotView: WorkspaceLayoutPaneContentSlotView)
    case browser(hostView: BrowserPanelWorkspaceContentView, slotView: WorkspaceLayoutPaneContentSlotView)
    case hosting(hostingController: NSHostingController<AnyView>, slotView: WorkspaceLayoutPaneContentSlotView)

    var slotView: WorkspaceLayoutPaneContentSlotView {
        switch self {
        case .terminal(_, let slotView), .browser(_, let slotView), .hosting(_, let slotView):
            return slotView
        }
    }
}

@MainActor
private final class WorkspaceLayoutNativeTabBarView: NSView {
    private var snapshot: WorkspaceLayoutPaneChromeSnapshot?
    private var controller: WorkspaceLayoutController?

    private let scrollView = NSScrollView(frame: .zero)
    private let documentView = WorkspaceLayoutTabDocumentView(frame: .zero)
    private let splitButtonsView = NSStackView(frame: .zero)
    private var tabButtons: [WorkspaceLayoutNativeTabButtonView] = []
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
#if DEBUG
    private var debugLastSnapshotSignature: String?
#endif

    var onTabMutation: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        addSubview(scrollView)

        splitButtonsView.orientation = .horizontal
        splitButtonsView.spacing = 4
        addSubview(splitButtonsView)

        documentView.onRequestRebuild = { [weak self] in
            self?.rebuildButtons()
        }
        documentView.onDropPerformed = { [weak self] in
            self?.onTabMutation?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let next = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        trackingArea = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateSplitButtonsVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateSplitButtonsVisibility()
    }

    func update(
        snapshot: WorkspaceLayoutPaneChromeSnapshot,
        controller: WorkspaceLayoutController
    ) {
        self.snapshot = snapshot
        self.controller = controller
        wantsLayer = true
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: controller.configuration.appearance
        ).cgColor
#if DEBUG
        let selectedTitle = snapshot.tabs.first(where: { $0.tab.id.id == snapshot.selectedTabId })?.tab.title ?? ""
        let selectedPreview = snapshot.selectedTabId.map { String($0.uuidString.prefix(8)) } ?? "none"
        let signature =
            "pane=\(snapshot.paneId.id.uuidString.prefix(8)) " +
            "rev=\(snapshot.chromeRevision) " +
            "selected=\(selectedPreview) " +
            "title=\"\(workspaceLayoutDebugPreview(selectedTitle))\" " +
            "count=\(snapshot.tabs.count)"
        if debugLastSnapshotSignature != signature {
            debugLastSnapshotSignature = signature
        }
#endif
        documentView.update(snapshot: snapshot, controller: controller)
        rebuildButtons()
        rebuildSplitButtons()
        updateSplitButtonsVisibility()
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard let controller else { return }
        let buttonWidth = splitButtonsView.isHidden ? 0 : splitButtonsView.fittingSize.width + 8
        scrollView.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - buttonWidth), height: bounds.height)
        splitButtonsView.frame = CGRect(
            x: max(0, bounds.width - buttonWidth),
            y: 0,
            width: buttonWidth,
            height: bounds.height
        )
        documentView.frame = CGRect(origin: .zero, size: CGSize(width: max(scrollView.contentSize.width, documentView.preferredContentWidth), height: bounds.height))
        documentView.needsLayout = true
        documentView.layoutSubtreeIfNeeded()
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: controller.configuration.appearance
        ).cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let controller else { return }
        let separatorColor = TabBarColors.nsColorSeparator(for: controller.configuration.appearance)
        separatorColor.setFill()
        let segments = separatorSegments(
            totalWidth: bounds.width,
            gap: selectedTabSeparatorGap()
        )
        if segments.left > 0 {
            CGRect(x: 0, y: 0, width: segments.left, height: 1).fill()
        }
        if segments.right > 0 {
            CGRect(
                x: bounds.width - segments.right,
                y: 0,
                width: segments.right,
                height: 1
            ).fill()
        }
    }

    private func separatorSegments(
        totalWidth: CGFloat,
        gap: ClosedRange<CGFloat>?
    ) -> (left: CGFloat, right: CGFloat) {
        let clampedTotal = max(0, totalWidth)
        guard let gap else {
            return (left: clampedTotal, right: 0)
        }

        let start = min(max(gap.lowerBound, 0), clampedTotal)
        let end = min(max(gap.upperBound, 0), clampedTotal)
        let normalizedStart = min(start, end)
        let normalizedEnd = max(start, end)
        return (
            left: max(0, normalizedStart),
            right: max(0, clampedTotal - normalizedEnd)
        )
    }

    private func selectedTabSeparatorGap() -> ClosedRange<CGFloat>? {
        guard let snapshot else { return nil }
        let selectedId = snapshot.selectedTabId
        guard let selectedId,
              let selectedButton = tabButtons.first(where: { $0.tab.id.id == selectedId }) else {
            return nil
        }

        let frameInBar = convert(selectedButton.bounds, from: selectedButton)
        guard frameInBar.maxX > 0, frameInBar.minX < bounds.width else {
            return nil
        }
        return frameInBar.minX...frameInBar.maxX
    }

    private func rebuildButtons() {
        guard let snapshot, let controller else { return }

        let existingById = Dictionary(uniqueKeysWithValues: tabButtons.map { ($0.tab.id, $0) })
        var nextButtons: [WorkspaceLayoutNativeTabButtonView] = []

        for tabSnapshot in snapshot.tabs {
            let tab = tabSnapshot.tab
            let button = existingById[tab.id] ?? WorkspaceLayoutNativeTabButtonView(frame: .zero)
            button.update(
                tab: tabSnapshot.tab,
                paneId: snapshot.paneId,
                isSelected: tabSnapshot.isSelected,
                showsZoomIndicator: tabSnapshot.showsZoomIndicator,
                appearance: controller.configuration.appearance,
                contextMenuState: tabSnapshot.contextMenuState,
                splitViewController: controller.internalController,
                onSelect: { [weak self] in
                    guard let self else { return }
                    controller.focusPane(snapshot.paneId)
                    controller.selectTab(tab.id)
                    self.onTabMutation?()
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    guard !tab.isPinned else { return }
                    controller.onTabCloseRequest?(tab.id, snapshot.paneId)
                    _ = controller.closeTab(tab.id, inPane: snapshot.paneId)
                    self.onTabMutation?()
                },
                onZoomToggle: { [weak self] in
                    guard let self else { return }
                    _ = controller.togglePaneZoom(inPane: snapshot.paneId)
                    self.onTabMutation?()
                },
                onContextAction: { [weak self] action in
                    guard let self else { return }
                    controller.requestTabContextAction(action, for: tab.id, inPane: snapshot.paneId)
                    self.onTabMutation?()
                }
            )
            nextButtons.append(button)
        }

        let nextIds = Set(nextButtons.map { $0.tab.id })
        for button in tabButtons where !nextIds.contains(button.tab.id) {
            button.removeFromSuperview()
        }

        tabButtons = nextButtons
        documentView.setTabButtons(tabButtons)
        documentView.needsLayout = true
        documentView.needsDisplay = true
        for button in tabButtons {
            button.needsLayout = true
            button.needsDisplay = true
        }
        needsLayout = true
        needsDisplay = true
        if let selected = snapshot.selectedTabId,
           let selectedButton = tabButtons.first(where: { $0.tab.id.id == selected }) {
            scrollView.contentView.scrollToVisible(selectedButton.frame.insetBy(dx: -32, dy: 0))
        }
    }

    private func rebuildSplitButtons() {
        guard let snapshot, let controller else { return }

        splitButtonsView.subviews.forEach { $0.removeFromSuperview() }
        guard snapshot.showSplitButtons else { return }

        let appearance = controller.configuration.appearance
        let tooltips = appearance.splitButtonTooltips

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "terminal",
                tooltip: tooltips.newTerminal,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                controller.requestNewTab(kind: .terminal, inPane: snapshot.paneId)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "globe",
                tooltip: tooltips.newBrowser,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                controller.requestNewTab(kind: .browser, inPane: snapshot.paneId)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "square.split.2x1",
                tooltip: tooltips.splitRight,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                _ = controller.splitPane(snapshot.paneId, orientation: .horizontal)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "square.split.1x2",
                tooltip: tooltips.splitDown,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                _ = controller.splitPane(snapshot.paneId, orientation: .vertical)
                self?.onTabMutation?()
            }
        )
    }

    private func updateSplitButtonsVisibility() {
        guard let controller, let snapshot else { return }
        let presentationMode = UserDefaults.standard.string(forKey: "workspacePresentationMode") ?? "standard"
        let isMinimalMode = presentationMode == "minimal"
        let shouldShow = snapshot.showSplitButtons && (!isMinimalMode || isHovering || !controller.configuration.appearance.splitButtonsOnHover)
        splitButtonsView.isHidden = !shouldShow
        needsLayout = true
    }
}

private func workspaceSplitMakeSymbolButton(
    symbolName: String,
    tooltip: String,
    color: NSColor,
    action: @escaping () -> Void
) -> NSButton {
    let button = NSButton(frame: .zero)
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: tooltip
    )
    button.contentTintColor = color
    button.toolTip = tooltip
    let target = ClosureSleeve(action)
    button.target = target
    button.action = #selector(ClosureSleeve.invoke)
    objc_setAssociatedObject(
        button,
        &workspaceSplitClosureSleeveAssociationKey,
        target,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    return button
}

private var workspaceSplitClosureSleeveAssociationKey: UInt8 = 0

private final class ClosureSleeve: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

@MainActor
private final class WorkspaceLayoutTabDocumentView: NSView {
    private var snapshot: WorkspaceLayoutPaneChromeSnapshot?
    private var controller: WorkspaceLayoutController?
    private var tabButtons: [WorkspaceLayoutNativeTabButtonView] = []
    private let dropIndicatorView = NSView(frame: .zero)

    var preferredContentWidth: CGFloat = 0
    var onRequestRebuild: (() -> Void)?
    var onDropPerformed: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)])
        dropIndicatorView.wantsLayer = true
        dropIndicatorView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicatorView.isHidden = true
        addSubview(dropIndicatorView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: WorkspaceLayoutPaneChromeSnapshot, controller: WorkspaceLayoutController) {
        self.snapshot = snapshot
        self.controller = controller
    }

    func setTabButtons(_ buttons: [WorkspaceLayoutNativeTabButtonView]) {
        tabButtons.forEach { if !buttons.contains($0) { $0.removeFromSuperview() } }
        tabButtons = buttons
        for button in buttons where button.superview !== self {
            addSubview(button)
        }
        addSubview(dropIndicatorView)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let controller else { return }
        let appearance = controller.configuration.appearance
        let leadingInset = appearance.tabBarLeadingInset
        var x = leadingInset

        for button in tabButtons {
            let width = button.preferredWidth(
                minWidth: appearance.tabMinWidth,
                maxWidth: appearance.tabMaxWidth
            )
            button.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width + appearance.tabSpacing
        }

        preferredContentWidth = max(bounds.width, x + 30)
        frame.size = CGSize(width: preferredContentWidth, height: bounds.height)
    }

    private func targetIndex(for point: NSPoint) -> Int {
        for (index, button) in tabButtons.enumerated() {
            if point.x < button.frame.midX {
                return index
            }
        }
        return tabButtons.count
    }

    private func updateDropIndicator(targetIndex: Int?) {
        guard let targetIndex else {
            dropIndicatorView.isHidden = true
            return
        }

        let x: CGFloat
        if targetIndex >= tabButtons.count {
            x = (tabButtons.last?.frame.maxX ?? 0) - 1
        } else {
            x = tabButtons[targetIndex].frame.minX - 1
        }

        dropIndicatorView.frame = CGRect(
            x: x,
            y: max(0, (bounds.height - TabBarMetrics.dropIndicatorHeight) / 2),
            width: TabBarMetrics.dropIndicatorWidth,
            height: TabBarMetrics.dropIndicatorHeight
        )
        dropIndicatorView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicatorView.isHidden = false
    }

    private func validateSplitTabDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let controller else { return false }
        guard controller.internalController.isInteractive else { return false }
        if controller.internalController.activeDragTabId != nil || controller.internalController.draggingTabId != nil {
            return true
        }
        guard let transfer = workspaceSplitDecodeTransfer(from: sender.draggingPasteboard),
              transfer.isFromCurrentProcess else {
            return false
        }
        return sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard validateSplitTabDrop(sender) else { return [] }
        updateDropIndicator(targetIndex: targetIndex(for: convert(sender.draggingLocation, from: nil)))
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard validateSplitTabDrop(sender) else { return [] }
        updateDropIndicator(targetIndex: targetIndex(for: convert(sender.draggingLocation, from: nil)))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateDropIndicator(targetIndex: nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        validateSplitTabDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let snapshot, let controller else { return false }
        let destinationIndex = targetIndex(for: convert(sender.draggingLocation, from: nil))

        if let draggedTabId = controller.internalController.activeDragTabId ?? controller.internalController.draggingTabId,
           let sourcePaneId = controller.internalController.activeDragSourcePaneId ?? controller.internalController.dragSourcePaneId {
            if sourcePaneId == snapshot.paneId,
               let sourceIndex = snapshot.tabs.firstIndex(where: { $0.tab.id == draggedTabId }),
               (destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1) {
                workspaceSplitClearDragState(controller.internalController)
                updateDropIndicator(targetIndex: nil)
                return true
            }

            if sourcePaneId == snapshot.paneId {
                _ = controller.moveTab(
                    draggedTabId,
                    toPane: snapshot.paneId,
                    atIndex: destinationIndex
                )
                controller.focusPane(snapshot.paneId)
            } else {
                _ = controller.moveTab(
                    draggedTabId,
                    toPane: snapshot.paneId,
                    atIndex: destinationIndex
                )
            }
            workspaceSplitClearDragState(controller.internalController)
            updateDropIndicator(targetIndex: nil)
            onDropPerformed?()
            return true
        }

        guard let transfer = workspaceSplitDecodeTransfer(from: sender.draggingPasteboard),
              transfer.isFromCurrentProcess else {
            updateDropIndicator(targetIndex: nil)
            return false
        }

        let request = WorkspaceLayoutController.ExternalTabDropRequest(
            tabId: transfer.tabId,
            sourcePaneId: PaneID(id: transfer.sourcePaneId),
            destination: .insert(targetPane: snapshot.paneId, targetIndex: destinationIndex)
        )
        let handled = controller.onExternalTabDrop?(request) ?? false
        updateDropIndicator(targetIndex: nil)
        if handled {
            onDropPerformed?()
        }
        return handled
    }
}

@MainActor
private final class WorkspaceLayoutHoverButton: NSControl {
    private var hoverTrackingArea: NSTrackingArea?
    private let iconView = NSImageView(frame: .zero)
    var onHoverChanged: ((Bool) -> Void)?
    var onPressedChanged: ((Bool) -> Void)?
    var rendersVisuals = true {
        didSet {
            if !rendersVisuals {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
            needsLayout = true
            needsDisplay = true
        }
    }
    var drawsCloseGlyph = false {
        didSet {
            iconView.isHidden = drawsCloseGlyph
            needsLayout = true
            needsDisplay = true
        }
    }
    var iconImage: NSImage? {
        didSet {
            iconView.image = iconImage
            needsLayout = true
            needsDisplay = true
        }
    }
    var iconTintColor: NSColor? {
        didSet {
            iconView.contentTintColor = iconTintColor
            needsDisplay = true
        }
    }
    var iconSize: CGFloat = TabBarMetrics.closeIconSize {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        guard rendersVisuals else {
            iconView.frame = .zero
            return
        }
        guard !drawsCloseGlyph else {
            iconView.frame = .zero
            return
        }
        let iconFrame = CGRect(
            x: (bounds.width - iconSize) / 2,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        iconView.frame = iconFrame
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard rendersVisuals, drawsCloseGlyph else { return }

        let strokeWidth = max(1.35, iconSize * 0.15)
        let maxGlyphDimension = min(bounds.width, bounds.height, iconSize)
        let armLength = max(0, min(iconSize * 0.325, (maxGlyphDimension - strokeWidth) / 2 - 0.35))
#if DEBUG
        let closeGlyphDX = WorkspaceLayoutTabChromeDebugTuning.current.closeGlyphDX
        let closeGlyphDY = WorkspaceLayoutTabChromeDebugTuning.current.closeGlyphDY
#else
        let closeGlyphDX: CGFloat = 0
        let closeGlyphDY: CGFloat = 0
#endif
        let center = CGPoint(x: bounds.midX + closeGlyphDX, y: bounds.midY + closeGlyphDY)
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: CGPoint(x: center.x - armLength, y: center.y - armLength))
        path.line(to: CGPoint(x: center.x + armLength, y: center.y + armLength))
        path.move(to: CGPoint(x: center.x - armLength, y: center.y + armLength))
        path.line(to: CGPoint(x: center.x + armLength, y: center.y - armLength))
        (iconTintColor ?? .labelColor).setStroke()
        path.stroke()
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let next = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        hoverTrackingArea = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onPressedChanged?(true)
        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self] nextEvent, stop in
            guard let self, let nextEvent else {
                stop.pointee = true
                return
            }
            let location = self.convert(nextEvent.locationInWindow, from: nil)
            let isInside = self.bounds.contains(location)
            switch nextEvent.type {
            case .leftMouseDragged:
                self.onPressedChanged?(isInside)
            case .leftMouseUp:
                self.onPressedChanged?(false)
                if isInside, let action = self.action {
                    _ = NSApp.sendAction(action, to: self.target, from: self)
                }
                stop.pointee = true
            default:
                break
            }
        }
    }
}

private final class WorkspaceLayoutZeroPaddingTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        rect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        rect
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        let size = super.cellSize(forBounds: rect)
        return NSSize(width: max(0, size.width - 4), height: size.height)
    }
}

@MainActor
final class WorkspaceLayoutNativeTabButtonView: NSView, NSDraggingSource {
    private(set) var tab: WorkspaceLayout.Tab = WorkspaceLayout.Tab(title: "")
    private var paneId: PaneID = PaneID()
    private var isSelected: Bool = false
    private var showsZoomIndicator: Bool = false
    private var splitAppearance: WorkspaceLayoutConfiguration.Appearance = .default
    private var contextMenuState = TabContextMenuState(
        isPinned: false,
        isUnread: false,
        isBrowser: false,
        isTerminal: false,
        hasCustomTitle: false,
        canCloseToLeft: false,
        canCloseToRight: false,
        canCloseOthers: false,
        canMoveToLeftPane: false,
        canMoveToRightPane: false,
        isZoomed: false,
        hasSplits: false,
        shortcuts: [:]
    )
    private weak var splitViewController: SplitViewController?
    private var onSelect: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onZoomToggle: (() -> Void)?
    private var onContextAction: ((TabContextAction) -> Void)?

    private let iconView = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(frame: .zero)
    private let closeButton = WorkspaceLayoutHoverButton(frame: .zero)
    private let zoomButton = WorkspaceLayoutHoverButton(frame: .zero)
    private let pinView = NSImageView(frame: .zero)
    private let dirtyDot = NSView(frame: .zero)
    private let unreadDot = NSView(frame: .zero)
    private let spinner = NSProgressIndicator(frame: .zero)
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isCloseHovered = false
    private var isZoomHovered = false
    private var isClosePressed = false
    private var isZoomPressed = false
    private var dragStartLocation: NSPoint?
    private var dragStarted = false
    private var spinnerTimer: Timer?
    private var debugFixedSpinnerPhase: CGFloat?
    private var iconUsesTemplateSymbol = false

    private var usesSubviewChrome: Bool {
        WorkspaceLayoutTabChromeContentRenderer.current == .appKitSubviews
    }

    private var usesSubviewTitleLabel: Bool {
        switch WorkspaceLayoutTabChromeTitleSource.current {
        case .label:
            return true
        case .draw:
            return false
        case .auto:
            return usesSubviewChrome && WorkspaceLayoutTabChromeSubviewTitleRenderer.current == .label
        }
    }

    private var titleFontSize: CGFloat {
#if DEBUG
        splitAppearance.tabTitleFontSize + WorkspaceLayoutTabChromeDebugTuning.current.titlePointSizeDelta
#else
        splitAppearance.tabTitleFontSize
#endif
    }

    private var accessoryFontSize: CGFloat {
        max(8, splitAppearance.tabTitleFontSize - 2)
    }

    private var accessorySlotSize: CGFloat {
        min(TabBarMetrics.tabHeight, max(TabBarMetrics.closeButtonSize, ceil(accessoryFontSize + 4)))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDebugSettingsChanged),
            name: .workspaceTabChromeDebugSettingsDidChange,
            object: nil
        )

        titleLabel.cell = WorkspaceLayoutZeroPaddingTextFieldCell(textCell: "")
        titleLabel.font = .systemFont(ofSize: splitAppearance.tabTitleFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.alphaValue = 0
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.usesSingleLineMode = true
        addSubview(titleLabel)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        iconView.alphaValue = 0
        addSubview(iconView)

        closeButton.drawsCloseGlyph = false
        closeButton.rendersVisuals = false
        closeButton.target = self
        closeButton.action = #selector(handleCloseButton)
        closeButton.layer?.cornerRadius = TabBarMetrics.closeButtonSize / 2
        closeButton.layer?.masksToBounds = true
        closeButton.onHoverChanged = { [weak self] hovering in
            guard let self else { return }
            self.isCloseHovered = hovering
            self.refreshChrome()
        }
        closeButton.onPressedChanged = { [weak self] pressed in
            guard let self else { return }
            self.isClosePressed = pressed
            self.refreshChrome()
        }
        addSubview(closeButton)

        zoomButton.iconImage = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Exit Zoom"
        )
        zoomButton.iconSize = TabBarMetrics.closeIconSize
        zoomButton.rendersVisuals = false
        zoomButton.target = self
        zoomButton.action = #selector(handleZoomButton)
        zoomButton.layer?.cornerRadius = TabBarMetrics.closeButtonSize / 2
        zoomButton.layer?.masksToBounds = true
        zoomButton.onHoverChanged = { [weak self] hovering in
            guard let self else { return }
            self.isZoomHovered = hovering
            self.refreshChrome()
        }
        zoomButton.onPressedChanged = { [weak self] pressed in
            guard let self else { return }
            self.isZoomPressed = pressed
            self.refreshChrome()
        }
        addSubview(zoomButton)

        pinView.image = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: "Pinned Tab"
        )
        pinView.imageScaling = .scaleProportionallyDown
        pinView.alphaValue = 0
        addSubview(pinView)

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = TabBarMetrics.dirtyIndicatorSize / 2
        dirtyDot.alphaValue = 0
        addSubview(dirtyDot)

        unreadDot.wantsLayer = true
        unreadDot.layer?.cornerRadius = TabBarMetrics.notificationBadgeSize / 2
        unreadDot.alphaValue = 0
        addSubview(unreadDot)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.alphaValue = 0
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        spinnerTimer?.invalidate()
    }

    @objc private func handleDebugSettingsChanged() {
        if superview != nil {
            superview?.needsLayout = true
            superview?.needsDisplay = true
        }
        needsLayout = true
        refreshChrome()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let next = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        trackingArea = next
        super.updateTrackingAreas()
    }

    func update(
        tab: WorkspaceLayout.Tab,
        paneId: PaneID,
        isSelected: Bool,
        showsZoomIndicator: Bool,
        appearance: WorkspaceLayoutConfiguration.Appearance,
        contextMenuState: TabContextMenuState,
        splitViewController: SplitViewController,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onZoomToggle: @escaping () -> Void,
        onContextAction: @escaping (TabContextAction) -> Void
    ) {
        self.tab = tab
        self.paneId = paneId
        self.isSelected = isSelected
        self.showsZoomIndicator = showsZoomIndicator
        self.splitAppearance = appearance
        self.contextMenuState = contextMenuState
        self.splitViewController = splitViewController
        self.onSelect = onSelect
        self.onClose = onClose
        self.onZoomToggle = onZoomToggle
        self.onContextAction = onContextAction

#if DEBUG
        let tuning = WorkspaceLayoutTabChromeDebugTuning.current
#else
        let tuning = (titlePointSizeDelta: CGFloat(0), titleKern: CGFloat(0), iconPointSizeDelta: CGFloat(-0.5))
#endif

        let titleFont = NSFont.systemFont(ofSize: titleFontSize)
        let titleColor = isSelected
            ? TabBarColors.nsColorActiveText(for: splitAppearance)
            : TabBarColors.nsColorInactiveText(for: splitAppearance)
        titleLabel.stringValue = tab.title
        titleLabel.font = titleFont
        titleLabel.textColor = titleColor

        if let imageData = tab.iconImageData,
           let image = NSImage(data: imageData) {
            image.isTemplate = false
            iconView.image = image
            iconView.contentTintColor = nil
            iconView.imageScaling = .scaleProportionallyDown
            iconUsesTemplateSymbol = false
        } else if let icon = tab.icon {
            iconView.image = workspaceSplitTemplateSymbolImage(
                named: icon,
                pointSize: symbolPointSize(for: icon) + tuning.iconPointSizeDelta,
                weight: .regular,
                fitting: CGSize(width: TabBarMetrics.iconSize, height: TabBarMetrics.iconSize)
            )
            iconView.contentTintColor = isSelected
                ? TabBarColors.nsColorActiveText(for: splitAppearance)
                : TabBarColors.nsColorInactiveText(for: splitAppearance)
            iconView.imageScaling = usesSubviewChrome ? .scaleNone : .scaleProportionallyDown
            iconUsesTemplateSymbol = true
        } else {
            iconView.image = nil
            iconUsesTemplateSymbol = false
        }

        closeButton.isHidden = tab.isPinned || !(isSelected || isHovered || isCloseHovered)
        if closeButton.isHidden {
            isCloseHovered = false
            isClosePressed = false
        }
        pinView.isHidden = !tab.isPinned || closeButton.isHidden == false
        zoomButton.isHidden = !showsZoomIndicator
        if zoomButton.isHidden {
            isZoomHovered = false
            isZoomPressed = false
        }

        unreadDot.isHidden = isSelected || isHovered || isCloseHovered || !tab.showsNotificationBadge
        dirtyDot.isHidden = isSelected || isHovered || isCloseHovered || !tab.isDirty
        unreadDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        dirtyDot.layer?.backgroundColor = TabBarColors.nsColorActiveText(for: splitAppearance).withAlphaComponent(0.72).cgColor

        if closeButton.rendersVisuals {
            closeButton.iconTintColor = (isCloseHovered || isClosePressed)
                ? TabBarColors.nsColorActiveText(for: splitAppearance)
                : TabBarColors.nsColorInactiveText(for: splitAppearance)
            closeButton.layer?.backgroundColor = closeButtonBackgroundColor().cgColor
        } else {
            closeButton.layer?.backgroundColor = NSColor.clear.cgColor
        }
        if zoomButton.rendersVisuals {
            zoomButton.iconTintColor = (isZoomHovered || isZoomPressed)
                ? TabBarColors.nsColorActiveText(for: splitAppearance)
                : TabBarColors.nsColorInactiveText(for: splitAppearance)
            zoomButton.layer?.backgroundColor = zoomButtonBackgroundColor().cgColor
        } else {
            zoomButton.layer?.backgroundColor = NSColor.clear.cgColor
        }
        pinView.contentTintColor = TabBarColors.nsColorInactiveText(for: splitAppearance)
        titleLabel.alphaValue = usesSubviewTitleLabel ? 1 : 0
        iconView.alphaValue = usesSubviewChrome && !tab.isLoading && iconView.image != nil ? 1 : 0
        pinView.alphaValue = 0
        spinner.alphaValue = 0
        syncSpinnerAnimation()

        needsLayout = true
        needsDisplay = true
    }

    func preferredWidth(minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: titleFontSize)
        ]
        let titleWidth = ceil((tab.title as NSString).size(withAttributes: titleAttributes).width)
        let trailingAccessoryWidth: CGFloat = showsZoomIndicator
            ? (accessorySlotSize * 2)
            : accessorySlotSize
        let titleToAccessorySpacing: CGFloat = showsZoomIndicator ? TabBarMetrics.contentSpacing : 0
        let chromeWidth =
            (TabBarMetrics.tabHorizontalPadding * 2)
            + TabBarMetrics.iconSize
            + TabBarMetrics.contentSpacing
            + trailingAccessoryWidth
            + titleToAccessorySpacing
        return min(maxWidth, max(minWidth, titleWidth + chromeWidth))
    }

    override func layout() {
        super.layout()
        let contentX = TabBarMetrics.tabHorizontalPadding
        let centerY = bounds.midY
#if DEBUG
        let tuning = WorkspaceLayoutTabChromeDebugTuning.current
#else
        let tuning = (titleDX: CGFloat(1), titleDY: CGFloat(0.375), iconDX: CGFloat(-1), iconDY: CGFloat(-0.875))
#endif

        let iconSlotRect = CGRect(
            x: contentX,
            y: centerY - (TabBarMetrics.iconSize / 2),
            width: TabBarMetrics.iconSize,
            height: TabBarMetrics.iconSize
        )
        if usesSubviewChrome, iconUsesTemplateSymbol, let image = iconView.image {
            iconView.frame = CGRect(
                x: round(iconSlotRect.midX - (image.size.width / 2) + tuning.iconDX),
                y: round(iconSlotRect.midY - (image.size.height / 2) + tuning.iconDY),
                width: image.size.width,
                height: image.size.height
            )
        } else {
            iconView.frame = iconSlotRect.offsetBy(dx: tuning.iconDX, dy: tuning.iconDY)
        }
        spinner.frame = CGRect(
            x: contentX,
            y: centerY - (TabBarMetrics.iconSize / 2),
            width: TabBarMetrics.iconSize,
            height: TabBarMetrics.iconSize
        )

        closeButton.frame = CGRect(
            x: bounds.maxX - TabBarMetrics.tabHorizontalPadding - accessorySlotSize,
            y: centerY - (accessorySlotSize / 2),
            width: accessorySlotSize,
            height: accessorySlotSize
        )
        closeButton.layer?.cornerRadius = closeButton.bounds.height / 2
        pinView.frame = closeButton.frame

        if showsZoomIndicator {
            zoomButton.frame = CGRect(
                x: closeButton.frame.minX - accessorySlotSize,
                y: centerY - (accessorySlotSize / 2),
                width: accessorySlotSize,
                height: accessorySlotSize
            )
            zoomButton.layer?.cornerRadius = zoomButton.bounds.height / 2
        } else {
            zoomButton.frame = .zero
        }

        let trailingAccessoryMinX = showsZoomIndicator ? zoomButton.frame.minX : closeButton.frame.minX
        let titleMinX = iconSlotRect.maxX + TabBarMetrics.contentSpacing
        let titleMaxX = trailingAccessoryMinX - (showsZoomIndicator ? TabBarMetrics.contentSpacing : 0)
        let titleFrameMinX = titleMinX + tuning.titleDX + tuning.iconDX
        titleLabel.frame = CGRect(
            x: titleFrameMinX,
            y: centerY - 7 + tuning.titleDY,
            width: max(0, titleMaxX - titleFrameMinX),
            height: 14
        )
        let indicatorStartX = bounds.maxX - TabBarMetrics.tabHorizontalPadding - accessorySlotSize
        unreadDot.frame = CGRect(
            x: indicatorStartX,
            y: centerY - (TabBarMetrics.notificationBadgeSize / 2),
            width: TabBarMetrics.notificationBadgeSize,
            height: TabBarMetrics.notificationBadgeSize
        )
        dirtyDot.frame = CGRect(
            x: unreadDot.isHidden
                ? indicatorStartX
                : unreadDot.frame.maxX + 2,
            y: centerY - (TabBarMetrics.dirtyIndicatorSize / 2),
            width: TabBarMetrics.dirtyIndicatorSize,
            height: TabBarMetrics.dirtyIndicatorSize
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let background: NSColor
        if isSelected {
            background = TabBarColors.nsColorPaneBackground(for: splitAppearance)
        } else if isHovered {
            background = workspaceSplitHoveredTabBackground(for: splitAppearance)
        } else {
            background = .clear
        }

        background.setFill()
        dirtyRect.fill()

        if isSelected {
            NSColor.controlAccentColor.setFill()
            CGRect(x: 0, y: bounds.height - TabBarMetrics.activeIndicatorHeight, width: bounds.width, height: TabBarMetrics.activeIndicatorHeight).fill()
        }

        TabBarColors.nsColorSeparator(for: splitAppearance).setFill()
        CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        drawTabChromeContent()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        refreshChrome()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isCloseHovered = false
        isZoomHovered = false
        isClosePressed = false
        isZoomPressed = false
        needsDisplay = true
        refreshChrome()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocation,
              !dragStarted,
              let splitViewController else { return }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - dragStartLocation.x, point.y - dragStartLocation.y)
        guard distance >= 3 else { return }
        dragStarted = true

        let transferTabId = tab.id
        splitViewController.dragGeneration += 1
        splitViewController.draggingTabId = transferTabId
        splitViewController.dragSourcePaneId = paneId
        splitViewController.activeDragTabId = transferTabId
        splitViewController.activeDragSourcePaneId = paneId

        let pasteboardItem = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(
            TabTransferData(tabId: transferTabId, sourcePaneId: paneId.id)
        ) {
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.tabTransfer.identifier))
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = workspaceSplitSnapshotImage(for: self) ?? NSImage(size: bounds.size)
        draggingItem.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartLocation = nil
            dragStarted = false
        }
        guard !dragStarted else { return }
        onSelect?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        workspaceSplitAddMenuItem("Rename Tab…", action: .rename, to: menu, handler: onContextAction)

        if contextMenuState.hasCustomTitle {
            workspaceSplitAddMenuItem("Remove Custom Tab Name", action: .clearName, to: menu, handler: onContextAction)
        }

        menu.addItem(.separator())
        workspaceSplitAddMenuItem("Close Tabs to Left", action: .closeToLeft, to: menu, enabled: contextMenuState.canCloseToLeft, handler: onContextAction)
        workspaceSplitAddMenuItem("Close Tabs to Right", action: .closeToRight, to: menu, enabled: contextMenuState.canCloseToRight, handler: onContextAction)
        workspaceSplitAddMenuItem("Close Other Tabs", action: .closeOthers, to: menu, enabled: contextMenuState.canCloseOthers, handler: onContextAction)
        workspaceSplitAddMenuItem("Move Tab…", action: .move, to: menu, handler: onContextAction)

        if contextMenuState.isTerminal {
            workspaceSplitAddMenuItem("Move to Left Pane", action: .moveToLeftPane, to: menu, enabled: contextMenuState.canMoveToLeftPane, handler: onContextAction)
            workspaceSplitAddMenuItem("Move to Right Pane", action: .moveToRightPane, to: menu, enabled: contextMenuState.canMoveToRightPane, handler: onContextAction)
        }

        menu.addItem(.separator())
        workspaceSplitAddMenuItem("New Terminal Tab to Right", action: .newTerminalToRight, to: menu, handler: onContextAction)
        workspaceSplitAddMenuItem("New Browser Tab to Right", action: .newBrowserToRight, to: menu, handler: onContextAction)

        if contextMenuState.isBrowser {
            menu.addItem(.separator())
            workspaceSplitAddMenuItem("Reload Tab", action: .reload, to: menu, handler: onContextAction)
            workspaceSplitAddMenuItem("Duplicate Tab", action: .duplicate, to: menu, handler: onContextAction)
        }

        menu.addItem(.separator())

        if contextMenuState.hasSplits {
            workspaceSplitAddMenuItem(
                contextMenuState.isZoomed ? "Exit Zoom" : "Zoom Pane",
                action: .toggleZoom,
                to: menu,
                handler: onContextAction
            )
        }

        workspaceSplitAddMenuItem(
            contextMenuState.isPinned ? "Unpin Tab" : "Pin Tab",
            action: .togglePin,
            to: menu,
            handler: onContextAction
        )

        if contextMenuState.isUnread {
            workspaceSplitAddMenuItem("Mark Tab as Read", action: .markAsRead, to: menu, enabled: contextMenuState.canMarkAsRead, handler: onContextAction)
        } else {
            workspaceSplitAddMenuItem("Mark Tab as Unread", action: .markAsUnread, to: menu, enabled: contextMenuState.canMarkAsUnread, handler: onContextAction)
        }

        return menu
    }

    @objc private func handleCloseButton() {
        onClose?()
    }

    @objc private func handleZoomButton() {
        onZoomToggle?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation == [] {
            splitViewController.map(workspaceSplitClearDragState)
        }
    }

    private func refreshChrome() {
        guard let splitViewController,
              let onSelect,
              let onClose,
              let onZoomToggle,
              let onContextAction else { return }
        update(
            tab: tab,
            paneId: paneId,
            isSelected: isSelected,
            showsZoomIndicator: showsZoomIndicator,
            appearance: splitAppearance,
            contextMenuState: contextMenuState,
            splitViewController: splitViewController,
            onSelect: onSelect,
            onClose: onClose,
            onZoomToggle: onZoomToggle,
            onContextAction: onContextAction
        )
    }

    private func syncSpinnerAnimation() {
        let shouldAnimate = tab.isLoading && debugFixedSpinnerPhase == nil
        if shouldAnimate {
            guard spinnerTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
            RunLoop.main.add(timer, forMode: .common)
            spinnerTimer = timer
        } else {
            spinnerTimer?.invalidate()
            spinnerTimer = nil
        }
    }

    private func drawTabChromeContent() {
        if !usesSubviewChrome {
            drawIconContent()
            if !usesSubviewTitleLabel {
                drawTitle()
            }
        } else {
            let tint = isSelected
                ? TabBarColors.nsColorActiveText(for: splitAppearance)
                : TabBarColors.nsColorInactiveText(for: splitAppearance)
            if tab.isLoading {
                drawLoadingSpinner(in: spinner.frame, color: tint)
            }
            if !usesSubviewTitleLabel {
                drawTitle()
            }
        }
        if showsZoomIndicator {
            drawAccessoryButton(
                in: zoomButton.frame,
                symbolName: "arrow.up.left.and.arrow.down.right",
                pointSize: TabBarMetrics.closeIconSize,
                isHovered: isZoomHovered,
                isPressed: isZoomPressed
            )
        }
        drawTrailingAccessory()
    }

    private func drawIconContent() {
#if DEBUG
        let tuning = WorkspaceLayoutTabChromeDebugTuning.current
#else
        let tuning = (iconPointSizeDelta: CGFloat(-0.5))
#endif
        let tint = isSelected
            ? TabBarColors.nsColorActiveText(for: splitAppearance)
            : TabBarColors.nsColorInactiveText(for: splitAppearance)

        if tab.isLoading {
            drawLoadingSpinner(in: iconView.frame, color: tint)
            return
        }

        if let imageData = tab.iconImageData,
           let image = iconView.image ?? NSImage(data: imageData) {
            drawRasterIcon(image, in: iconView.frame)
            return
        }

        guard let iconName = tab.icon else { return }
        workspaceSplitDrawSymbol(
            named: iconName,
            pointSize: symbolPointSize(for: iconName) + tuning.iconPointSizeDelta,
            weight: .regular,
            color: tint,
            in: iconView.frame
        )
    }

    private func drawTitle() {
        guard !titleLabel.frame.isEmpty else { return }
#if DEBUG
        let tuning = WorkspaceLayoutTabChromeDebugTuning.current
#else
        let tuning = (titlePointSizeDelta: CGFloat(0), titleKern: CGFloat(0))
#endif
        let rect = titleLabel.frame
        let font = NSFont.systemFont(ofSize: titleFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isSelected
                ? TabBarColors.nsColorActiveText(for: splitAppearance)
                : TabBarColors.nsColorInactiveText(for: splitAppearance),
            .paragraphStyle: paragraphStyle
        ]
        if abs(tuning.titleKern) > 0.0001 {
            attributes[.kern] = tuning.titleKern
        }
#if DEBUG
        switch WorkspaceLayoutTabChromeTitleRenderer.current {
        case .stringDraw:
            (tab.title as NSString).draw(
                with: rect,
                options: WorkspaceLayoutTabChromeTitleDrawMode.selected.options,
                attributes: attributes
            )
        case .textKit:
            drawTitleWithTextKit(in: rect, attributes: attributes)
        }
#else
        (tab.title as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: attributes
        )
#endif
    }

    private func drawTitleWithTextKit(in rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        let storage = NSTextStorage(string: tab.title, attributes: attributes)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        let container = NSTextContainer(size: rect.size)
        container.maximumNumberOfLines = 1
        container.lineBreakMode = .byTruncatingTail
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let glyphRange = layoutManager.glyphRange(for: container)
        let usedRect = layoutManager.usedRect(for: container)
        let drawOrigin = CGPoint(
            x: rect.minX,
            y: rect.minY + floor((rect.height - usedRect.height) / 2)
        )
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawOrigin)
    }

    private func drawTrailingAccessory() {
        if shouldShowIndicators {
            if !unreadDot.isHidden {
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: unreadDot.frame).fill()
            }
            if !dirtyDot.isHidden {
                TabBarColors.nsColorActiveText(for: splitAppearance)
                    .withAlphaComponent(0.72)
                    .setFill()
                NSBezierPath(ovalIn: dirtyDot.frame).fill()
            }
            return
        }

        if tab.isPinned {
            guard !pinView.isHidden else { return }
            workspaceSplitDrawSymbol(
                named: "pin.fill",
                pointSize: TabBarMetrics.closeIconSize,
                weight: .semibold,
                color: TabBarColors.nsColorInactiveText(for: splitAppearance),
                in: pinView.frame
            )
            return
        }

        guard !closeButton.isHidden else { return }
        drawAccessoryButton(
            in: closeButton.frame,
            symbolName: "xmark",
            pointSize: TabBarMetrics.closeIconSize,
            isHovered: isCloseHovered,
            isPressed: isClosePressed
        )
    }

    private var shouldShowIndicators: Bool {
        (!isSelected && !isHovered && !isCloseHovered) && (tab.isDirty || tab.showsNotificationBadge)
    }

    private func drawAccessoryButton(
        in rect: CGRect,
        symbolName: String,
        pointSize: CGFloat,
        isHovered: Bool,
        isPressed: Bool
    ) {
        workspaceSplitDrawAccessoryButton(
            in: rect,
            symbolName: symbolName,
            pointSize: pointSize,
            isHovered: isHovered,
            isPressed: isPressed,
            appearance: splitAppearance
        )
    }

    private func drawRasterIcon(_ image: NSImage, in rect: CGRect) {
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawLoadingSpinner(in rect: CGRect, color: NSColor) {
        let size = TabBarMetrics.iconSize * 0.86
        let spinnerRect = CGRect(
            x: rect.midX - (size / 2),
            y: rect.midY - (size / 2),
            width: size,
            height: size
        )
        let lineWidth = max(1.6, size * 0.14)
        let insetRect = spinnerRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let phase = debugFixedSpinnerPhase ?? CGFloat(
            (Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9) * 360.0
        )

        let ringPath = NSBezierPath(ovalIn: insetRect)
        ringPath.lineWidth = lineWidth
        color.withAlphaComponent(0.20).setStroke()
        ringPath.stroke()

        let arcPath = NSBezierPath()
        arcPath.appendArc(
            withCenter: CGPoint(x: insetRect.midX, y: insetRect.midY),
            radius: insetRect.width / 2,
            startAngle: phase,
            endAngle: phase + (360.0 * 0.28),
            clockwise: false
        )
        arcPath.lineWidth = lineWidth
        arcPath.lineCapStyle = .round
        color.setStroke()
        arcPath.stroke()
    }

    private func symbolPointSize(for iconName: String) -> CGFloat {
        if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
            return max(10, TabBarMetrics.iconSize - 2.5)
        }
        return TabBarMetrics.iconSize
    }

    func configureDebugInteractionState(
        isHovered: Bool,
        isCloseHovered: Bool,
        isClosePressed: Bool,
        isZoomHovered: Bool,
        isZoomPressed: Bool
    ) {
        self.isHovered = isHovered
        self.isCloseHovered = isCloseHovered
        self.isClosePressed = isClosePressed
        self.isZoomHovered = isZoomHovered
        self.isZoomPressed = isZoomPressed
        debugFixedSpinnerPhase = tab.isLoading ? 0 : nil
        refreshChrome()
    }

    private func closeButtonBackgroundColor() -> NSColor {
        if isClosePressed {
            return workspaceSplitPressedTabBackground(for: splitAppearance)
        }
        if isCloseHovered {
            return workspaceSplitHoveredTabBackground(for: splitAppearance)
        }
        return .clear
    }

    private func zoomButtonBackgroundColor() -> NSColor {
        if isZoomPressed {
            return workspaceSplitPressedTabBackground(for: splitAppearance)
        }
        if isZoomHovered {
            return workspaceSplitHoveredTabBackground(for: splitAppearance)
        }
        return .clear
    }
}

@MainActor
private final class WorkspaceLayoutPaneDropOverlayView: NSView {
    private var paneId: PaneID?
    private var controller: WorkspaceLayoutController?
    private var onZoneChanged: ((DropZone?) -> Void)?
    private var onDropPerformed: (() -> Void)?
    var activeDropZone: DropZone? {
        didSet {
            needsDisplay = true
        }
    }

    var prefersNativeDropOverlay = false {
        didSet {
            guard oldValue != prefersNativeDropOverlay else { return }
            needsDisplay = true
        }
    }

    var hitTestPassthroughEnabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(UTType.tabTransfer.identifier),
            .fileURL,
            .URL
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitTestPassthroughEnabled ? nil : super.hitTest(point)
    }

    func update(
        paneId: PaneID,
        controller: WorkspaceLayoutController,
        activeDropZone: DropZone?,
        onZoneChanged: @escaping (DropZone?) -> Void,
        onDropPerformed: @escaping () -> Void
    ) {
        self.paneId = paneId
        self.controller = controller
        self.activeDropZone = activeDropZone
        self.onZoneChanged = onZoneChanged
        self.onDropPerformed = onDropPerformed
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let zone = activeDropZone else { return }
        // Native pane hosts (for example terminal) can render their own drop overlay.
        // Skip split-host fallback paint in that case.
        if prefersNativeDropOverlay {
            return
        }
        let frame = WorkspacePaneDropRouting.overlayFrame(for: zone, in: bounds.size)
        let path = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let paneId, let controller else { return [] }
        guard controller.internalController.isInteractive else { return [] }

        if sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil {
            guard controller.internalController.activeDragTabId != nil
                || controller.internalController.draggingTabId != nil
                || workspaceSplitDecodeTransfer(from: sender.draggingPasteboard)?.isFromCurrentProcess == true else {
                return []
            }
            let location = convert(sender.draggingLocation, from: nil)
            let sourcePaneId = controller.internalController.activeDragSourcePaneId
                ?? controller.internalController.dragSourcePaneId
            let decision = WorkspacePaneDropRouting.decision(
                for: location,
                in: bounds.size,
                targetPaneId: paneId,
                sourcePaneId: sourcePaneId
            )
            let zone = decision.finalZone
            activeDropZone = zone
            onZoneChanged?(zone)
            return .move
        }

        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        if let urls, !urls.isEmpty {
            activeDropZone = .center
            onZoneChanged?(.center)
            return .copy
        }

        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        activeDropZone = nil
        onZoneChanged?(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let paneId, let controller else { return false }

        if sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil {
            let zone = activeDropZone ?? WorkspacePaneDropRouting.zone(
                for: convert(sender.draggingLocation, from: nil),
                in: bounds.size
            )

            if let draggedTabId = controller.internalController.activeDragTabId ?? controller.internalController.draggingTabId,
               let sourcePaneId = controller.internalController.activeDragSourcePaneId ?? controller.internalController.dragSourcePaneId {
                workspaceSplitClearDragState(controller.internalController)
                activeDropZone = nil
                onZoneChanged?(nil)

                if zone == .center {
                    if sourcePaneId != paneId {
                        _ = controller.moveTab(draggedTabId, toPane: paneId, atIndex: nil)
                    }
                    onDropPerformed?()
                    return true
                }

                guard let orientation = zone.orientation else { return false }
                _ = controller.splitPane(
                    paneId,
                    orientation: orientation,
                    movingTab: draggedTabId,
                    insertFirst: zone.insertsFirst
                )
                onDropPerformed?()
                return true
            }

            guard let transfer = workspaceSplitDecodeTransfer(from: sender.draggingPasteboard),
                  transfer.isFromCurrentProcess else {
                activeDropZone = nil
                onZoneChanged?(nil)
                return false
            }

            let destination: WorkspaceLayoutController.ExternalTabDropRequest.Destination
            if zone == .center {
                destination = .insert(targetPane: paneId, targetIndex: nil)
            } else if let orientation = zone.orientation {
                destination = .split(targetPane: paneId, orientation: orientation, insertFirst: zone.insertsFirst)
            } else {
                return false
            }

            let request = WorkspaceLayoutController.ExternalTabDropRequest(
                tabId: transfer.tabId,
                sourcePaneId: PaneID(id: transfer.sourcePaneId),
                destination: destination
            )
            let handled = controller.onExternalTabDrop?(request) ?? false
            activeDropZone = nil
            onZoneChanged?(nil)
            if handled {
                onDropPerformed?()
            }
            return handled
        }

        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let handled = controller.onFileDrop?(urls, paneId) ?? false
        activeDropZone = nil
        onZoneChanged?(nil)
        if handled {
            onDropPerformed?()
        }
        return handled
    }
}

private func workspaceSplitSymbolImage(named name: String) -> NSImage? {
    let size = (name == "terminal.fill" || name == "terminal" || name == "globe")
        ? max(10, TabBarMetrics.iconSize - 2.5)
        : TabBarMetrics.iconSize
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
}

private func workspaceSplitTemplateSymbolImage(
    named name: String,
    pointSize: CGFloat,
    weight: NSFont.Weight,
    fitting slotSize: CGSize? = nil
) -> NSImage? {
    func image(for candidatePointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: candidatePointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    guard let slotSize else {
        return image(for: pointSize)
    }

    var candidatePointSize = pointSize
    var lastImage: NSImage?
    while candidatePointSize >= 1 {
        guard let candidate = image(for: candidatePointSize) else { break }
        lastImage = candidate
        if candidate.size.width <= slotSize.width, candidate.size.height <= slotSize.height {
            return candidate
        }
        candidatePointSize -= 0.5
    }
    return lastImage
}

private func workspaceSplitSymbolImage(
    named name: String,
    pointSize: CGFloat,
    weight: NSFont.Weight,
    color: NSColor
) -> NSImage? {
    let pointConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [color])
    let configuration = pointConfiguration.applying(colorConfiguration)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
}

private func workspaceSplitDrawSymbol(
    named name: String,
    pointSize: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    in slotRect: CGRect
) {
    guard let image = workspaceSplitSymbolImage(
        named: name,
        pointSize: pointSize,
        weight: weight,
        color: color
    ) else {
        return
    }
    let fittedSize: CGSize
    if image.size.width > slotRect.width || image.size.height > slotRect.height {
        let scale = min(slotRect.width / image.size.width, slotRect.height / image.size.height)
        fittedSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    } else {
        fittedSize = image.size
    }
    let fittedScale = image.size.width > 0 ? fittedSize.width / image.size.width : 1
    let opticalCenterOffset = name == "xmark"
        ? workspaceLayoutVisibleAlphaCenterOffset(for: image).applying(
            CGAffineTransform(scaleX: fittedScale, y: fittedScale)
        )
        : .zero
    let drawRect = CGRect(
        x: slotRect.midX - (fittedSize.width / 2) + opticalCenterOffset.x,
        y: slotRect.midY - (fittedSize.height / 2) + opticalCenterOffset.y,
        width: fittedSize.width,
        height: fittedSize.height
    )
    image.draw(
        in: drawRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func workspaceLayoutVisibleAlphaCenterOffset(
    for image: NSImage,
    alphaThreshold: UInt8 = 8
) -> CGPoint {
    guard let buffer = workspaceLayoutRGBAImageBuffer(from: image) else { return .zero }
    var minX = buffer.width
    var minY = buffer.height
    var maxX = -1
    var maxY = -1

    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            let base = ((y * buffer.width) + x) * 4
            if buffer.bytes[base + 3] <= alphaThreshold {
                continue
            }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else { return .zero }

    let imageCenterX = CGFloat(buffer.width) / 2
    let imageCenterY = CGFloat(buffer.height) / 2
    let visibleCenterX = CGFloat(minX + maxX + 1) / 2
    let visibleCenterY = CGFloat(minY + maxY + 1) / 2
    let pointScaleX = image.size.width / CGFloat(buffer.width)
    let pointScaleY = image.size.height / CGFloat(buffer.height)

    return CGPoint(
        x: (imageCenterX - visibleCenterX) * pointScaleX,
        y: (imageCenterY - visibleCenterY) * pointScaleY
    )
}

private func workspaceSplitAddMenuItem(
    _ title: String,
    action: TabContextAction,
    to menu: NSMenu,
    enabled: Bool = true,
    handler: ((TabContextAction) -> Void)?
) {
    let item = NSMenuItem(title: title, action: #selector(ClosureMenuTarget.invoke(_:)), keyEquivalent: "")
    let target = ClosureMenuTarget {
        handler?(action)
    }
    item.target = target
    item.isEnabled = enabled
    objc_setAssociatedObject(item, Unmanaged.passUnretained(item).toOpaque(), target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    menu.addItem(item)
}

private final class ClosureMenuTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke(_ sender: Any?) {
        handler()
    }
}

struct WorkspaceLayoutTabChromeDebugScenario: Identifiable {
    let id: String
    let title: String
    let tab: WorkspaceLayout.Tab
    let isSelected: Bool
    let isHovered: Bool
    let isCloseHovered: Bool
    let isClosePressed: Bool
    let showsZoomIndicator: Bool
    let isZoomHovered: Bool
    let isZoomPressed: Bool
    let appearance: WorkspaceLayoutConfiguration.Appearance
}

struct WorkspaceLayoutTabChromeDebugDiffMetrics: Codable, Hashable {
    let width: Int
    let height: Int
    let differingPixelCount: Int
    let totalPixelCount: Int
    let maxChannelDelta: Int
    let meanAbsoluteChannelDelta: Double
    let matchingPixels: Bool
}

struct WorkspaceLayoutTabChromeDebugExportScenarioResult: Codable {
    let id: String
    let title: String
    let appKitPNG: String
    let scenario: WorkspaceLayoutTabChromeDebugScenarioSpec
}

struct WorkspaceLayoutTabChromeDebugExportManifest: Codable {
    let generatedAt: String
    let scenarioResults: [WorkspaceLayoutTabChromeDebugExportScenarioResult]
}

struct WorkspaceLayoutTabChromeDebugScenarioSpec: Codable {
    let tab: WorkspaceLayoutTabChromeDebugTabSpec
    let isSelected: Bool
    let isHovered: Bool
    let isCloseHovered: Bool
    let isClosePressed: Bool
    let showsZoomIndicator: Bool
    let isZoomHovered: Bool
    let isZoomPressed: Bool
    let appearance: WorkspaceLayoutTabChromeDebugAppearanceSpec
}

struct WorkspaceLayoutTabChromeDebugTabSpec: Codable {
    let id: UUID
    let title: String
    let hasCustomTitle: Bool
    let icon: String?
    let iconImageDataBase64: String?
    let kind: PanelType?
    let isDirty: Bool
    let showsNotificationBadge: Bool
    let isLoading: Bool
    let isPinned: Bool
}

struct WorkspaceLayoutTabChromeDebugAppearanceSpec: Codable {
    let tabBarHeight: Double
    let tabMinWidth: Double
    let tabMaxWidth: Double
    let tabTitleFontSize: Double
    let tabSpacing: Double
    let minimumPaneWidth: Double
    let minimumPaneHeight: Double
    let showSplitButtons: Bool
    let splitButtonsOnHover: Bool
    let tabBarLeadingInset: Double
    let splitButtonTooltips: WorkspaceLayoutTabChromeDebugSplitButtonTooltipsSpec
    let animationDuration: Double
    let enableAnimations: Bool
    let chromeColors: WorkspaceLayoutTabChromeDebugChromeColorsSpec
}

struct WorkspaceLayoutTabChromeDebugSplitButtonTooltipsSpec: Codable {
    let newTerminal: String
    let newBrowser: String
    let splitRight: String
    let splitDown: String
}

struct WorkspaceLayoutTabChromeDebugChromeColorsSpec: Codable {
    let backgroundHex: String?
    let borderHex: String?
}

private struct WorkspaceLayoutReferenceTabChromeView: View {
    let tab: WorkspaceLayout.Tab
    let isSelected: Bool
    let isHovered: Bool
    let isCloseHovered: Bool
    let isClosePressed: Bool
    let showsZoomIndicator: Bool
    let isZoomHovered: Bool
    let isZoomPressed: Bool
    let appearance: WorkspaceLayoutConfiguration.Appearance
    let fixedSpinnerPhase: Double?
    private let saturation: Double = 1.0

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: TabBarMetrics.contentSpacing) {
                let iconSlotSize = TabBarMetrics.iconSize
                let iconTint = isSelected
                    ? TabBarColors.activeText(for: appearance)
                    : TabBarColors.inactiveText(for: appearance)
                let faviconImage = decodedFaviconImage

                Group {
                    if tab.isLoading {
                        WorkspaceLayoutReferenceTabLoadingSpinner(
                            size: iconSlotSize * 0.86,
                            color: iconTint,
                            fixedPhaseDegrees: fixedSpinnerPhase
                        )
                    } else if let image = faviconImage {
                        WorkspaceLayoutReferenceFaviconIconView(image: image)
                            .frame(width: iconSlotSize, height: iconSlotSize, alignment: .center)
                            .clipped()
                    } else if let iconName = tab.icon {
                        Image(systemName: iconName)
                            .font(.system(size: glyphSize(for: iconName)))
                            .foregroundStyle(iconTint)
                    }
                }
                .saturation(WorkspaceLayoutReferenceTabItemStyling.iconSaturation(hasRasterIcon: faviconImage != nil, tabSaturation: saturation))
                .transaction { tx in
                    tx.animation = nil
                }
                .frame(width: iconSlotSize, height: iconSlotSize, alignment: .center)

                Text(tab.title)
                    .font(.system(size: appearance.tabTitleFontSize))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? TabBarColors.activeText(for: appearance)
                            : TabBarColors.inactiveText(for: appearance)
                    )
                    .saturation(saturation)

                if showsZoomIndicator {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: max(8, appearance.tabTitleFontSize - 2), weight: .semibold))
                        .foregroundStyle(
                            isZoomHovered
                                ? TabBarColors.activeText(for: appearance)
                                : TabBarColors.inactiveText(for: appearance)
                        )
                        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
                        .background(
                            Circle()
                                .fill(
                                    isZoomHovered
                                        ? TabBarColors.hoveredTabBackground(for: appearance)
                                        : .clear
                                )
                        )
                        .saturation(saturation)
                }
            }

            Spacer(minLength: 0)

            trailingAccessory
        }
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .offset(y: isSelected ? 0.5 : 0)
        .frame(
            minWidth: TabBarMetrics.tabMinWidth,
            maxWidth: TabBarMetrics.tabMaxWidth,
            minHeight: TabBarMetrics.tabHeight,
            maxHeight: TabBarMetrics.tabHeight
        )
        .padding(.bottom, isSelected ? 1 : 0)
        .background(tabBackground)
        .allowsHitTesting(false)
    }

    private var decodedFaviconImage: NSImage? {
        guard let data = tab.iconImageData,
              let image = NSImage(data: data) else {
            return nil
        }
        image.isTemplate = false
        return image
    }

    private func glyphSize(for iconName: String) -> CGFloat {
        if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
            return max(10, TabBarMetrics.iconSize - 2.5)
        }
        return TabBarMetrics.iconSize
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        closeOrDirtyIndicator
            .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
            .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isHovered)
            .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isCloseHovered)
    }

    @ViewBuilder
    private var tabBackground: some View {
        ZStack(alignment: .top) {
            if WorkspaceLayoutReferenceTabItemStyling.shouldShowHoverBackground(isHovered: isHovered, isSelected: isSelected) {
                Rectangle()
                    .fill(TabBarColors.hoveredTabBackground(for: appearance))
            } else {
                Color.clear
            }

            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: TabBarMetrics.activeIndicatorHeight)
            }

            HStack {
                Spacer()
                Rectangle()
                    .fill(TabBarColors.separator(for: appearance))
                    .frame(width: 1)
            }
        }
    }

    @ViewBuilder
    private var closeOrDirtyIndicator: some View {
        ZStack {
            if (!isSelected && !isHovered && !isCloseHovered) && (tab.isDirty || tab.showsNotificationBadge) {
                HStack(spacing: 2) {
                    if tab.showsNotificationBadge {
                        Circle()
                            .fill(TabBarColors.notificationBadge(for: appearance))
                            .frame(width: TabBarMetrics.notificationBadgeSize, height: TabBarMetrics.notificationBadgeSize)
                    }
                    if tab.isDirty {
                        Circle()
                            .fill(TabBarColors.dirtyIndicator(for: appearance))
                            .frame(width: TabBarMetrics.dirtyIndicatorSize, height: TabBarMetrics.dirtyIndicatorSize)
                            .saturation(saturation)
                    }
                }
            }

            if tab.isPinned {
                if isSelected || isHovered || isCloseHovered || (!tab.isDirty && !tab.showsNotificationBadge) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
                        .foregroundStyle(TabBarColors.inactiveText(for: appearance))
                        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
                        .saturation(saturation)
                }
            } else if isSelected || isHovered || isCloseHovered {
                Image(systemName: "xmark")
                    .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
                    .foregroundStyle(
                        isCloseHovered
                            ? TabBarColors.activeText(for: appearance)
                            : TabBarColors.inactiveText(for: appearance)
                    )
                    .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
                    .background(
                        Circle()
                            .fill(
                                isCloseHovered
                                    ? TabBarColors.hoveredTabBackground(for: appearance)
                                    : .clear
                            )
                    )
                    .saturation(saturation)
            }
        }
    }
}

private enum WorkspaceLayoutReferenceTabItemStyling {
    static func iconSaturation(hasRasterIcon: Bool, tabSaturation: Double) -> Double {
        hasRasterIcon ? 1.0 : tabSaturation
    }

    static func shouldShowHoverBackground(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered && !isSelected
    }
}

private struct WorkspaceLayoutReferenceTabLoadingSpinner: View {
    let size: CGFloat
    let color: Color
    let fixedPhaseDegrees: Double?

    var body: some View {
        TimelineView(.animation) { context in
            ZStack {
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0.0, to: 0.28)
                    .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(spinnerAngle(for: context.date)))
            }
            .frame(width: size, height: size)
        }
    }

    private var ringWidth: CGFloat {
        max(1.6, size * 0.14)
    }

    private func spinnerAngle(for date: Date) -> Double {
        if let fixedPhaseDegrees {
            return fixedPhaseDegrees
        }
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: 0.9) / 0.9) * 360.0
    }
}

private struct WorkspaceLayoutReferenceFaviconIconView: NSViewRepresentable {
    let image: NSImage

    final class ContainerView: NSView {
        let imageView = NSImageView(frame: .zero)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignCenter
            imageView.animates = false
            imageView.contentTintColor = nil
            imageView.autoresizingMask = [.width, .height]
            addSubview(imageView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            .zero
        }

        override func layout() {
            super.layout()
            imageView.frame = bounds.integral
        }
    }

    func makeNSView(context: Context) -> ContainerView {
        ContainerView(frame: .zero)
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        image.isTemplate = false
        if nsView.imageView.image !== image {
            nsView.imageView.image = image
        }
        nsView.imageView.contentTintColor = nil
    }
}

@MainActor
func workspaceLayoutTabChromeDebugScenarios() -> [WorkspaceLayoutTabChromeDebugScenario] {
    let baseAppearance = workspaceLayoutTabChromeDebugAppearance()
    let terminalTab = WorkspaceLayout.Tab(
        title: "~/fun/cmuxterm-hq",
        icon: "terminal.fill",
        kind: .terminal
    )

    let scenarios = [
        WorkspaceLayoutTabChromeDebugScenario(
            id: "selected-idle",
            title: "Selected Idle",
            tab: terminalTab,
            isSelected: true,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "selected-close-hover",
            title: "Selected Close Hover",
            tab: terminalTab,
            isSelected: true,
            isHovered: false,
            isCloseHovered: true,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "selected-close-pressed",
            title: "Selected Close Pressed",
            tab: terminalTab,
            isSelected: true,
            isHovered: false,
            isCloseHovered: true,
            isClosePressed: true,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "unselected-idle",
            title: "Unselected Idle",
            tab: terminalTab,
            isSelected: false,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "unselected-hover",
            title: "Unselected Hover",
            tab: terminalTab,
            isSelected: false,
            isHovered: true,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "unselected-close-hover",
            title: "Unselected Close Hover",
            tab: terminalTab,
            isSelected: false,
            isHovered: true,
            isCloseHovered: true,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "dirty-unread",
            title: "Dirty + Unread",
            tab: WorkspaceLayout.Tab(
                title: "~/fun/cmuxterm-hq",
                icon: "terminal.fill",
                kind: .terminal,
                isDirty: true,
                showsNotificationBadge: true
            ),
            isSelected: false,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "pinned",
            title: "Pinned",
            tab: WorkspaceLayout.Tab(
                title: "Pinned shell",
                icon: "terminal.fill",
                kind: .terminal,
                isPinned: true
            ),
            isSelected: false,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "zoomed",
            title: "Zoomed",
            tab: terminalTab,
            isSelected: true,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: true,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "loading",
            title: "Loading",
            tab: WorkspaceLayout.Tab(
                title: "Loading shell",
                icon: "terminal.fill",
                kind: .terminal,
                isLoading: true
            ),
            isSelected: true,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
        WorkspaceLayoutTabChromeDebugScenario(
            id: "long-title",
            title: "Long Title",
            tab: WorkspaceLayout.Tab(
                title: "lawrence@Mac:~/fun/cmuxterm-hq",
                icon: "terminal.fill",
                kind: .terminal
            ),
            isSelected: true,
            isHovered: false,
            isCloseHovered: false,
            isClosePressed: false,
            showsZoomIndicator: false,
            isZoomHovered: false,
            isZoomPressed: false,
            appearance: baseAppearance
        ),
    ]

#if DEBUG
    let environment = ProcessInfo.processInfo.environment
    if let rawFilter = environment["CMUX_WORKSPACE_TAB_CHROME_SCENARIO_IDS"]?
        .split(separator: ",")
        .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        .filter({ !$0.isEmpty }),
       !rawFilter.isEmpty {
        let allowed = Set(rawFilter)
        return scenarios.filter { allowed.contains($0.id) }
    }
#endif

    return scenarios
}

@MainActor
func workspaceLayoutTabChromeDebugAppearance() -> WorkspaceLayoutConfiguration.Appearance {
    WorkspaceLayoutConfiguration.Appearance(
        chromeColors: .init(
            backgroundHex: Workspace.splitChromeHex(
                backgroundColor: GhosttyApp.shared.defaultBackgroundColor,
                backgroundOpacity: GhosttyApp.shared.defaultBackgroundOpacity
            )
        )
    )
}

@MainActor
func workspaceLayoutRenderAppKitTabChromeImage(
    scenario: WorkspaceLayoutTabChromeDebugScenario,
    scale: CGFloat = 2
) -> NSImage? {
    let pane = PaneState(
        tabs: [TabItem(id: scenario.tab.id.id, title: scenario.tab.title, isPinned: scenario.tab.isPinned)],
        selectedTabId: scenario.isSelected ? scenario.tab.id.id : nil
    )
    let splitController = SplitViewController(rootNode: .pane(pane))
    let view = WorkspaceLayoutNativeTabButtonView(frame: .zero)
    let renderTab = scenario.tab
    view.update(
        tab: renderTab,
        paneId: pane.id,
        isSelected: scenario.isSelected,
        showsZoomIndicator: scenario.showsZoomIndicator,
        appearance: scenario.appearance,
        contextMenuState: TabContextMenuState(
            isPinned: scenario.tab.isPinned,
            isUnread: scenario.tab.showsNotificationBadge,
            isBrowser: scenario.tab.kind == .browser,
            isTerminal: scenario.tab.kind == .terminal,
            hasCustomTitle: scenario.tab.hasCustomTitle,
            canCloseToLeft: false,
            canCloseToRight: false,
            canCloseOthers: false,
            canMoveToLeftPane: false,
            canMoveToRightPane: false,
            isZoomed: scenario.showsZoomIndicator,
            hasSplits: scenario.showsZoomIndicator,
            shortcuts: [:]
        ),
        splitViewController: splitController,
        onSelect: {},
        onClose: {},
        onZoomToggle: {},
        onContextAction: { _ in }
    )
    view.configureDebugInteractionState(
        isHovered: scenario.isHovered,
        isCloseHovered: scenario.isCloseHovered,
        isClosePressed: scenario.isClosePressed,
        isZoomHovered: scenario.isZoomHovered,
        isZoomPressed: scenario.isZoomPressed
    )
    let width = view.preferredWidth(
        minWidth: scenario.appearance.tabMinWidth,
        maxWidth: scenario.appearance.tabMaxWidth
    )
    view.frame = CGRect(x: 0, y: 0, width: width, height: TabBarMetrics.tabHeight)
    view.layoutSubtreeIfNeeded()
    return workspaceSplitSnapshotImage(
        for: view,
        scale: scale,
        backgroundColor: TabBarColors.nsColorPaneBackground(for: scenario.appearance)
    )
}

@MainActor
func workspaceLayoutRenderReferenceTabChromeImage(
    scenario: WorkspaceLayoutTabChromeDebugScenario,
    scale: CGFloat = 2
) -> NSImage? {
    let rootView = WorkspaceLayoutReferenceTabChromeView(
        tab: scenario.tab,
        isSelected: scenario.isSelected,
        isHovered: scenario.isHovered,
        isCloseHovered: scenario.isCloseHovered,
        isClosePressed: scenario.isClosePressed,
        showsZoomIndicator: scenario.showsZoomIndicator,
        isZoomHovered: scenario.isZoomHovered,
        isZoomPressed: scenario.isZoomPressed,
        appearance: scenario.appearance,
        fixedSpinnerPhase: scenario.tab.isLoading ? 0 : nil
    )
    let host = NSHostingView(rootView: rootView)
    let fittingWidth = ceil(host.fittingSize.width)
    host.frame = CGRect(x: 0, y: 0, width: fittingWidth, height: TabBarMetrics.tabHeight)
    host.layoutSubtreeIfNeeded()
    return workspaceSplitSnapshotImage(
        for: host,
        scale: scale,
        backgroundColor: TabBarColors.nsColorPaneBackground(for: scenario.appearance)
    )
}

private func workspaceSplitAccessoryButtonTuning() -> (
    accessoryDX: CGFloat,
    accessoryDY: CGFloat,
    accessoryPointSizeDelta: CGFloat,
    closeGlyphDX: CGFloat,
    closeGlyphDY: CGFloat,
    closeCircleDX: CGFloat,
    closeCircleDY: CGFloat,
    closeCircleSizeDelta: CGFloat
) {
#if DEBUG
    let tuning = WorkspaceLayoutTabChromeDebugTuning.current
    return (
        accessoryDX: tuning.accessoryDX,
        accessoryDY: tuning.accessoryDY,
        accessoryPointSizeDelta: tuning.accessoryPointSizeDelta,
        closeGlyphDX: tuning.closeGlyphDX,
        closeGlyphDY: tuning.closeGlyphDY,
        closeCircleDX: tuning.closeCircleDX,
        closeCircleDY: tuning.closeCircleDY,
        closeCircleSizeDelta: tuning.closeCircleSizeDelta
    )
#else
    (
        accessoryDX: CGFloat(0),
        accessoryDY: WorkspaceLayoutTabChromeAccessoryMetrics.baseDY,
        accessoryPointSizeDelta: WorkspaceLayoutTabChromeAccessoryMetrics.basePointSizeDelta,
        closeGlyphDX: CGFloat(0),
        closeGlyphDY: CGFloat(0),
        closeCircleDX: CGFloat(0),
        closeCircleDY: WorkspaceLayoutTabChromeAccessoryMetrics.baseCloseCircleDY,
        closeCircleSizeDelta: CGFloat(0)
    )
#endif
}

private func workspaceSplitAccessoryBackgroundColor(
    isHovered: Bool,
    isPressed: Bool,
    appearance: WorkspaceLayoutConfiguration.Appearance
) -> NSColor {
    if isPressed {
        return workspaceSplitPressedTabBackground(for: appearance)
    }
    if isHovered {
        return workspaceSplitHoveredTabBackground(for: appearance)
    }
    return .clear
}

private func workspaceSplitDrawAccessoryButton(
    in rect: CGRect,
    symbolName: String,
    pointSize: CGFloat,
    isHovered: Bool,
    isPressed: Bool,
    appearance: WorkspaceLayoutConfiguration.Appearance
) {
    let tuning = workspaceSplitAccessoryButtonTuning()
    let backgroundColor = workspaceSplitAccessoryBackgroundColor(
        isHovered: isHovered,
        isPressed: isPressed,
        appearance: appearance
    )
    if backgroundColor.alphaComponent > 0 {
        let backgroundRect = CGRect(
            x: rect.minX + tuning.closeCircleDX - (tuning.closeCircleSizeDelta / 2),
            y: rect.minY + tuning.closeCircleDY - (tuning.closeCircleSizeDelta / 2),
            width: max(1, rect.width + tuning.closeCircleSizeDelta),
            height: max(1, rect.height + tuning.closeCircleSizeDelta)
        )
        backgroundColor.setFill()
        NSBezierPath(ovalIn: backgroundRect).fill()
    }
    let tint = (isHovered || isPressed)
        ? TabBarColors.nsColorActiveText(for: appearance)
        : TabBarColors.nsColorInactiveText(for: appearance)
    let glyphDX = tuning.accessoryDX + (symbolName == "xmark" ? tuning.closeGlyphDX : 0)
    let glyphDY = tuning.accessoryDY + (symbolName == "xmark" ? tuning.closeGlyphDY : 0)
    workspaceSplitDrawSymbol(
        named: symbolName,
        pointSize: pointSize + tuning.accessoryPointSizeDelta,
        weight: .semibold,
        color: tint,
        in: rect.offsetBy(dx: glyphDX, dy: glyphDY)
    )
}

final class WorkspaceLayoutAccessoryDebugPreviewView: NSView {
    private var symbolName: String
    private var pointSize: CGFloat
    private var isHovered: Bool
    private var isPressed: Bool
    private var splitAppearance: WorkspaceLayoutConfiguration.Appearance

    init(
        frame frameRect: NSRect,
        symbolName: String,
        pointSize: CGFloat,
        isHovered: Bool,
        isPressed: Bool,
        appearance: WorkspaceLayoutConfiguration.Appearance
    ) {
        self.symbolName = symbolName
        self.pointSize = pointSize
        self.isHovered = isHovered
        self.isPressed = isPressed
        self.splitAppearance = appearance
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        symbolName: String,
        pointSize: CGFloat,
        isHovered: Bool,
        isPressed: Bool,
        appearance: WorkspaceLayoutConfiguration.Appearance
    ) {
        self.symbolName = symbolName
        self.pointSize = pointSize
        self.isHovered = isHovered
        self.isPressed = isPressed
        self.splitAppearance = appearance
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let buttonRect = CGRect(
            x: floor((bounds.width - TabBarMetrics.closeButtonSize) / 2),
            y: floor((bounds.height - TabBarMetrics.closeButtonSize) / 2),
            width: TabBarMetrics.closeButtonSize,
            height: TabBarMetrics.closeButtonSize
        )
        workspaceSplitDrawAccessoryButton(
            in: buttonRect,
            symbolName: symbolName,
            pointSize: pointSize,
            isHovered: isHovered,
            isPressed: isPressed,
            appearance: splitAppearance
        )
    }
}

final class WorkspaceLayoutNativeTabButtonDebugPreviewHost: NSView {
    private let splitViewController = SplitViewController()
    private let button = WorkspaceLayoutNativeTabButtonView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        title: String,
        icon: String?,
        kind: PanelType,
        appearance: WorkspaceLayoutConfiguration.Appearance,
        isSelected: Bool,
        isHovered: Bool,
        isCloseHovered: Bool,
        isClosePressed: Bool
    ) {
        let tab = WorkspaceLayout.Tab(
            title: title,
            icon: icon,
            kind: kind
        )
        let contextMenuState = TabContextMenuState(
            isPinned: false,
            isUnread: false,
            isBrowser: kind == .browser,
            isTerminal: kind == .terminal,
            hasCustomTitle: false,
            canCloseToLeft: false,
            canCloseToRight: false,
            canCloseOthers: false,
            canMoveToLeftPane: false,
            canMoveToRightPane: false,
            isZoomed: false,
            hasSplits: false,
            shortcuts: [:]
        )
        button.update(
            tab: tab,
            paneId: PaneID(),
            isSelected: isSelected,
            showsZoomIndicator: false,
            appearance: appearance,
            contextMenuState: contextMenuState,
            splitViewController: splitViewController,
            onSelect: {},
            onClose: {},
            onZoomToggle: {},
            onContextAction: { _ in }
        )
        button.configureDebugInteractionState(
            isHovered: isHovered,
            isCloseHovered: isCloseHovered,
            isClosePressed: isClosePressed,
            isZoomHovered: false,
            isZoomPressed: false
        )
        let width = button.preferredWidth(
            minWidth: appearance.tabMinWidth,
            maxWidth: appearance.tabMaxWidth
        )
        frame.size = CGSize(width: width, height: TabBarMetrics.tabHeight)
        button.frame = CGRect(x: 0, y: 0, width: width, height: TabBarMetrics.tabHeight)
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: max(1, button.frame.width), height: TabBarMetrics.tabHeight)
    }
}

@MainActor
func workspaceLayoutTabChromeDebugDiff(
    appKitImage: NSImage,
    referenceImage: NSImage
) -> (image: NSImage, metrics: WorkspaceLayoutTabChromeDebugDiffMetrics)? {
    guard let appKitBuffer = workspaceLayoutRGBAImageBuffer(from: appKitImage),
          let referenceBuffer = workspaceLayoutRGBAImageBuffer(from: referenceImage) else {
        return nil
    }

    let width = max(appKitBuffer.width, referenceBuffer.width)
    let height = max(appKitBuffer.height, referenceBuffer.height)
    guard let resizedAppKit = workspaceLayoutResizeImageBuffer(appKitBuffer, width: width, height: height),
          let resizedReference = workspaceLayoutResizeImageBuffer(referenceBuffer, width: width, height: height) else {
        return nil
    }

    var diffBytes = [UInt8](repeating: 0, count: width * height * 4)
    var differingPixelCount = 0
    var maxChannelDelta = 0
    var totalChannelDelta = 0

    for pixelIndex in 0..<(width * height) {
        let base = pixelIndex * 4
        let rDelta = abs(Int(resizedAppKit.bytes[base]) - Int(resizedReference.bytes[base]))
        let gDelta = abs(Int(resizedAppKit.bytes[base + 1]) - Int(resizedReference.bytes[base + 1]))
        let bDelta = abs(Int(resizedAppKit.bytes[base + 2]) - Int(resizedReference.bytes[base + 2]))
        let aDelta = abs(Int(resizedAppKit.bytes[base + 3]) - Int(resizedReference.bytes[base + 3]))
        let pixelMax = max(rDelta, gDelta, bDelta, aDelta)
        if pixelMax > 0 {
            differingPixelCount += 1
        }
        maxChannelDelta = max(maxChannelDelta, pixelMax)
        totalChannelDelta += rDelta + gDelta + bDelta + aDelta

        diffBytes[base] = UInt8(clamping: rDelta)
        diffBytes[base + 1] = UInt8(clamping: gDelta)
        diffBytes[base + 2] = UInt8(clamping: bDelta)
        diffBytes[base + 3] = pixelMax == 0 ? 0 : 255
    }

    guard let diffImage = workspaceLayoutImageFromRGBABytes(
        diffBytes,
        width: width,
        height: height
    ) else {
        return nil
    }

    let totalPixels = width * height
    let meanAbsoluteChannelDelta = totalPixels == 0
        ? 0
        : Double(totalChannelDelta) / Double(totalPixels * 4)
    let metrics = WorkspaceLayoutTabChromeDebugDiffMetrics(
        width: width,
        height: height,
        differingPixelCount: differingPixelCount,
        totalPixelCount: totalPixels,
        maxChannelDelta: maxChannelDelta,
        meanAbsoluteChannelDelta: meanAbsoluteChannelDelta,
        matchingPixels: differingPixelCount == 0
    )
    return (diffImage, metrics)
}

@MainActor
func workspaceLayoutExportTabChromeDebugArtifacts(
    to directory: URL,
    scale: CGFloat = 2
) throws -> WorkspaceLayoutTabChromeDebugExportManifest {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

    var scenarioResults: [WorkspaceLayoutTabChromeDebugExportScenarioResult] = []
    for scenario in workspaceLayoutTabChromeDebugScenarios() {
        guard let appKitImage = workspaceLayoutRenderAppKitTabChromeImage(scenario: scenario, scale: scale) else {
            continue
        }

        let appKitName = "\(scenario.id)-appkit.png"
        try workspaceLayoutWritePNG(image: appKitImage, to: directory.appendingPathComponent(appKitName))
        scenarioResults.append(
            WorkspaceLayoutTabChromeDebugExportScenarioResult(
                id: scenario.id,
                title: scenario.title,
                appKitPNG: appKitName,
                scenario: workspaceLayoutTabChromeDebugScenarioSpec(from: scenario)
            )
        )
    }

    let formatter = ISO8601DateFormatter()
    let manifest = WorkspaceLayoutTabChromeDebugExportManifest(
        generatedAt: formatter.string(from: Date()),
        scenarioResults: scenarioResults
    )
    let manifestURL = directory.appendingPathComponent("manifest.json")
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: manifestURL, options: .atomic)
    return manifest
}

private func workspaceLayoutTabChromeDebugScenarioSpec(
    from scenario: WorkspaceLayoutTabChromeDebugScenario
) -> WorkspaceLayoutTabChromeDebugScenarioSpec {
    WorkspaceLayoutTabChromeDebugScenarioSpec(
        tab: WorkspaceLayoutTabChromeDebugTabSpec(
            id: scenario.tab.id.id,
            title: scenario.tab.title,
            hasCustomTitle: scenario.tab.hasCustomTitle,
            icon: scenario.tab.icon,
            iconImageDataBase64: scenario.tab.iconImageData?.base64EncodedString(),
            kind: scenario.tab.kind,
            isDirty: scenario.tab.isDirty,
            showsNotificationBadge: scenario.tab.showsNotificationBadge,
            isLoading: scenario.tab.isLoading,
            isPinned: scenario.tab.isPinned
        ),
        isSelected: scenario.isSelected,
        isHovered: scenario.isHovered,
        isCloseHovered: scenario.isCloseHovered,
        isClosePressed: scenario.isClosePressed,
        showsZoomIndicator: scenario.showsZoomIndicator,
        isZoomHovered: scenario.isZoomHovered,
        isZoomPressed: scenario.isZoomPressed,
        appearance: WorkspaceLayoutTabChromeDebugAppearanceSpec(
            tabBarHeight: Double(scenario.appearance.tabBarHeight),
            tabMinWidth: Double(scenario.appearance.tabMinWidth),
            tabMaxWidth: Double(scenario.appearance.tabMaxWidth),
            tabTitleFontSize: Double(scenario.appearance.tabTitleFontSize),
            tabSpacing: Double(scenario.appearance.tabSpacing),
            minimumPaneWidth: Double(scenario.appearance.minimumPaneWidth),
            minimumPaneHeight: Double(scenario.appearance.minimumPaneHeight),
            showSplitButtons: scenario.appearance.showSplitButtons,
            splitButtonsOnHover: scenario.appearance.splitButtonsOnHover,
            tabBarLeadingInset: Double(scenario.appearance.tabBarLeadingInset),
            splitButtonTooltips: WorkspaceLayoutTabChromeDebugSplitButtonTooltipsSpec(
                newTerminal: scenario.appearance.splitButtonTooltips.newTerminal,
                newBrowser: scenario.appearance.splitButtonTooltips.newBrowser,
                splitRight: scenario.appearance.splitButtonTooltips.splitRight,
                splitDown: scenario.appearance.splitButtonTooltips.splitDown
            ),
            animationDuration: scenario.appearance.animationDuration,
            enableAnimations: scenario.appearance.enableAnimations,
            chromeColors: WorkspaceLayoutTabChromeDebugChromeColorsSpec(
                backgroundHex: scenario.appearance.chromeColors.backgroundHex,
                borderHex: scenario.appearance.chromeColors.borderHex
            )
        )
    )
}

private struct WorkspaceLayoutRGBAImageBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

private func workspaceLayoutRGBAImageBuffer(from image: NSImage) -> WorkspaceLayoutRGBAImageBuffer? {
    guard let cgImage = workspaceLayoutCGImage(from: image) else { return nil }
    return workspaceLayoutRGBAImageBuffer(from: cgImage)
}

private func workspaceLayoutRGBAImageBuffer(from cgImage: CGImage) -> WorkspaceLayoutRGBAImageBuffer? {
    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return WorkspaceLayoutRGBAImageBuffer(width: width, height: height, bytes: bytes)
}

private func workspaceLayoutResizeImageBuffer(
    _ buffer: WorkspaceLayoutRGBAImageBuffer,
    width: Int,
    height: Int
) -> WorkspaceLayoutRGBAImageBuffer? {
    guard let image = workspaceLayoutImageFromRGBABytes(buffer.bytes, width: buffer.width, height: buffer.height),
          let cgImage = workspaceLayoutCGImage(from: image) else {
        return nil
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }
    context.interpolationQuality = .none
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return WorkspaceLayoutRGBAImageBuffer(width: width, height: height, bytes: bytes)
}

private func workspaceLayoutImageFromRGBABytes(
    _ bytes: [UInt8],
    width: Int,
    height: Int
) -> NSImage? {
    let data = Data(bytes)
    guard let provider = CGDataProvider(data: data as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        return nil
    }
    let image = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    return image
}

private func workspaceLayoutCGImage(from image: NSImage) -> CGImage? {
    var proposed = CGRect(origin: .zero, size: image.size)
    if let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
        return cgImage
    }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    return rep.cgImage
}

private func workspaceLayoutWritePNG(image: NSImage, to url: URL) throws {
    guard let cgImage = workspaceLayoutCGImage(from: image) else {
        throw NSError(domain: "WorkspaceTabChromeDebug", code: 1, userInfo: nil)
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WorkspaceTabChromeDebug", code: 2, userInfo: nil)
    }
    try data.write(to: url, options: .atomic)
}

private func workspaceSplitSnapshotImage(
    for view: NSView,
    scale: CGFloat = 1,
    backgroundColor: NSColor? = nil
) -> NSImage? {
    guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
    let width = max(1, Int(ceil(view.bounds.width * scale)))
    let height = max(1, Int(ceil(view.bounds.height * scale)))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    rep.size = view.bounds.size
    if let backgroundColor,
       let context = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        backgroundColor.setFill()
        NSBezierPath(rect: view.bounds).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    return image
}

private func workspaceSplitDecodeTransfer(from pasteboard: NSPasteboard) -> TabTransferData? {
    let type = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    if let data = pasteboard.data(forType: type),
       let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) {
        return transfer
    }
    if let raw = pasteboard.string(forType: type),
       let data = raw.data(using: .utf8),
       let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) {
        return transfer
    }
    return nil
}

private func workspaceSplitHoveredTabBackground(
    for appearance: WorkspaceLayoutConfiguration.Appearance
) -> NSColor {
    guard let backgroundHex = appearance.chromeColors.backgroundHex,
          let custom = NSColor(hex: backgroundHex) else {
        return NSColor.controlBackgroundColor.withAlphaComponent(0.5)
    }

    let adjusted = workspaceSplitIsLightColor(custom)
        ? workspaceSplitAdjustColor(custom, by: -0.03)
        : workspaceSplitAdjustColor(custom, by: 0.07)
    return adjusted.withAlphaComponent(0.78)
}

private func workspaceSplitPressedTabBackground(
    for appearance: WorkspaceLayoutConfiguration.Appearance
) -> NSColor {
    guard let backgroundHex = appearance.chromeColors.backgroundHex,
          let custom = NSColor(hex: backgroundHex) else {
        return NSColor.controlBackgroundColor.withAlphaComponent(0.72)
    }

    let adjusted = workspaceSplitIsLightColor(custom)
        ? workspaceSplitAdjustColor(custom, by: -0.065)
        : workspaceSplitAdjustColor(custom, by: 0.12)
    return adjusted.withAlphaComponent(0.9)
}

private func workspaceSplitIsLightColor(_ color: NSColor) -> Bool {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
    let luminance = (0.299 * rgb.redComponent) + (0.587 * rgb.greenComponent) + (0.114 * rgb.blueComponent)
    return luminance > 0.6
}

private func workspaceSplitAdjustColor(_ color: NSColor, by delta: CGFloat) -> NSColor {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
    let clamp: (CGFloat) -> CGFloat = { min(max($0, 0), 1) }
    return NSColor(
        red: clamp(rgb.redComponent + delta),
        green: clamp(rgb.greenComponent + delta),
        blue: clamp(rgb.blueComponent + delta),
        alpha: rgb.alphaComponent
    )
}

@MainActor
private func workspaceSplitClearDragState(_ controller: SplitViewController) {
    controller.draggingTabId = nil
    controller.dragSourcePaneId = nil
    controller.activeDragTabId = nil
    controller.activeDragSourcePaneId = nil
}

struct WorkspacePaneDropZoneDecision: Equatable {
    let defaultZone: DropZone
    let finalZone: DropZone
    let targetPaneId: PaneID
    let sourcePaneId: PaneID?
    let remapReason: String?
}

enum WorkspacePaneDropRouting {
    private static let padding: CGFloat = 4

    static func overlayFrame(for zone: DropZone, in size: CGSize) -> CGRect {
        switch zone {
        case .center:
            return CGRect(
                x: padding,
                y: padding,
                width: size.width - (padding * 2),
                height: size.height - (padding * 2)
            )
        case .left:
            return CGRect(
                x: padding,
                y: padding,
                width: (size.width / 2) - padding,
                height: size.height - (padding * 2)
            )
        case .right:
            return CGRect(
                x: size.width / 2,
                y: padding,
                width: (size.width / 2) - padding,
                height: size.height - (padding * 2)
            )
        case .top:
            return CGRect(
                x: padding,
                y: padding,
                width: size.width - (padding * 2),
                height: (size.height / 2) - padding
            )
        case .bottom:
            return CGRect(
                x: padding,
                y: size.height / 2,
                width: size.width - (padding * 2),
                height: (size.height / 2) - padding
            )
        }
    }

    static func zone(for location: CGPoint, in size: CGSize) -> DropZone {
        let edgeRatio: CGFloat = 0.25
        let horizontalEdge = max(80, size.width * edgeRatio)
        let verticalEdge = max(80, size.height * edgeRatio)

        if location.x < horizontalEdge {
            return .left
        }
        if location.x > size.width - horizontalEdge {
            return .right
        }
        if location.y > size.height - verticalEdge {
            return .top
        }
        if location.y < verticalEdge {
            return .bottom
        }
        return .center
    }

    static func decision(
        for location: CGPoint,
        in size: CGSize,
        targetPaneId: PaneID,
        sourcePaneId: PaneID?
    ) -> WorkspacePaneDropZoneDecision {
        let defaultZone = zone(for: location, in: size)
        return WorkspacePaneDropZoneDecision(
            defaultZone: defaultZone,
            finalZone: defaultZone,
            targetPaneId: targetPaneId,
            sourcePaneId: sourcePaneId,
            remapReason: nil
        )
    }
}
