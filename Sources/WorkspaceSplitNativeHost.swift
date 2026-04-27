import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

@MainActor
struct WorkspaceLayoutNativeHost: NSViewRepresentable {
    private let hostBridge: WorkspaceLayoutInteractionHandlers
    private let renderSnapshot: WorkspaceLayoutRenderSnapshot
    private let surfaceRegistry: WorkspaceSurfaceRegistry

    init(
        hostBridge: WorkspaceLayoutInteractionHandlers,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        self.hostBridge = hostBridge
        self.renderSnapshot = renderSnapshot
        self.surfaceRegistry = surfaceRegistry
    }

    func makeNSView(context: Context) -> WorkspaceLayoutRootHostView {
        let view = WorkspaceLayoutRootHostView(
            hostBridge: hostBridge,
            renderSnapshot: renderSnapshot,
            surfaceRegistry: surfaceRegistry
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: WorkspaceLayoutRootHostView, context: Context) {
        nsView.update(
            hostBridge: hostBridge,
            renderSnapshot: renderSnapshot,
            surfaceRegistry: surfaceRegistry
        )
    }

    static func dismantleNSView(_ nsView: WorkspaceLayoutRootHostView, coordinator: ()) {
        nsView.prepareForRemoval()
    }
}

@MainActor
final class WorkspaceLayoutRootHostView: NSView {
    private var hostBridge: WorkspaceLayoutInteractionHandlers
    private var desiredRenderSnapshot: WorkspaceLayoutRenderSnapshot
    private var displayedRenderSnapshot: WorkspaceLayoutRenderSnapshot
    private let surfaceRegistry: WorkspaceSurfaceRegistry
    private var activeLocalTabDrag: WorkspaceLayoutLocalDragSnapshot?

    private let viewportCanvas: WorkspaceLayoutViewportCanvasView
    private var currentRootView: NSView?
    private var paneHosts: [UUID: WorkspaceLayoutPaneHostView] = [:]
    private var splitHosts: [UUID: WorkspaceLayoutNativeSplitView] = [:]
    private var dropOverlayCoordinator = WorkspacePaneDropOverlayCoordinator()
    private var renderedPaneIds: Set<UUID> = []
    private var renderedSplitIds: Set<UUID> = []
    private var lastContainerFrame: CGRect = .zero

    init(
        hostBridge: WorkspaceLayoutInteractionHandlers,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        self.hostBridge = hostBridge
        desiredRenderSnapshot = renderSnapshot
        displayedRenderSnapshot = renderSnapshot
        self.surfaceRegistry = surfaceRegistry
        activeLocalTabDrag = renderSnapshot.presentation.localTabDrag
        viewportCanvas = WorkspaceLayoutViewportCanvasView(
            surfaceRegistry: surfaceRegistry,
            debugName: "live"
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(viewportCanvas)
        updateBackground()
        rebuildTree()
        applyViewportScene()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        hostBridge: WorkspaceLayoutInteractionHandlers,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        self.hostBridge = hostBridge
        desiredRenderSnapshot = renderSnapshot
        syncLocalTabDragIfNeeded(from: renderSnapshot)
        isHidden = !renderSnapshot.presentation.isInteractive
        refreshPresentation()
        syncContainerFrameIfNeeded(isDragging: false)
    }

    override func layout() {
        super.layout()
        viewportCanvas.frame = bounds
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
        refreshPresentation()
        syncContainerFrameIfNeeded(isDragging: false)
    }

    func prepareForRemoval() {
        clearLocalTabDrag(propagateToWorkspace: false)
        viewportCanvas.clear(surfaceRegistry: surfaceRegistry)

        for (_, host) in paneHosts {
            host.prepareForRemoval()
            if host.superview != nil {
                host.removeFromSuperview()
            }
        }
        paneHosts.removeAll()

        for (_, host) in splitHosts {
            host.removeAllChildren()
            if host.superview != nil {
                host.removeFromSuperview()
            }
        }
        splitHosts.removeAll()

        dropOverlayCoordinator.clearAll()
        renderedPaneIds.removeAll()
        renderedSplitIds.removeAll()

        currentRootView?.removeFromSuperview()
        currentRootView = nil
    }

    private func updateBackground() {
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: displayedRenderSnapshot.presentation.appearance
        ).cgColor
    }

    fileprivate func notifyGeometryChanged(isDragging: Bool) {
        syncContainerFrameIfNeeded(isDragging: isDragging)
        hostBridge.notifyGeometryChange(isDragging: isDragging)
    }

    fileprivate func updatePaneDropZone(_ zone: DropZone, for paneId: PaneID) {
        guard dropOverlayCoordinator.setZone(zone, for: paneId) else { return }
        syncPaneDropState(for: paneId)
    }

    fileprivate func clearPaneDropZone(for paneId: PaneID) {
        guard dropOverlayCoordinator.clearZone(for: paneId) else { return }
        syncPaneDropState(for: paneId)
    }

    fileprivate func clearPaneDropZoneImmediately(for paneId: PaneID) {
        guard dropOverlayCoordinator.clearZoneImmediately(for: paneId) else { return }
        syncPaneDropState(for: paneId)
    }

    fileprivate func completePaneDropOverlayHide(for paneId: PaneID, generation: UInt64) {
        guard dropOverlayCoordinator.completeHide(for: paneId, generation: generation) else { return }
        syncPaneDropState(for: paneId)
    }

    private func syncContainerFrameIfNeeded(isDragging: Bool) {
        let frame = convert(bounds, to: nil)
        guard frame != lastContainerFrame else { return }
        lastContainerFrame = frame
        hostBridge.setContainerFrame(frame)
        if !isDragging {
            hostBridge.notifyGeometryChange(isDragging: false)
        }
    }

    private func rebuildTree() {
        let nextPaneIds = displayedRenderSnapshot.root.paneIds
        let nextSplitIds = displayedRenderSnapshot.root.splitIds

        let nextRootView = hostView(for: displayedRenderSnapshot.root)

        if currentRootView !== nextRootView {
            if nextRootView.superview !== self {
                addSubview(nextRootView)
            }
            if currentRootView?.superview === self {
                currentRootView?.removeFromSuperview()
            }
            currentRootView = nextRootView
        }

        currentRootView?.frame = bounds
        renderedPaneIds = nextPaneIds
        renderedSplitIds = nextSplitIds
        cleanupUnusedHosts()
    }

    private func applyViewportScene() {
        viewportCanvas.update(
            viewports: displayedRenderSnapshot.viewports,
            presentation: displayedRenderSnapshot.presentation,
            paneDropZones: dropOverlayCoordinator.viewportDropZones()
        )
    }

    private func cleanupUnusedHosts() {
        let livePaneIds = displayedRenderSnapshot.root.paneIds
        let liveSplitIds = displayedRenderSnapshot.root.splitIds

        for (id, host) in paneHosts where !livePaneIds.contains(id) {
            host.prepareForRemoval()
            dropOverlayCoordinator.removePane(PaneID(id: id))
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
        let subviewHostBridge = interactionHandlersForSubviews()
        if let existing = paneHosts[snapshot.paneId.id] {
            existing.update(
                snapshot: snapshot,
                hostBridge: subviewHostBridge,
                presentation: displayedRenderSnapshot.presentation,
                localTabDrag: activeLocalTabDrag,
                overlayPresentation: dropOverlayCoordinator.overlayPresentation(for: snapshot.paneId),
                contentDropZone: dropOverlayCoordinator.activeDropZone(for: snapshot.paneId),
                surfaceRegistry: surfaceRegistry
            )
            return existing
        }

        let host = WorkspaceLayoutPaneHostView(
            rootHost: self,
            snapshot: snapshot,
            hostBridge: subviewHostBridge,
            presentation: displayedRenderSnapshot.presentation,
            localTabDrag: activeLocalTabDrag,
            overlayPresentation: dropOverlayCoordinator.overlayPresentation(for: snapshot.paneId),
            contentDropZone: dropOverlayCoordinator.activeDropZone(for: snapshot.paneId),
            surfaceRegistry: surfaceRegistry
        )
        paneHosts[snapshot.paneId.id] = host
        return host
    }

    private func splitHost(for snapshot: WorkspaceLayoutSplitRenderSnapshot) -> WorkspaceLayoutNativeSplitView {
        if let existing = splitHosts[snapshot.splitId] {
            existing.update(
                snapshot: snapshot,
                hostBridge: hostBridge,
                rootHost: self,
                firstChild: hostView(for: snapshot.first),
                secondChild: hostView(for: snapshot.second),
                appearance: displayedRenderSnapshot.presentation.appearance
            )
            return existing
        }

        let host = WorkspaceLayoutNativeSplitView(
            snapshot: snapshot,
            hostBridge: hostBridge,
            rootHost: self,
            firstChild: hostView(for: snapshot.first),
            secondChild: hostView(for: snapshot.second),
            appearance: displayedRenderSnapshot.presentation.appearance
        )
        splitHosts[snapshot.splitId] = host
        return host
    }

    private func refreshPresentation() {
        displayedRenderSnapshot = desiredRenderSnapshot
        updateBackground()
        rebuildTree()
        applyViewportScene()
    }

    private func syncLocalTabDragIfNeeded(from renderSnapshot: WorkspaceLayoutRenderSnapshot) {
        guard let snapshotLocalTabDrag = renderSnapshot.presentation.localTabDrag else { return }
        guard snapshotLocalTabDrag != activeLocalTabDrag else { return }
        activeLocalTabDrag = snapshotLocalTabDrag
        propagateLocalTabDrag()
    }

    private func interactionHandlersForSubviews() -> WorkspaceLayoutInteractionHandlers {
        WorkspaceLayoutInteractionHandlers(
            notifyGeometryChangeHandler: { [weak self] isDragging in
                self?.hostBridge.notifyGeometryChange(isDragging: isDragging)
            },
            setContainerFrameHandler: { [weak self] frame in
                self?.hostBridge.setContainerFrame(frame)
            },
            setDividerPositionHandler: { [weak self] position, splitId in
                self?.hostBridge.setDividerPosition(position, forSplit: splitId) ?? false
            },
            consumeSplitEntryAnimationHandler: { [weak self] splitId in
                self?.hostBridge.consumeSplitEntryAnimation(splitId)
            },
            beginTabDragHandler: { [weak self] tabId, sourcePaneId in
                self?.beginLocalTabDrag(tabId: tabId, sourcePaneId: sourcePaneId)
            },
            clearDragStateHandler: { [weak self] in
                self?.clearLocalTabDrag()
            },
            focusPaneHandler: { [weak self] paneId in
                self?.hostBridge.focusPane(paneId) ?? false
            },
            selectTabHandler: { [weak self] tabId in
                self?.hostBridge.selectTab(tabId)
            },
            requestCloseTabHandler: { [weak self] tabId, paneId in
                self?.hostBridge.requestCloseTab(tabId, inPane: paneId) ?? false
            },
            togglePaneZoomHandler: { [weak self] paneId in
                self?.hostBridge.togglePaneZoom(inPane: paneId) ?? false
            },
            requestTabContextActionHandler: { [weak self] action, tabId, paneId in
                self?.hostBridge.requestTabContextAction(action, for: tabId, inPane: paneId)
            },
            requestNewTabHandler: { [weak self] kind, paneId in
                self?.hostBridge.requestNewTab(kind: kind, inPane: paneId)
            },
            splitPaneHandler: { [weak self] paneId, orientation in
                self?.hostBridge.splitPane(paneId, orientation: orientation)
            },
            splitPaneMovingTabHandler: { [weak self] paneId, orientation, tabId, insertFirst, focusNewPane in
                self?.hostBridge.splitPane(
                    paneId,
                    orientation: orientation,
                    movingTab: tabId,
                    insertFirst: insertFirst,
                    focusNewPane: focusNewPane
                )
            },
            moveTabHandler: { [weak self] tabId, paneId, index in
                self?.hostBridge.moveTab(tabId, toPane: paneId, atIndex: index) ?? false
            },
            handleExternalTabDropHandler: { [weak self] request in
                self?.hostBridge.handleExternalTabDrop(request) ?? false
            },
            handleFileDropHandler: { [weak self] urls, paneId in
                self?.hostBridge.handleFileDrop(urls, in: paneId) ?? false
            }
        )
    }

    private func beginLocalTabDrag(tabId: TabID, sourcePaneId: PaneID) {
        let drag = WorkspaceLayoutLocalDragSnapshot(tabId: tabId, sourcePaneId: sourcePaneId)
        guard activeLocalTabDrag != drag else { return }
        activeLocalTabDrag = drag
        propagateLocalTabDrag()
        hostBridge.beginTabDrag(tabId: tabId, sourcePaneId: sourcePaneId)
    }

    private func clearLocalTabDrag(propagateToWorkspace: Bool = true) {
        let hadActiveLocalTabDrag = activeLocalTabDrag != nil
        activeLocalTabDrag = nil
        if hadActiveLocalTabDrag {
            propagateLocalTabDrag()
            clearAllPaneDropOverlays()
        }
        if propagateToWorkspace {
            hostBridge.clearDragState()
        }
    }

    private func propagateLocalTabDrag() {
        for host in paneHosts.values {
            host.updateLocalTabDrag(activeLocalTabDrag)
        }
    }

    private func clearAllPaneDropOverlays() {
        let paneIds = Array(paneHosts.keys).map(PaneID.init(id:))
        var didChange = false
        for paneId in paneIds {
            didChange = dropOverlayCoordinator.clearZone(for: paneId) || didChange
            paneHosts[paneId.id]?.updateDropPresentation(
                overlayPresentation: dropOverlayCoordinator.overlayPresentation(for: paneId),
                contentDropZone: dropOverlayCoordinator.activeDropZone(for: paneId),
                surfaceRegistry: surfaceRegistry
            )
        }
        if didChange {
            viewportCanvas.update(
                viewports: displayedRenderSnapshot.viewports,
                presentation: displayedRenderSnapshot.presentation,
                paneDropZones: dropOverlayCoordinator.viewportDropZones()
            )
        }
    }

    private func syncPaneDropState(for paneId: PaneID) {
        paneHosts[paneId.id]?.updateDropPresentation(
            overlayPresentation: dropOverlayCoordinator.overlayPresentation(for: paneId),
            contentDropZone: dropOverlayCoordinator.activeDropZone(for: paneId),
            surfaceRegistry: surfaceRegistry
        )
        viewportCanvas.update(
            viewports: displayedRenderSnapshot.viewports,
            presentation: displayedRenderSnapshot.presentation,
            paneDropZones: dropOverlayCoordinator.viewportDropZones()
        )
    }

#if DEBUG
    var debugViewportMountIdentities: Set<WorkspacePaneMountIdentity> {
        viewportCanvas.debugMountedIdentities
    }

    func debugPaneMountedDirectContentIdentity(_ paneId: PaneID) -> WorkspacePaneMountIdentity? {
        paneHosts[paneId.id]?.debugMountedDirectContentIdentity
    }

    func debugPaneDirectContentBounds(_ paneId: PaneID) -> CGRect {
        paneHosts[paneId.id]?.debugDirectContentBounds ?? .zero
    }

    func debugPaneUsesDirectTerminalHost(_ paneId: PaneID) -> Bool {
        paneHosts[paneId.id]?.debugUsesDirectTerminalHost ?? false
    }

    func debugPaneLocalTabDrag(_ paneId: PaneID) -> WorkspaceLayoutLocalDragSnapshot? {
        paneHosts[paneId.id]?.debugLocalTabDrag
    }

    func debugBeginLocalTabDrag(tabId: TabID, sourcePaneId: PaneID) {
        beginLocalTabDrag(tabId: tabId, sourcePaneId: sourcePaneId)
    }

    func debugClearLocalTabDrag() {
        clearLocalTabDrag()
    }
#endif
}

func workspaceLayoutRemoveSubviewIfOwned(_ child: NSView?, from container: NSView) {
    guard let child,
          child.superview === container else { return }
    child.removeFromSuperview()
}

@MainActor
private final class WorkspaceLayoutNativeSplitView: NSSplitView, NSSplitViewDelegate {
    private let hostBridge: WorkspaceLayoutInteractionHandlers
    private weak var rootHost: WorkspaceLayoutRootHostView?
    private var splitId: UUID
    private var splitOrientation: SplitOrientation
    private var splitDividerPosition: CGFloat
    private var splitAnimationOrigin: SplitAnimationOrigin?
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
        snapshot: WorkspaceLayoutSplitRenderSnapshot,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        rootHost: WorkspaceLayoutRootHostView,
        firstChild: NSView,
        secondChild: NSView,
        appearance: WorkspaceLayoutConfiguration.Appearance
    ) {
        self.hostBridge = hostBridge
        self.rootHost = rootHost
        self.splitId = snapshot.splitId
        self.splitOrientation = snapshot.orientation
        self.splitDividerPosition = snapshot.dividerPosition
        self.splitAnimationOrigin = snapshot.animationOrigin
        self.splitAppearance = appearance
        self.lastAppliedPosition = snapshot.dividerPosition
        super.init(frame: .zero)
        delegate = self
        dividerStyle = .thin
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isVertical = snapshot.orientation == .horizontal
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
        snapshot: WorkspaceLayoutSplitRenderSnapshot,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        rootHost: WorkspaceLayoutRootHostView,
        firstChild: NSView,
        secondChild: NSView,
        appearance: WorkspaceLayoutConfiguration.Appearance
    ) {
        if self.splitId != snapshot.splitId {
            didApplyInitialDividerPosition = false
            initialDividerApplyAttempts = 0
            isAnimatingEntry = false
        }

        self.rootHost = rootHost
        self.splitId = snapshot.splitId
        self.splitOrientation = snapshot.orientation
        self.splitDividerPosition = snapshot.dividerPosition
        self.splitAnimationOrigin = snapshot.animationOrigin
        self.splitAppearance = appearance
        isHidden = rootHost.isHidden
        isVertical = snapshot.orientation == .horizontal
        updateDividerColor()
        install(child: firstChild, in: firstContainer, current: &self.firstChild)
        install(child: secondChild, in: secondContainer, current: &self.secondChild)
        syncDividerPosition()
    }

    func removeAllChildren() {
        workspaceLayoutRemoveSubviewIfOwned(firstChild, from: firstContainer)
        workspaceLayoutRemoveSubviewIfOwned(secondChild, from: secondContainer)
        firstChild = nil
        secondChild = nil
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
            workspaceLayoutRemoveSubviewIfOwned(current, from: container)
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
                consumePendingAnimationOriginIfNeeded()
                return
            }
            Task { @MainActor [weak self] in
                self?.applyInitialDividerPositionIfNeeded()
            }
            return
        }

        didApplyInitialDividerPosition = true
        let targetPosition = round(available * splitDividerPosition)

        guard splitAppearance.enableAnimations,
              let animationOrigin = splitAnimationOrigin else {
            consumePendingAnimationOriginIfNeeded()
            setDividerPosition(targetPosition, layout: false)
            return
        }

        let startPosition: CGFloat = animationOrigin == .fromFirst ? 0 : available
        consumePendingAnimationOriginIfNeeded()
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
                self.lastAppliedPosition = self.splitDividerPosition
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
        lastAppliedPosition = availableSplitSize > 0 ? position / availableSplitSize : splitDividerPosition
    }

    private func syncDividerPosition() {
        guard !isAnimatingEntry else { return }
        let available = availableSplitSize
        guard available > 0 else { return }
        let desired = min(max(splitDividerPosition, 0.1), 0.9)
        guard abs(desired - lastAppliedPosition) > 0.0005 else { return }
        setDividerPosition(round(available * desired), layout: false)
    }

    private func normalizedDividerPosition() -> CGFloat {
        guard arrangedSubviews.count >= 2 else { return splitDividerPosition }
        let firstFrame = arrangedSubviews[0].frame
        let available = availableSplitSize
        guard available > 0 else { return splitDividerPosition }
        let occupied = isVertical ? firstFrame.width : firstFrame.height
        return min(max(occupied / available, 0.1), 0.9)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isSyncingProgrammatically else { return }
        let next = normalizedDividerPosition()
        splitDividerPosition = next
        hostBridge.setDividerPosition(next, forSplit: splitId)
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

    private func consumePendingAnimationOriginIfNeeded() {
        guard splitAnimationOrigin != nil else { return }
        splitAnimationOrigin = nil
        hostBridge.consumeSplitEntryAnimation(splitId)
    }
}

@MainActor
private final class WorkspaceLayoutPaneHostView: NSView {
    private weak var rootHost: WorkspaceLayoutRootHostView?
    private var snapshot: WorkspaceLayoutPaneRenderSnapshot
    private let hostBridge: WorkspaceLayoutInteractionHandlers
    private var presentation: WorkspaceLayoutPresentationSnapshot
    private var localTabDrag: WorkspaceLayoutLocalDragSnapshot?
    private let surfaceRegistry: WorkspaceSurfaceRegistry

    private let directContentSlotView = WorkspaceLayoutPaneContentSlotView(frame: .zero)
    private let tabBarView = WorkspaceLayoutNativeTabBarView(frame: .zero)
    private let dropOverlayView = WorkspaceLayoutPaneDropOverlayView(frame: .zero)
    private var overlayPresentation: WorkspacePaneDropOverlayPresentation = .hidden
    private var contentDropZone: DropZone? = nil
    private var mountedDirectContent: WorkspaceLayoutMountedTabEntry?

    init(
        rootHost: WorkspaceLayoutRootHostView,
        snapshot: WorkspaceLayoutPaneRenderSnapshot,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        presentation: WorkspaceLayoutPresentationSnapshot,
        localTabDrag: WorkspaceLayoutLocalDragSnapshot?,
        overlayPresentation: WorkspacePaneDropOverlayPresentation,
        contentDropZone: DropZone?,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        self.rootHost = rootHost
        self.snapshot = snapshot
        self.hostBridge = hostBridge
        self.presentation = presentation
        self.localTabDrag = localTabDrag
        self.overlayPresentation = overlayPresentation
        self.contentDropZone = contentDropZone
        self.surfaceRegistry = surfaceRegistry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        directContentSlotView.isHidden = true
        addSubview(directContentSlotView)
        addSubview(tabBarView)
        addSubview(dropOverlayView)
        dropOverlayView.hitTestPassthroughEnabled = true
        update(
            snapshot: snapshot,
            hostBridge: hostBridge,
            presentation: presentation,
            localTabDrag: localTabDrag,
            overlayPresentation: overlayPresentation,
            contentDropZone: contentDropZone,
            surfaceRegistry: surfaceRegistry
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        snapshot: WorkspaceLayoutPaneRenderSnapshot,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        presentation: WorkspaceLayoutPresentationSnapshot,
        localTabDrag: WorkspaceLayoutLocalDragSnapshot?,
        overlayPresentation: WorkspacePaneDropOverlayPresentation,
        contentDropZone: DropZone?,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        self.snapshot = snapshot
        self.presentation = presentation
        self.localTabDrag = localTabDrag
        self.overlayPresentation = overlayPresentation
        self.contentDropZone = contentDropZone

        tabBarView.update(
            snapshot: snapshot.chrome,
            hostBridge: hostBridge,
            presentation: presentation,
            localTabDrag: localTabDrag
        )
        tabBarView.onTabMutation = { [weak self] in
            self?.rootHost?.notifyGeometryChanged(isDragging: false)
        }

        dropOverlayView.update(
            paneId: snapshot.paneId,
            hostBridge: hostBridge,
            presentation: presentation,
            localTabDrag: localTabDrag,
            overlayPresentation: overlayPresentation,
            onZoneUpdated: { [weak self] zone in
                self?.rootHost?.updatePaneDropZone(zone, for: snapshot.paneId)
            },
            onZoneCleared: { [weak self] in
                self?.rootHost?.clearPaneDropZone(for: snapshot.paneId)
            },
            onDropSucceeded: { [weak self] in
                self?.rootHost?.clearPaneDropZoneImmediately(for: snapshot.paneId)
            },
            onHideAnimationCompleted: { [weak self] generation in
                self?.rootHost?.completePaneDropOverlayHide(for: snapshot.paneId, generation: generation)
            },
            onDropPerformed: { [weak self] in
                self?.rootHost?.notifyGeometryChanged(isDragging: false)
            }
        )
        refreshDirectContentMount(surfaceRegistry: surfaceRegistry, reconcileLifecycle: true)
        needsLayout = true
    }

    func updateLocalTabDrag(_ localTabDrag: WorkspaceLayoutLocalDragSnapshot?) {
        guard self.localTabDrag != localTabDrag else { return }
        self.localTabDrag = localTabDrag
        tabBarView.updateLocalTabDrag(localTabDrag)
        dropOverlayView.updateLocalTabDrag(localTabDrag)
    }

    func prepareForRemoval() {
        clearDirectContent(surfaceRegistry: surfaceRegistry)
    }

    override func layout() {
        super.layout()
        let barHeight = presentation.appearance.tabBarHeight
        let topInset = min(barHeight, max(0, bounds.height - 1))
        let contentHeight = max(0, bounds.height - topInset)
        directContentSlotView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
        tabBarView.frame = CGRect(x: 0, y: contentHeight, width: bounds.width, height: topInset)
        dropOverlayView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
        reconcileDirectContentLifecycle(reason: "layout")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reconcileDirectContentLifecycle(reason: "windowMove")
    }

    func updateDropPresentation(
        overlayPresentation: WorkspacePaneDropOverlayPresentation,
        contentDropZone: DropZone?,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        let didChangeOverlay = self.overlayPresentation != overlayPresentation
        let didChangeContentDropZone = self.contentDropZone != contentDropZone
        self.overlayPresentation = overlayPresentation
        self.contentDropZone = contentDropZone
        if didChangeOverlay {
            dropOverlayView.updateOverlayPresentation(overlayPresentation)
        }
        if didChangeContentDropZone && !snapshot.content.usesDirectPaneHost {
            refreshDirectContentMount(surfaceRegistry: surfaceRegistry, reconcileLifecycle: false)
        }
    }

    private func refreshDirectContentMount(
        surfaceRegistry: WorkspaceSurfaceRegistry,
        reconcileLifecycle: Bool
    ) {
        guard snapshot.content.usesDirectPaneHost else {
            clearDirectContent(surfaceRegistry: surfaceRegistry)
            return
        }

        let nextMountedContent = WorkspaceLayoutMountedTabEntry(
            contentId: snapshot.contentId,
            content: snapshot.content,
            mountIdentity: snapshot.content.mountIdentity(contentId: snapshot.contentId)
        )

        if let mountedDirectContent,
           (mountedDirectContent.contentId != nextMountedContent.contentId
               || mountedDirectContent.mountIdentity != nextMountedContent.mountIdentity) {
            surfaceRegistry.unmountContent(
                mountedDirectContent.content,
                contentId: mountedDirectContent.contentId,
                from: directContentSlotView
            )
            self.mountedDirectContent = nil
        }

        let effectiveContentDropZone = snapshot.content.usesDirectPaneHost ? nil : self.contentDropZone
        surfaceRegistry.mountContent(
            snapshot.content,
            contentId: snapshot.contentId,
            in: directContentSlotView,
            activeDropZone: effectiveContentDropZone
        )
        mountedDirectContent = nextMountedContent
        directContentSlotView.isHidden = false
        if reconcileLifecycle {
            reconcileDirectContentLifecycle(reason: "update")
        }
    }

    private func reconcileDirectContentLifecycle(reason: String) {
        guard let mountedDirectContent else { return }
        surfaceRegistry.reconcileViewportLifecycle(
            mountedDirectContent.content,
            contentId: mountedDirectContent.contentId,
            in: directContentSlotView,
            reason: "pane.\(reason)"
        )
    }

    private func clearDirectContent(surfaceRegistry: WorkspaceSurfaceRegistry) {
        if let mountedDirectContent {
            surfaceRegistry.unmountContent(
                mountedDirectContent.content,
                contentId: mountedDirectContent.contentId,
                from: directContentSlotView
            )
        }
        mountedDirectContent = nil
        directContentSlotView.clearContentView()
        directContentSlotView.isHidden = true
    }

#if DEBUG
    var debugMountedDirectContentIdentity: WorkspacePaneMountIdentity? {
        mountedDirectContent?.mountIdentity
    }

    var debugDirectContentBounds: CGRect {
        directContentSlotView.bounds
    }

    var debugUsesDirectTerminalHost: Bool {
        if case .terminal = mountedDirectContent?.content {
            return true
        }
        return false
    }

    var debugLocalTabDrag: WorkspaceLayoutLocalDragSnapshot? {
        localTabDrag
    }
#endif
}

@MainActor
final class WorkspaceLayoutPaneContentSlotView: NSView {
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
            if let previous = installedContentView, previous.superview === self {
                previous.removeFromSuperview()
            }
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

    func clearContentView() {
        if let installedContentView, installedContentView.superview === self {
            installedContentView.removeFromSuperview()
        }
        installedContentView = nil
    }

    override func layout() {
        super.layout()
        guard let installedContentView else { return }
        guard installedContentView.superview === self else {
            self.installedContentView = nil
            return
        }
        installedContentView.frame = bounds
    }
}

@MainActor
private final class WorkspaceLayoutViewportCanvasView: NSView {
    private let surfaceRegistry: WorkspaceSurfaceRegistry
    private let debugName: String
    private var viewportHosts: [WorkspacePaneMountIdentity: WorkspaceLayoutSurfaceViewportHostView] = [:]

    init(surfaceRegistry: WorkspaceSurfaceRegistry, debugName: String) {
        self.surfaceRegistry = surfaceRegistry
        self.debugName = debugName
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        viewports: [WorkspaceLayoutViewportSnapshot],
        presentation _: WorkspaceLayoutPresentationSnapshot,
        paneDropZones: [UUID: DropZone?]
    ) {
        let liveIdentities = Set(viewports.map(\.mountIdentity))

        for viewport in viewports {
            let host = viewportHost(for: viewport.mountIdentity)
            host.apply(
                snapshot: viewport,
                surfaceRegistry: surfaceRegistry,
                activeDropZone: paneDropZones[viewport.paneId.id] ?? nil
            )
            if host.superview !== self {
                addSubview(host)
            }
        }

        for (identity, host) in viewportHosts where !liveIdentities.contains(identity) {
            host.prepareForRemoval(surfaceRegistry: surfaceRegistry)
            viewportHosts.removeValue(forKey: identity)
        }
    }

    func clear(surfaceRegistry: WorkspaceSurfaceRegistry) {
        for (_, host) in viewportHosts {
            host.prepareForRemoval(surfaceRegistry: surfaceRegistry)
        }
        viewportHosts.removeAll()
    }

    private func viewportHost(
        for identity: WorkspacePaneMountIdentity
    ) -> WorkspaceLayoutSurfaceViewportHostView {
        if let existing = viewportHosts[identity] {
            return existing
        }
        let host = WorkspaceLayoutSurfaceViewportHostView(
            mountIdentity: identity,
            surfaceRegistry: surfaceRegistry,
            debugCanvasName: debugName
        )
        viewportHosts[identity] = host
        return host
    }

#if DEBUG
    var debugMountedIdentities: Set<WorkspacePaneMountIdentity> {
        Set(viewportHosts.keys)
    }
#endif
}

@MainActor
private final class WorkspaceLayoutViewportRevealCoverView: NSView {
    private let spinner = NSProgressIndicator(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.sizeToFit()
        addSubview(spinner)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        spinner.sizeToFit()
        spinner.frame = CGRect(
            x: round((bounds.width - spinner.frame.width) / 2),
            y: round((bounds.height - spinner.frame.height) / 2),
            width: spinner.frame.width,
            height: spinner.frame.height
        )
    }

    func setVisible(_ visible: Bool) {
        isHidden = !visible
        if visible {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }
}

@MainActor
final class WorkspaceLayoutSurfaceViewportHostView: NSView {
    private let mountIdentity: WorkspacePaneMountIdentity
    private let surfaceRegistry: WorkspaceSurfaceRegistry
    private let debugCanvasName: String
    private let slotView = WorkspaceLayoutPaneContentSlotView(frame: .zero)
    private let revealCoverView = WorkspaceLayoutViewportRevealCoverView(frame: .zero)
    private var mountedContent: WorkspaceLayoutMountedTabEntry?
    private var currentSnapshot: WorkspaceLayoutViewportSnapshot?
    private var lastPresentationFacts: WorkspaceSurfacePresentationFacts?

    init(
        mountIdentity: WorkspacePaneMountIdentity,
        surfaceRegistry: WorkspaceSurfaceRegistry,
        debugCanvasName: String
    ) {
        self.mountIdentity = mountIdentity
        self.surfaceRegistry = surfaceRegistry
        self.debugCanvasName = debugCanvasName
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        addSubview(slotView)
        addSubview(revealCoverView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        synchronizeSlotFrameToBounds()
        revealCoverView.frame = bounds
        refreshSurfacePresentation(reason: "layout", force: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshSurfacePresentation(reason: "windowMove", force: true)
    }

    func apply(
        snapshot: WorkspaceLayoutViewportSnapshot,
        surfaceRegistry: WorkspaceSurfaceRegistry,
        activeDropZone: DropZone?
    ) {
        frame = snapshot.frame
        synchronizeSlotFrameToBounds()
        currentSnapshot = snapshot
        let nextMountedContent = WorkspaceLayoutMountedTabEntry(
            contentId: snapshot.contentId,
            content: snapshot.content,
            mountIdentity: mountIdentity
        )

        if let mountedContent,
           (mountedContent.contentId != nextMountedContent.contentId
               || mountedContent.mountIdentity != nextMountedContent.mountIdentity) {
            surfaceRegistry.unmountContent(
                mountedContent.content,
                contentId: mountedContent.contentId,
                from: slotView
            )
            self.mountedContent = nil
        }

        surfaceRegistry.mountContent(
            snapshot.content,
            contentId: snapshot.contentId,
            in: slotView,
            activeDropZone: activeDropZone,
            onPresentationChange: { [weak self] in
                self?.updateRevealState(reason: "presentationChange", force: true)
            }
        )
        mountedContent = nextMountedContent
        refreshSurfacePresentation(reason: "apply", force: true)
    }

    #if DEBUG
    var debugSlotBounds: CGRect {
        slotView.bounds
    }

    var debugRevealPhase: WorkspaceSurfaceRevealPhase? {
        lastPresentationFacts?.revealPhase
    }

    var debugShowsRevealCover: Bool {
        !revealCoverView.isHidden
    }
    #endif

    func prepareForRemoval(surfaceRegistry: WorkspaceSurfaceRegistry) {
        if let mountedContent {
            surfaceRegistry.unmountContent(
                mountedContent.content,
                contentId: mountedContent.contentId,
                from: slotView
            )
        }
        currentSnapshot = nil
        lastPresentationFacts = nil
        mountedContent = nil
        revealCoverView.setVisible(false)
        removeFromSuperview()
    }

    private func refreshSurfacePresentation(reason: String, force: Bool) {
        guard currentSnapshot != nil else { return }
        guard let mountedContent else { return }
        surfaceRegistry.reconcileViewportLifecycle(
            mountedContent.content,
            contentId: mountedContent.contentId,
            in: slotView,
            reason: "viewport.\(reason)"
        )
        updateRevealState(reason: reason, force: force)
    }

    private func updateRevealState(reason: String, force: Bool) {
        guard let currentSnapshot else { return }
        let nextFacts = surfaceRegistry.presentationFacts(
            currentSnapshot.content,
            contentId: currentSnapshot.contentId
        )
        guard force || nextFacts != lastPresentationFacts else { return }
        lastPresentationFacts = nextFacts
        revealCoverView.setVisible(nextFacts.showsLoadingCover)
    }

    private func synchronizeSlotFrameToBounds() {
        guard slotView.frame != bounds else { return }
        slotView.frame = bounds
    }
}

@MainActor
private struct WorkspaceLayoutMountedTabEntry {
    let contentId: UUID
    let content: WorkspacePaneContent
    let mountIdentity: WorkspacePaneMountIdentity
}

struct WorkspaceLayoutPaneTabShortcutHintModifier: Equatable {
    let modifierFlags: NSEvent.ModifierFlags
    let symbol: String
}

enum WorkspaceLayoutPaneTabShortcutHintPolicy {
    static let intentionalHoldDelay: TimeInterval = 0.30

    static func hintModifier(
        for modifierFlags: NSEvent.ModifierFlags,
        defaults: UserDefaults = .standard
    ) -> WorkspaceLayoutPaneTabShortcutHintModifier? {
        guard ShortcutHintDebugSettings.showHintsOnCommandHoldEnabled(defaults: defaults) else {
            return nil
        }
        let shortcut = KeyboardShortcutSettings.selectSurfaceByNumberShortcut()
        guard !shortcut.hasChord else { return nil }
        let normalized = modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard normalized == shortcut.modifierFlags || normalized == [.command] else { return nil }
        return WorkspaceLayoutPaneTabShortcutHintModifier(
            modifierFlags: shortcut.modifierFlags,
            symbol: shortcut.modifierDisplayString
        )
    }

    static func isCurrentWindow(
        hostWindowNumber: Int?,
        hostWindowIsKey: Bool,
        eventWindowNumber: Int?,
        keyWindowNumber: Int?
    ) -> Bool {
        guard let hostWindowNumber, hostWindowIsKey else { return false }
        if let eventWindowNumber {
            return eventWindowNumber == hostWindowNumber
        }
        return keyWindowNumber == hostWindowNumber
    }

    static func shouldShowHints(
        for modifierFlags: NSEvent.ModifierFlags,
        hostWindowNumber: Int?,
        hostWindowIsKey: Bool,
        eventWindowNumber: Int?,
        keyWindowNumber: Int?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        hintModifier(for: modifierFlags, defaults: defaults) != nil &&
            isCurrentWindow(
                hostWindowNumber: hostWindowNumber,
                hostWindowIsKey: hostWindowIsKey,
                eventWindowNumber: eventWindowNumber,
                keyWindowNumber: keyWindowNumber
            )
    }
}

func workspaceLayoutTabControlShortcutDigit(for index: Int, tabCount: Int) -> Int? {
    for digit in 1...9 {
        if workspaceLayoutTabIndexForControlShortcutDigit(digit, tabCount: tabCount) == index {
            return digit
        }
    }
    return nil
}

func workspaceLayoutTabIndexForControlShortcutDigit(_ digit: Int, tabCount: Int) -> Int? {
    guard tabCount > 0, digit >= 1, digit <= 9 else { return nil }
    if digit == 9 {
        return tabCount - 1
    }
    let index = digit - 1
    return index < tabCount ? index : nil
}

@MainActor
private final class WorkspaceLayoutPaneTabShortcutHintMonitor {
    private(set) var isShortcutHintVisible = false {
        didSet {
            guard isShortcutHintVisible != oldValue else { return }
            onChange?()
        }
    }

    private(set) var shortcutModifierSymbol = "⌃" {
        didSet {
            guard shortcutModifierSymbol != oldValue else { return }
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private weak var hostWindow: NSWindow?
    private var hostWindowDidBecomeKeyObserver: NSObjectProtocol?
    private var hostWindowDidResignKeyObserver: NSObjectProtocol?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var pendingShowWorkItem: DispatchWorkItem?
    private var pendingModifier: WorkspaceLayoutPaneTabShortcutHintModifier?

    func setHostWindow(_ window: NSWindow?) {
        guard hostWindow !== window else { return }
        removeHostWindowObservers()
        hostWindow = window
        guard let window else {
            cancelPendingHintShow(resetVisible: true)
            return
        }

        hostWindowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update(from: NSEvent.modifierFlags, eventWindow: nil)
            }
        }

        hostWindowDidResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelPendingHintShow(resetVisible: true)
            }
        }

        update(from: NSEvent.modifierFlags, eventWindow: nil)
    }

    func start() {
        guard flagsMonitor == nil else {
            update(from: NSEvent.modifierFlags, eventWindow: nil)
            return
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.update(from: event.modifierFlags, eventWindow: event.window)
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isCurrentWindow(eventWindow: event.window) == true else { return event }
            self?.cancelPendingHintShow(resetVisible: true)
            return event
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelPendingHintShow(resetVisible: true)
            }
        }

        update(from: NSEvent.modifierFlags, eventWindow: nil)
    }

    func stop() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        removeHostWindowObservers()
        cancelPendingHintShow(resetVisible: true)
    }

    private func isCurrentWindow(eventWindow: NSWindow?) -> Bool {
        WorkspaceLayoutPaneTabShortcutHintPolicy.isCurrentWindow(
            hostWindowNumber: hostWindow?.windowNumber,
            hostWindowIsKey: hostWindow?.isKeyWindow ?? false,
            eventWindowNumber: eventWindow?.windowNumber,
            keyWindowNumber: NSApp.keyWindow?.windowNumber
        )
    }

    private func update(from modifierFlags: NSEvent.ModifierFlags, eventWindow: NSWindow?) {
        guard WorkspaceLayoutPaneTabShortcutHintPolicy.shouldShowHints(
            for: modifierFlags,
            hostWindowNumber: hostWindow?.windowNumber,
            hostWindowIsKey: hostWindow?.isKeyWindow ?? false,
            eventWindowNumber: eventWindow?.windowNumber,
            keyWindowNumber: NSApp.keyWindow?.windowNumber
        ) else {
            cancelPendingHintShow(resetVisible: true)
            return
        }

        guard let modifier = WorkspaceLayoutPaneTabShortcutHintPolicy.hintModifier(for: modifierFlags) else {
            cancelPendingHintShow(resetVisible: true)
            return
        }

        if isShortcutHintVisible {
            shortcutModifierSymbol = modifier.symbol
            return
        }

        queueHintShow(for: modifier)
    }

    private func queueHintShow(for modifier: WorkspaceLayoutPaneTabShortcutHintModifier) {
        if pendingModifier == modifier, pendingShowWorkItem != nil {
            return
        }

        pendingShowWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShowWorkItem = nil
            self.pendingModifier = nil
            guard WorkspaceLayoutPaneTabShortcutHintPolicy.shouldShowHints(
                for: NSEvent.modifierFlags,
                hostWindowNumber: self.hostWindow?.windowNumber,
                hostWindowIsKey: self.hostWindow?.isKeyWindow ?? false,
                eventWindowNumber: nil,
                keyWindowNumber: NSApp.keyWindow?.windowNumber
            ) else {
                return
            }
            guard let currentModifier = WorkspaceLayoutPaneTabShortcutHintPolicy.hintModifier(for: NSEvent.modifierFlags) else {
                return
            }
            self.shortcutModifierSymbol = currentModifier.symbol
            self.isShortcutHintVisible = true
        }

        pendingModifier = modifier
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + WorkspaceLayoutPaneTabShortcutHintPolicy.intentionalHoldDelay,
            execute: workItem
        )
    }

    private func cancelPendingHintShow(resetVisible: Bool) {
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        pendingModifier = nil
        if resetVisible {
            isShortcutHintVisible = false
        }
    }

    private func removeHostWindowObservers() {
        if let hostWindowDidBecomeKeyObserver {
            NotificationCenter.default.removeObserver(hostWindowDidBecomeKeyObserver)
            self.hostWindowDidBecomeKeyObserver = nil
        }
        if let hostWindowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(hostWindowDidResignKeyObserver)
            self.hostWindowDidResignKeyObserver = nil
        }
    }
}

@MainActor
private final class WorkspaceLayoutNativeTabBarView: NSView {
    private var snapshot: WorkspaceLayoutPaneChromeSnapshot?
    private var hostBridge: (WorkspaceLayoutInteractionHandlers)?
    private var presentation: WorkspaceLayoutPresentationSnapshot?
    private var localTabDrag: WorkspaceLayoutLocalDragSnapshot?
    private let shortcutHintMonitor = WorkspaceLayoutPaneTabShortcutHintMonitor()

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
        shortcutHintMonitor.onChange = { [weak self] in
            self?.rebuildButtons()
            self?.needsLayout = true
            self?.needsDisplay = true
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shortcutHintMonitor.setHostWindow(window)
        if window != nil {
            shortcutHintMonitor.start()
        } else {
            shortcutHintMonitor.stop()
        }
    }

    func update(
        snapshot: WorkspaceLayoutPaneChromeSnapshot,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        presentation: WorkspaceLayoutPresentationSnapshot,
        localTabDrag: WorkspaceLayoutLocalDragSnapshot?
    ) {
        self.snapshot = snapshot
        self.hostBridge = hostBridge
        self.presentation = presentation
        self.localTabDrag = localTabDrag
        wantsLayer = true
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: presentation.appearance
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
        documentView.update(
            snapshot: snapshot,
            hostBridge: hostBridge,
            presentation: presentation,
            localTabDrag: localTabDrag
        )
        rebuildButtons()
        rebuildSplitButtons()
        updateSplitButtonsVisibility()
        needsLayout = true
        needsDisplay = true
    }

    func updateLocalTabDrag(_ localTabDrag: WorkspaceLayoutLocalDragSnapshot?) {
        guard self.localTabDrag != localTabDrag else { return }
        self.localTabDrag = localTabDrag
        documentView.updateLocalTabDrag(localTabDrag)
    }

    override func layout() {
        super.layout()
        guard let presentation else { return }
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
            for: presentation.appearance
        ).cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let presentation else { return }
        let separatorColor = TabBarColors.nsColorSeparator(for: presentation.appearance)
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
        guard let snapshot, let hostBridge, let presentation else { return }
        let showsControlShortcutHints = snapshot.isFocused && shortcutHintMonitor.isShortcutHintVisible

        let existingById = Dictionary(uniqueKeysWithValues: tabButtons.map { ($0.tab.id, $0) })
        var nextButtons: [WorkspaceLayoutNativeTabButtonView] = []

        for (index, tabSnapshot) in snapshot.tabs.enumerated() {
            let tab = tabSnapshot.tab
            let button = existingById[tab.id] ?? WorkspaceLayoutNativeTabButtonView(frame: .zero)
            button.update(
                tab: tabSnapshot.tab,
                paneId: snapshot.paneId,
                isSelected: tabSnapshot.isSelected,
                isPaneFocused: snapshot.isFocused,
                showsZoomIndicator: tabSnapshot.showsZoomIndicator,
                controlShortcutDigit: workspaceLayoutTabControlShortcutDigit(for: index, tabCount: snapshot.tabs.count),
                showsControlShortcutHint: showsControlShortcutHints,
                shortcutModifierSymbol: shortcutHintMonitor.shortcutModifierSymbol,
                appearance: presentation.appearance,
                contextMenuState: tabSnapshot.contextMenuState,
                onSelect: { [weak self] in
                    guard let self else { return }
                    hostBridge.focusPane(snapshot.paneId)
                    hostBridge.selectTab(tab.id)
                    self.onTabMutation?()
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    guard !tab.isPinned else { return }
                    _ = hostBridge.requestCloseTab(tab.id, inPane: snapshot.paneId)
                    self.onTabMutation?()
                },
                onZoomToggle: { [weak self] in
                    guard let self else { return }
                    _ = hostBridge.togglePaneZoom(inPane: snapshot.paneId)
                    self.onTabMutation?()
                },
                onContextAction: { [weak self] action in
                    guard let self else { return }
                    hostBridge.requestTabContextAction(action, for: tab.id, inPane: snapshot.paneId)
                    self.onTabMutation?()
                },
                onBeginTabDrag: {
                    hostBridge.beginTabDrag(tabId: tab.id, sourcePaneId: snapshot.paneId)
                },
                onCancelTabDrag: {
                    hostBridge.clearDragState()
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
        guard let snapshot, let hostBridge, let presentation else { return }

        splitButtonsView.subviews.forEach { $0.removeFromSuperview() }
        guard snapshot.showSplitButtons else { return }

        let appearance = presentation.appearance
        let tooltips = appearance.splitButtonTooltips

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "terminal",
                tooltip: tooltips.newTerminal,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                hostBridge.requestNewTab(kind: .terminal, inPane: snapshot.paneId)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "globe",
                tooltip: tooltips.newBrowser,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                hostBridge.requestNewTab(kind: .browser, inPane: snapshot.paneId)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "square.split.2x1",
                tooltip: tooltips.splitRight,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                _ = hostBridge.splitPane(snapshot.paneId, orientation: .horizontal)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "square.split.1x2",
                tooltip: tooltips.splitDown,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                _ = hostBridge.splitPane(snapshot.paneId, orientation: .vertical)
                self?.onTabMutation?()
            }
        )
    }

    private func updateSplitButtonsVisibility() {
        guard let presentation, let snapshot else { return }
        let shouldShow = snapshot.showSplitButtons
            && (!presentation.isMinimalMode || isHovering || !presentation.appearance.splitButtonsOnHover)
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
    private var hostBridge: (WorkspaceLayoutInteractionHandlers)?
    private var presentation: WorkspaceLayoutPresentationSnapshot?
    private var localTabDrag: WorkspaceLayoutLocalDragSnapshot?
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

    func update(
        snapshot: WorkspaceLayoutPaneChromeSnapshot,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        presentation: WorkspaceLayoutPresentationSnapshot,
        localTabDrag: WorkspaceLayoutLocalDragSnapshot?
    ) {
        self.snapshot = snapshot
        self.hostBridge = hostBridge
        self.presentation = presentation
        self.localTabDrag = localTabDrag
    }

    func updateLocalTabDrag(_ localTabDrag: WorkspaceLayoutLocalDragSnapshot?) {
        self.localTabDrag = localTabDrag
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
        guard let presentation else { return }
        let appearance = presentation.appearance
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

    private func effectiveTargetIndex(for point: NSPoint) -> Int? {
        guard let snapshot else { return nil }
        let rawTargetIndex = targetIndex(for: point)
        return workspaceLayoutEffectiveTabDropTargetIndex(
            rawTargetIndex: rawTargetIndex,
            tabIds: snapshot.tabs.map(\.tab.id),
            paneId: snapshot.paneId,
            localTabDrag: localTabDrag
        )
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
        guard let presentation else { return false }
        guard presentation.isInteractive else { return false }
        if localTabDrag != nil {
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
        let targetIndex = effectiveTargetIndex(for: convert(sender.draggingLocation, from: nil))
        updateDropIndicator(targetIndex: targetIndex)
        return targetIndex == nil ? [] : .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard validateSplitTabDrop(sender) else { return [] }
        let targetIndex = effectiveTargetIndex(for: convert(sender.draggingLocation, from: nil))
        updateDropIndicator(targetIndex: targetIndex)
        return targetIndex == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateDropIndicator(targetIndex: nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard validateSplitTabDrop(sender) else { return false }
        return effectiveTargetIndex(for: convert(sender.draggingLocation, from: nil)) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let snapshot, let hostBridge else { return false }
        guard let destinationIndex = effectiveTargetIndex(for: convert(sender.draggingLocation, from: nil)) else {
            updateDropIndicator(targetIndex: nil)
            return false
        }

        if let localDrag = localTabDrag {
            let draggedTabId = localDrag.tabId
            let sourcePaneId = localDrag.sourcePaneId
            if sourcePaneId == snapshot.paneId {
                _ = hostBridge.moveTab(
                    draggedTabId,
                    toPane: snapshot.paneId,
                    atIndex: destinationIndex
                )
                hostBridge.focusPane(snapshot.paneId)
            } else {
                _ = hostBridge.moveTab(
                    draggedTabId,
                    toPane: snapshot.paneId,
                    atIndex: destinationIndex
                )
            }
            hostBridge.clearDragState()
            updateDropIndicator(targetIndex: nil)
            onDropPerformed?()
            return true
        }

        guard let transfer = workspaceSplitDecodeTransfer(from: sender.draggingPasteboard),
              transfer.isFromCurrentProcess else {
            updateDropIndicator(targetIndex: nil)
            return false
        }

        let request = WorkspaceLayoutExternalTabDropRequest(
            tabId: transfer.tabId,
            sourcePaneId: PaneID(id: transfer.sourcePaneId),
            destination: .insert(targetPane: snapshot.paneId, targetIndex: destinationIndex)
        )
        let handled = hostBridge.handleExternalTabDrop(request)
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
private struct WorkspaceLayoutPaneTabShortcutHintPill: View {
    let text: String
    let fontSize: CGFloat
    let textColor: NSColor

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color(nsColor: textColor))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(ShortcutHintPillBackground())
    }
}

private final class WorkspaceLayoutShortcutHintPillView: NSHostingView<WorkspaceLayoutPaneTabShortcutHintPill> {

    required init(rootView: WorkspaceLayoutPaneTabShortcutHintPill) {
        super.init(rootView: rootView)
        translatesAutoresizingMaskIntoConstraints = false
    }

    convenience init(frame frameRect: NSRect) {
        self.init(
            rootView: WorkspaceLayoutPaneTabShortcutHintPill(
                text: "",
                fontSize: 9,
                textColor: .labelColor
            )
        )
        frame = frameRect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, fontSize: CGFloat, textColor: NSColor) {
        rootView = WorkspaceLayoutPaneTabShortcutHintPill(
            text: text,
            fontSize: fontSize,
            textColor: textColor
        )
        invalidateIntrinsicContentSize()
    }

    func applyAppearance() {}
}

@MainActor
final class WorkspaceLayoutNativeTabButtonView: NSView, NSDraggingSource {
    private(set) var tab: WorkspaceLayout.Tab = WorkspaceLayout.Tab(title: "")
    private var paneId: PaneID = PaneID()
    private var isSelected: Bool = false
    private var isPaneFocused: Bool = false
    private var showsZoomIndicator: Bool = false
    private var controlShortcutDigit: Int?
    private var showsControlShortcutHint = false
    private var shortcutModifierSymbol = "⌃"
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
    private var onSelect: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onZoomToggle: (() -> Void)?
    private var onContextAction: ((TabContextAction) -> Void)?
    private var onBeginTabDrag: (() -> Void)?
    private var onCancelTabDrag: (() -> Void)?

    private let iconView = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(frame: .zero)
    private let closeButton = WorkspaceLayoutHoverButton(frame: .zero)
    private let zoomButton = WorkspaceLayoutHoverButton(frame: .zero)
    private let pinView = NSImageView(frame: .zero)
    private let dirtyDot = NSView(frame: .zero)
    private let unreadDot = NSView(frame: .zero)
    private let spinner = NSProgressIndicator(frame: .zero)
    private let shortcutHintView = WorkspaceLayoutShortcutHintPillView(frame: .zero)
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
            accessibilityDescription: String(
                localized: "workspace.menu.exitZoomPane",
                defaultValue: "Exit Zoom"
            )
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
            accessibilityDescription: String(
                localized: "workspace.accessibility.pinnedTab",
                defaultValue: "Pinned Tab"
            )
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

        shortcutHintView.alphaValue = 0
        shortcutHintView.isHidden = true
        addSubview(shortcutHintView)
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
        isPaneFocused: Bool,
        showsZoomIndicator: Bool,
        controlShortcutDigit: Int?,
        showsControlShortcutHint: Bool,
        shortcutModifierSymbol: String,
        appearance: WorkspaceLayoutConfiguration.Appearance,
        contextMenuState: TabContextMenuState,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onZoomToggle: @escaping () -> Void,
        onContextAction: @escaping (TabContextAction) -> Void,
        onBeginTabDrag: @escaping () -> Void,
        onCancelTabDrag: @escaping () -> Void
    ) {
        self.tab = tab
        self.paneId = paneId
        self.isSelected = isSelected
        self.isPaneFocused = isPaneFocused
        self.showsZoomIndicator = showsZoomIndicator
        self.controlShortcutDigit = controlShortcutDigit
        self.showsControlShortcutHint = showsControlShortcutHint
        self.shortcutModifierSymbol = shortcutModifierSymbol
        self.splitAppearance = appearance
        self.contextMenuState = contextMenuState
        self.onSelect = onSelect
        self.onClose = onClose
        self.onZoomToggle = onZoomToggle
        self.onContextAction = onContextAction
        self.onBeginTabDrag = onBeginTabDrag
        self.onCancelTabDrag = onCancelTabDrag

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

        let nextShowsShortcutHint = showsShortcutHint
        closeButton.isHidden = nextShowsShortcutHint || tab.isPinned || !(isSelected || isHovered || isCloseHovered)
        if closeButton.isHidden {
            isCloseHovered = false
            isClosePressed = false
        }
        pinView.isHidden = nextShowsShortcutHint || !tab.isPinned || closeButton.isHidden == false
        zoomButton.isHidden = !showsZoomIndicator
        if zoomButton.isHidden {
            isZoomHovered = false
            isZoomPressed = false
        }

        unreadDot.isHidden = nextShowsShortcutHint || isSelected || isHovered || isCloseHovered || !tab.showsNotificationBadge
        dirtyDot.isHidden = nextShowsShortcutHint || isSelected || isHovered || isCloseHovered || !tab.isDirty
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
        shortcutHintView.applyAppearance()
        if let shortcutHintLabel {
            shortcutHintView.update(
                text: shortcutHintLabel,
                fontSize: accessoryFontSize,
                textColor: isSelected
                    ? TabBarColors.nsColorActiveText(for: splitAppearance)
                    : TabBarColors.nsColorInactiveText(for: splitAppearance)
            )
        }
        if nextShowsShortcutHint != !shortcutHintView.isHidden {
            shortcutHintView.layer?.removeAllAnimations()
            shortcutHintView.isHidden = false
            let shouldRemainVisible = nextShowsShortcutHint
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shortcutHintView.animator().alphaValue = nextShowsShortcutHint ? 1 : 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                if !shouldRemainVisible {
                    self.shortcutHintView.isHidden = true
                }
            }
        } else {
            shortcutHintView.alphaValue = nextShowsShortcutHint ? 1 : 0
            shortcutHintView.isHidden = !nextShowsShortcutHint
        }
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
            ? (accessorySlotSize + trailingAccessorySlotWidth)
            : trailingAccessorySlotWidth
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
            x: bounds.maxX - TabBarMetrics.tabHorizontalPadding - trailingAccessorySlotWidth + ((trailingAccessorySlotWidth - accessorySlotSize) / 2),
            y: centerY - (accessorySlotSize / 2),
            width: accessorySlotSize,
            height: accessorySlotSize
        )
        closeButton.layer?.cornerRadius = closeButton.bounds.height / 2
        pinView.frame = closeButton.frame
        let shortcutHintSlotFrame = CGRect(
            x: bounds.maxX - TabBarMetrics.tabHorizontalPadding - trailingAccessorySlotWidth,
            y: centerY - (accessorySlotSize / 2),
            width: trailingAccessorySlotWidth,
            height: accessorySlotSize
        )
        shortcutHintView.frame = shortcutHintSlotFrame.offsetBy(dx: paneShortcutHintXOffset, dy: paneShortcutHintYOffset)

        if showsZoomIndicator {
            zoomButton.frame = CGRect(
                x: shortcutHintSlotFrame.minX - accessorySlotSize,
                y: centerY - (accessorySlotSize / 2),
                width: accessorySlotSize,
                height: accessorySlotSize
            )
            zoomButton.layer?.cornerRadius = zoomButton.bounds.height / 2
        } else {
            zoomButton.frame = .zero
        }

        let trailingAccessoryMinX = showsZoomIndicator ? zoomButton.frame.minX : shortcutHintSlotFrame.minX
        let titleMinX = iconSlotRect.maxX + TabBarMetrics.contentSpacing
        let titleMaxX = trailingAccessoryMinX - (showsZoomIndicator ? TabBarMetrics.contentSpacing : 0)
        let titleFrameMinX = titleMinX + tuning.titleDX + tuning.iconDX
        titleLabel.frame = CGRect(
            x: titleFrameMinX,
            y: centerY - 7 + tuning.titleDY,
            width: max(0, titleMaxX - titleFrameMinX),
            height: 14
        )
        let indicatorCenterX = closeButton.frame.midX
        let indicatorStartX = indicatorCenterX - (TabBarMetrics.notificationBadgeSize / 2)
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
            TabBarColors.nsColorSelectedIndicator(
                for: splitAppearance,
                focused: isPaneFocused
            ).setFill()
            CGRect(
                x: 0,
                y: bounds.height - TabBarMetrics.activeIndicatorHeight,
                width: max(0, bounds.width - 1),
                height: TabBarMetrics.activeIndicatorHeight
            ).fill()
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
              let onBeginTabDrag else { return }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - dragStartLocation.x, point.y - dragStartLocation.y)
        guard distance >= 3 else { return }
        dragStarted = true

        let transferTabId = tab.id
        onBeginTabDrag()

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

        workspaceSplitAddMenuItem(
            String(localized: "command.renameTab.title", defaultValue: "Rename Tab…"),
            action: .rename,
            to: menu,
            handler: onContextAction
        )

        if contextMenuState.hasCustomTitle {
            workspaceSplitAddMenuItem(
                String(localized: "workspace.menu.removeCustomTabName", defaultValue: "Remove Custom Tab Name"),
                action: .clearName,
                to: menu,
                handler: onContextAction
            )
        }

        menu.addItem(.separator())
        workspaceSplitAddMenuItem(
            String(localized: "workspace.menu.closeTabsToLeft", defaultValue: "Close Tabs to Left"),
            action: .closeToLeft,
            to: menu,
            enabled: contextMenuState.canCloseToLeft,
            handler: onContextAction
        )
        workspaceSplitAddMenuItem(
            String(localized: "workspace.menu.closeTabsToRight", defaultValue: "Close Tabs to Right"),
            action: .closeToRight,
            to: menu,
            enabled: contextMenuState.canCloseToRight,
            handler: onContextAction
        )
        workspaceSplitAddMenuItem(
            String(localized: "menu.file.closeOtherTabs", defaultValue: "Close Other Tabs in Pane"),
            action: .closeOthers,
            to: menu,
            enabled: contextMenuState.canCloseOthers,
            handler: onContextAction
        )
        workspaceSplitAddMenuItem(
            String(localized: "dialog.moveTab.title", defaultValue: "Move Tab"),
            action: .move,
            to: menu,
            handler: onContextAction
        )

        if contextMenuState.isTerminal {
            workspaceSplitAddMenuItem(
                String(localized: "workspace.menu.moveToLeftPane", defaultValue: "Move to Left Pane"),
                action: .moveToLeftPane,
                to: menu,
                enabled: contextMenuState.canMoveToLeftPane,
                handler: onContextAction
            )
            workspaceSplitAddMenuItem(
                String(localized: "workspace.menu.moveToRightPane", defaultValue: "Move to Right Pane"),
                action: .moveToRightPane,
                to: menu,
                enabled: contextMenuState.canMoveToRightPane,
                handler: onContextAction
            )
        }

        menu.addItem(.separator())
        workspaceSplitAddMenuItem(
            String(localized: "workspace.menu.newTerminalTabToRight", defaultValue: "New Terminal Tab to Right"),
            action: .newTerminalToRight,
            to: menu,
            handler: onContextAction
        )
        workspaceSplitAddMenuItem(
            String(localized: "workspace.menu.newBrowserTabToRight", defaultValue: "New Browser Tab to Right"),
            action: .newBrowserToRight,
            to: menu,
            handler: onContextAction
        )

        if contextMenuState.isBrowser {
            menu.addItem(.separator())
            workspaceSplitAddMenuItem(
                String(localized: "workspace.menu.reloadTab", defaultValue: "Reload Tab"),
                action: .reload,
                to: menu,
                handler: onContextAction
            )
            workspaceSplitAddMenuItem(
                String(localized: "workspace.menu.duplicateTab", defaultValue: "Duplicate Tab"),
                action: .duplicate,
                to: menu,
                handler: onContextAction
            )
        }

        menu.addItem(.separator())

        if contextMenuState.hasSplits {
            workspaceSplitAddMenuItem(
                contextMenuState.isZoomed
                    ? String(localized: "workspace.menu.exitZoomPane", defaultValue: "Exit Zoom")
                    : String(localized: "workspace.menu.zoomPane", defaultValue: "Zoom Pane"),
                action: .toggleZoom,
                to: menu,
                handler: onContextAction
            )
        }

        workspaceSplitAddMenuItem(
            contextMenuState.isPinned
                ? String(localized: "command.unpinTab.title", defaultValue: "Unpin Tab")
                : String(localized: "command.pinTab.title", defaultValue: "Pin Tab"),
            action: .togglePin,
            to: menu,
            handler: onContextAction
        )

        if contextMenuState.isUnread {
            workspaceSplitAddMenuItem(
                String(localized: "command.markTabRead.title", defaultValue: "Mark Tab as Read"),
                action: .markAsRead,
                to: menu,
                enabled: contextMenuState.canMarkAsRead,
                handler: onContextAction
            )
        } else {
            workspaceSplitAddMenuItem(
                String(localized: "command.markTabUnread.title", defaultValue: "Mark Tab as Unread"),
                action: .markAsUnread,
                to: menu,
                enabled: contextMenuState.canMarkAsUnread,
                handler: onContextAction
            )
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
            onCancelTabDrag?()
        }
    }

    private func refreshChrome() {
        guard let onSelect,
              let onClose,
              let onZoomToggle,
              let onContextAction,
              let onBeginTabDrag,
              let onCancelTabDrag else { return }
        update(
            tab: tab,
            paneId: paneId,
            isSelected: isSelected,
            isPaneFocused: isPaneFocused,
            showsZoomIndicator: showsZoomIndicator,
            controlShortcutDigit: controlShortcutDigit,
            showsControlShortcutHint: showsControlShortcutHint,
            shortcutModifierSymbol: shortcutModifierSymbol,
            appearance: splitAppearance,
            contextMenuState: contextMenuState,
            onSelect: onSelect,
            onClose: onClose,
            onZoomToggle: onZoomToggle,
            onContextAction: onContextAction,
            onBeginTabDrag: onBeginTabDrag,
            onCancelTabDrag: onCancelTabDrag
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
        let iconPointSizeDelta = WorkspaceLayoutTabChromeDebugTuning.current.iconPointSizeDelta
#else
        let iconPointSizeDelta = CGFloat(-0.5)
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
            pointSize: symbolPointSize(for: iconName) + iconPointSizeDelta,
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
        if showsShortcutHint {
            return
        }

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

    private var shortcutHintLabel: String? {
        guard let controlShortcutDigit else { return nil }
        return "\(shortcutModifierSymbol)\(controlShortcutDigit)"
    }

    private var showsShortcutHint: Bool {
        (showsControlShortcutHint || alwaysShowShortcutHints) && shortcutHintLabel != nil
    }

    private var alwaysShowShortcutHints: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ShortcutHintDebugSettings.alwaysShowHintsKey) != nil else {
            return ShortcutHintDebugSettings.defaultAlwaysShowHints
        }
        return defaults.bool(forKey: ShortcutHintDebugSettings.alwaysShowHintsKey)
    }

    private var paneShortcutHintXOffset: CGFloat {
        let defaults = UserDefaults.standard
        let value: Double
        if defaults.object(forKey: ShortcutHintDebugSettings.paneHintXKey) != nil {
            value = defaults.double(forKey: ShortcutHintDebugSettings.paneHintXKey)
        } else {
            value = ShortcutHintDebugSettings.defaultPaneHintX
        }
        return CGFloat(ShortcutHintDebugSettings.clamped(value))
    }

    private var paneShortcutHintYOffset: CGFloat {
        let defaults = UserDefaults.standard
        let value: Double
        if defaults.object(forKey: ShortcutHintDebugSettings.paneHintYKey) != nil {
            value = defaults.double(forKey: ShortcutHintDebugSettings.paneHintYKey)
        } else {
            value = ShortcutHintDebugSettings.defaultPaneHintY
        }
        return CGFloat(ShortcutHintDebugSettings.clamped(value))
    }

    private var trailingAccessorySlotWidth: CGFloat {
        guard let label = shortcutHintLabel else {
            return accessorySlotSize
        }
        let font = shortcutHintFont()
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let positiveDebugInset = max(0, paneShortcutHintXOffset) + 2
        return max(accessorySlotSize, textWidth + 8 + positiveDebugInset)
    }

    private func shortcutHintFont() -> NSFont {
        NSFont.systemFont(ofSize: accessoryFontSize, weight: .semibold)
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
    private var hostBridge: (WorkspaceLayoutInteractionHandlers)?
    private var presentation: WorkspaceLayoutPresentationSnapshot?
    private var localTabDrag: WorkspaceLayoutLocalDragSnapshot?
    private var onZoneUpdated: ((DropZone) -> Void)?
    private var onZoneCleared: (() -> Void)?
    private var onDropSucceeded: (() -> Void)?
    private var onHideAnimationCompleted: ((UInt64) -> Void)?
    private var onDropPerformed: (() -> Void)?
    private let overlayShapeView = NSView(frame: .zero)
    private var overlayPresentation: WorkspacePaneDropOverlayPresentation = .hidden

    var hitTestPassthroughEnabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        overlayShapeView.wantsLayer = true
        overlayShapeView.isHidden = true
        overlayShapeView.alphaValue = 1
        if let layer = overlayShapeView.layer {
            layer.cornerRadius = 8
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.borderWidth = 2
        }
        addSubview(overlayShapeView)
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

    override func layout() {
        super.layout()
        guard let zone = overlayPresentation.zone else { return }
        let targetFrame = WorkspacePaneDropRouting.overlayFrame(for: zone, in: bounds.size)
        if !Self.rectApproximatelyEqual(overlayShapeView.frame, targetFrame) {
            overlayShapeView.frame = targetFrame
        }
    }

    func update(
        paneId: PaneID,
        hostBridge: WorkspaceLayoutInteractionHandlers,
        presentation: WorkspaceLayoutPresentationSnapshot,
        localTabDrag: WorkspaceLayoutLocalDragSnapshot?,
        overlayPresentation: WorkspacePaneDropOverlayPresentation,
        onZoneUpdated: @escaping (DropZone) -> Void,
        onZoneCleared: @escaping () -> Void,
        onDropSucceeded: @escaping () -> Void,
        onHideAnimationCompleted: @escaping (UInt64) -> Void,
        onDropPerformed: @escaping () -> Void
    ) {
        self.paneId = paneId
        self.hostBridge = hostBridge
        self.presentation = presentation
        self.localTabDrag = localTabDrag
        self.onZoneUpdated = onZoneUpdated
        self.onZoneCleared = onZoneCleared
        self.onDropSucceeded = onDropSucceeded
        self.onHideAnimationCompleted = onHideAnimationCompleted
        self.onDropPerformed = onDropPerformed
        updateOverlayPresentation(overlayPresentation)
    }

    func updateLocalTabDrag(_ localTabDrag: WorkspaceLayoutLocalDragSnapshot?) {
        self.localTabDrag = localTabDrag
    }

    func updateOverlayPresentation(_ overlayPresentation: WorkspacePaneDropOverlayPresentation) {
        let previousPresentation = self.overlayPresentation
        guard previousPresentation != overlayPresentation else { return }
        self.overlayPresentation = overlayPresentation
        applyOverlayPresentationTransition(from: previousPresentation, to: overlayPresentation)
    }

    private static func rectApproximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        epsilon: CGFloat = 0.5
    ) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= epsilon &&
            abs(lhs.origin.y - rhs.origin.y) <= epsilon &&
            abs(lhs.size.width - rhs.size.width) <= epsilon &&
            abs(lhs.size.height - rhs.size.height) <= epsilon
    }

    private func applyOverlayPresentationTransition(
        from previousPresentation: WorkspacePaneDropOverlayPresentation,
        to nextPresentation: WorkspacePaneDropOverlayPresentation
    ) {
        switch nextPresentation.phase {
        case .hidden:
            overlayShapeView.layer?.removeAllAnimations()
            overlayShapeView.isHidden = true
            overlayShapeView.alphaValue = 1

        case .visible:
            guard let zone = nextPresentation.zone else { return }
            let targetFrame = WorkspacePaneDropRouting.overlayFrame(for: zone, in: bounds.size)
            let isSameFrame = Self.rectApproximatelyEqual(overlayShapeView.frame, targetFrame)
            let zoneChanged = previousPresentation.zone != zone

            if overlayShapeView.isHidden || previousPresentation.phase != .visible {
                overlayShapeView.layer?.removeAllAnimations()
                overlayShapeView.frame = targetFrame
                overlayShapeView.alphaValue = 0
                overlayShapeView.isHidden = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    overlayShapeView.animator().alphaValue = 1
                }
                return
            }

            if zoneChanged && !isSameFrame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    overlayShapeView.animator().frame = targetFrame
                }
            } else if !isSameFrame {
                overlayShapeView.frame = targetFrame
            }

            if overlayShapeView.alphaValue < 1 {
                overlayShapeView.layer?.removeAllAnimations()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    overlayShapeView.animator().alphaValue = 1
                }
            }

        case .hiding:
            guard let zone = nextPresentation.zone else {
                onHideAnimationCompleted?(nextPresentation.generation)
                return
            }

            let targetFrame = WorkspacePaneDropRouting.overlayFrame(for: zone, in: bounds.size)
            if !Self.rectApproximatelyEqual(overlayShapeView.frame, targetFrame) {
                overlayShapeView.frame = targetFrame
            }
            overlayShapeView.layer?.removeAllAnimations()
            guard !overlayShapeView.isHidden else {
                onHideAnimationCompleted?(nextPresentation.generation)
                return
            }

            let generation = nextPresentation.generation
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                overlayShapeView.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.overlayPresentation.phase == .hiding else { return }
                    guard self.overlayPresentation.generation == generation else { return }
                    self.overlayShapeView.isHidden = true
                    self.overlayShapeView.alphaValue = 1
                    self.onHideAnimationCompleted?(generation)
                }
            }
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let paneId, let presentation else { return [] }
        guard presentation.isInteractive else { return [] }

        if sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil {
            guard localTabDrag != nil
                || workspaceSplitDecodeTransfer(from: sender.draggingPasteboard)?.isFromCurrentProcess == true else {
                return []
            }
            let location = convert(sender.draggingLocation, from: nil)
            let sourcePaneId = localTabDrag?.sourcePaneId
            let decision = WorkspacePaneDropRouting.decision(
                for: location,
                in: bounds.size,
                targetPaneId: paneId,
                sourcePaneId: sourcePaneId
            )
            let zone = decision.finalZone
            onZoneUpdated?(zone)
            return .move
        }

        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        if let urls, !urls.isEmpty {
            onZoneUpdated?(.center)
            return .copy
        }

        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onZoneCleared?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let paneId, let hostBridge else { return false }

        if sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil {
            let zone = overlayPresentation.zone ?? WorkspacePaneDropRouting.zone(
                for: convert(sender.draggingLocation, from: nil),
                in: bounds.size
            )

            if let localDrag = localTabDrag {
                let draggedTabId = localDrag.tabId
                let sourcePaneId = localDrag.sourcePaneId
                hostBridge.clearDragState()

                if zone == .center {
                    if sourcePaneId != paneId {
                        _ = hostBridge.moveTab(draggedTabId, toPane: paneId, atIndex: nil)
                    }
                    onDropSucceeded?()
                    onDropPerformed?()
                    return true
                }

                guard let orientation = zone.orientation else {
                    onZoneCleared?()
                    return false
                }
                _ = hostBridge.splitPane(
                    paneId,
                    orientation: orientation,
                    movingTab: draggedTabId,
                    insertFirst: zone.insertsFirst,
                    focusNewPane: true
                )
                onDropSucceeded?()
                onDropPerformed?()
                return true
            }

            guard let transfer = workspaceSplitDecodeTransfer(from: sender.draggingPasteboard),
                  transfer.isFromCurrentProcess else {
                onZoneCleared?()
                return false
            }

            let destination: WorkspaceLayoutExternalTabDropRequest.Destination
            if zone == .center {
                destination = .insert(targetPane: paneId, targetIndex: nil)
            } else if let orientation = zone.orientation {
                destination = .split(targetPane: paneId, orientation: orientation, insertFirst: zone.insertsFirst)
            } else {
                return false
            }

            let request = WorkspaceLayoutExternalTabDropRequest(
                tabId: transfer.tabId,
                sourcePaneId: PaneID(id: transfer.sourcePaneId),
                destination: destination
            )
            let handled = hostBridge.handleExternalTabDrop(request)
            if handled {
                onDropSucceeded?()
                onDropPerformed?()
            } else {
                onZoneCleared?()
            }
            return handled
        }

        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let handled = hostBridge.handleFileDrop(urls, in: paneId)
        if handled {
            onDropSucceeded?()
            onDropPerformed?()
        } else {
            onZoneCleared?()
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
    let terminalTab = WorkspaceLayout.Tab.rendered(
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
            tab: WorkspaceLayout.Tab.rendered(
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
            tab: WorkspaceLayout.Tab.rendered(
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
            tab: WorkspaceLayout.Tab.rendered(
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
            tab: WorkspaceLayout.Tab.rendered(
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
    let view = WorkspaceLayoutNativeTabButtonView(frame: .zero)
    let renderTab = scenario.tab
    view.update(
        tab: renderTab,
        paneId: PaneID(),
        isSelected: scenario.isSelected,
        isPaneFocused: true,
        showsZoomIndicator: scenario.showsZoomIndicator,
        controlShortcutDigit: nil,
        showsControlShortcutHint: false,
        shortcutModifierSymbol: "⌃",
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
        onSelect: {},
        onClose: {},
        onZoomToggle: {},
        onContextAction: { _ in },
        onBeginTabDrag: {},
        onCancelTabDrag: {}
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
        let tab = WorkspaceLayout.Tab.rendered(
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
            isPaneFocused: true,
            showsZoomIndicator: false,
            controlShortcutDigit: nil,
            showsControlShortcutHint: false,
            shortcutModifierSymbol: "⌃",
            appearance: appearance,
            contextMenuState: contextMenuState,
            onSelect: {},
            onClose: {},
            onZoomToggle: {},
            onContextAction: { _ in },
            onBeginTabDrag: {},
            onCancelTabDrag: {}
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
                y: size.height / 2,
                width: size.width - (padding * 2),
                height: (size.height / 2) - padding
            )
        case .bottom:
            return CGRect(
                x: padding,
                y: padding,
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
