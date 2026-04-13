import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct WorkspaceSplitNativeHost<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Bindable private var controller: WorkspaceSplitController
    private let nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?
    private let contentBuilder: (WorkspaceSplit.Tab, PaneID) -> Content
    private let emptyPaneBuilder: (PaneID) -> EmptyContent
    private let showSplitButtons: Bool
    private let contentViewLifecycle: ContentViewLifecycle
    private let onGeometryChange: ((_ isDragging: Bool) -> Void)?

    init(
        controller: WorkspaceSplitController,
        nativeContent: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?,
        @ViewBuilder content: @escaping (WorkspaceSplit.Tab, PaneID) -> Content,
        @ViewBuilder emptyPane: @escaping (PaneID) -> EmptyContent,
        showSplitButtons: Bool,
        contentViewLifecycle: ContentViewLifecycle,
        onGeometryChange: ((_ isDragging: Bool) -> Void)?
    ) {
        self.controller = controller
        self.nativeContentBuilder = nativeContent
        self.contentBuilder = content
        self.emptyPaneBuilder = emptyPane
        self.showSplitButtons = showSplitButtons
        self.contentViewLifecycle = contentViewLifecycle
        self.onGeometryChange = onGeometryChange
    }

    func makeNSView(context: Context) -> WorkspaceSplitRootHostView<Content, EmptyContent> {
        let view = WorkspaceSplitRootHostView(
            controller: controller,
            nativeContentBuilder: nativeContentBuilder,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle,
            onGeometryChange: onGeometryChange
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: WorkspaceSplitRootHostView<Content, EmptyContent>, context: Context) {
        nsView.update(
            controller: controller,
            nativeContentBuilder: nativeContentBuilder,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle,
            onGeometryChange: onGeometryChange
        )
    }
}

@MainActor
final class WorkspaceSplitRootHostView<Content: View, EmptyContent: View>: NSView {
    private var controller: WorkspaceSplitController
    private var nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?
    private var contentBuilder: (WorkspaceSplit.Tab, PaneID) -> Content
    private var emptyPaneBuilder: (PaneID) -> EmptyContent
    private var showSplitButtons: Bool
    private var contentViewLifecycle: ContentViewLifecycle
    private var onGeometryChange: ((_ isDragging: Bool) -> Void)?

    private var currentRootView: NSView?
    private var paneHosts: [UUID: WorkspaceSplitPaneHostView<Content, EmptyContent>] = [:]
    private var splitHosts: [UUID: WorkspaceSplitNativeSplitView<Content, EmptyContent>] = [:]
    private var renderedPaneIds: Set<UUID> = []
    private var renderedSplitIds: Set<UUID> = []
    private var lastContainerFrame: CGRect = .zero

    init(
        controller: WorkspaceSplitController,
        nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?,
        contentBuilder: @escaping (WorkspaceSplit.Tab, PaneID) -> Content,
        emptyPaneBuilder: @escaping (PaneID) -> EmptyContent,
        showSplitButtons: Bool,
        contentViewLifecycle: ContentViewLifecycle,
        onGeometryChange: ((_ isDragging: Bool) -> Void)?
    ) {
        self.controller = controller
        self.nativeContentBuilder = nativeContentBuilder
        self.contentBuilder = contentBuilder
        self.emptyPaneBuilder = emptyPaneBuilder
        self.showSplitButtons = showSplitButtons
        self.contentViewLifecycle = contentViewLifecycle
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
        controller: WorkspaceSplitController,
        nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?,
        contentBuilder: @escaping (WorkspaceSplit.Tab, PaneID) -> Content,
        emptyPaneBuilder: @escaping (PaneID) -> EmptyContent,
        showSplitButtons: Bool,
        contentViewLifecycle: ContentViewLifecycle,
        onGeometryChange: ((_ isDragging: Bool) -> Void)?
    ) {
        self.controller = controller
        self.nativeContentBuilder = nativeContentBuilder
        self.contentBuilder = contentBuilder
        self.emptyPaneBuilder = emptyPaneBuilder
        self.showSplitButtons = showSplitButtons
        self.contentViewLifecycle = contentViewLifecycle
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
        let renderedNode = controller.internalController.zoomedNode ?? controller.internalController.rootNode
        let nextPaneIds = Set(renderedNode.allPaneIds.map(\.id))
        let nextSplitIds = Set(workspaceSplitCollectSplitIDs(in: renderedNode))
        let topologyChanged = nextPaneIds != renderedPaneIds || nextSplitIds != renderedSplitIds

        if topologyChanged {
            resetHostCaches()
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

        let nextRootView = hostView(for: renderedNode)

        if currentRootView !== nextRootView {
            currentRootView?.removeFromSuperview()
            addSubview(nextRootView)
            currentRootView = nextRootView
        }

        currentRootView?.frame = bounds
        renderedPaneIds = nextPaneIds
        renderedSplitIds = nextSplitIds
        if !topologyChanged {
            cleanupUnusedHosts()
        }
    }

    private func resetHostCaches() {
        currentRootView?.removeFromSuperview()
        currentRootView = nil
        for host in splitHosts.values {
            host.removeAllChildren()
        }
        paneHosts.removeAll()
        splitHosts.removeAll()
    }

    private func cleanupUnusedHosts() {
        let livePaneIds = Set(controller.internalController.rootNode.allPaneIds.map(\.id))
        let liveSplitIds = Set(workspaceSplitCollectSplitIDs(in: controller.internalController.rootNode))

        for (id, host) in paneHosts where !livePaneIds.contains(id) {
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

    private func hostView(for node: SplitNode) -> NSView {
        switch node {
        case .pane(let pane):
            return paneHost(for: pane)
        case .split(let split):
            return splitHost(for: split)
        }
    }

    private func paneHost(for pane: PaneState) -> WorkspaceSplitPaneHostView<Content, EmptyContent> {
        if let existing = paneHosts[pane.id.id] {
            existing.update(
                pane: pane,
                controller: controller,
                nativeContentBuilder: nativeContentBuilder,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
            return existing
        }

        let host = WorkspaceSplitPaneHostView(
            rootHost: self,
            pane: pane,
            controller: controller,
            nativeContentBuilder: nativeContentBuilder,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        paneHosts[pane.id.id] = host
        return host
    }

    private func splitHost(for split: SplitState) -> WorkspaceSplitNativeSplitView<Content, EmptyContent> {
        if let existing = splitHosts[split.id] {
            existing.update(
                splitState: split,
                rootHost: self,
                firstChild: hostView(for: split.first),
                secondChild: hostView(for: split.second),
                appearance: controller.configuration.appearance
            )
            return existing
        }

        let host = WorkspaceSplitNativeSplitView(
            splitState: split,
            rootHost: self,
            firstChild: hostView(for: split.first),
            secondChild: hostView(for: split.second),
            appearance: controller.configuration.appearance
        )
        splitHosts[split.id] = host
        return host
    }
}

private func workspaceSplitCollectSplitIDs(in node: SplitNode) -> [UUID] {
    switch node {
    case .pane:
        return []
    case .split(let split):
        return [split.id]
            + workspaceSplitCollectSplitIDs(in: split.first)
            + workspaceSplitCollectSplitIDs(in: split.second)
    }
}

@MainActor
private final class WorkspaceSplitNativeSplitView<Content: View, EmptyContent: View>: NSSplitView, NSSplitViewDelegate {
    private weak var rootHost: WorkspaceSplitRootHostView<Content, EmptyContent>?
    private var splitState: SplitState
    private var splitAppearance: WorkspaceSplitConfiguration.Appearance

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
        rootHost: WorkspaceSplitRootHostView<Content, EmptyContent>,
        firstChild: NSView,
        secondChild: NSView,
        appearance: WorkspaceSplitConfiguration.Appearance
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
        rootHost: WorkspaceSplitRootHostView<Content, EmptyContent>,
        firstChild: NSView,
        secondChild: NSView,
        appearance: WorkspaceSplitConfiguration.Appearance
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
            DispatchQueue.main.async { [weak self] in
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

        DispatchQueue.main.async { [weak self] in
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
private final class WorkspaceSplitPaneHostView<Content: View, EmptyContent: View>: NSView {
    private weak var rootHost: WorkspaceSplitRootHostView<Content, EmptyContent>?
    private var pane: PaneState
    private var controller: WorkspaceSplitController
    private var nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?
    private var contentBuilder: (WorkspaceSplit.Tab, PaneID) -> Content
    private var emptyPaneBuilder: (PaneID) -> EmptyContent
    private var showSplitButtons: Bool
    private var contentViewLifecycle: ContentViewLifecycle

    private let tabBarView = WorkspaceSplitNativeTabBarView(frame: .zero)
    private let contentContainer = NSView(frame: .zero)
    private let dropOverlayView = WorkspaceSplitPaneDropOverlayView(frame: .zero)
    private var mountedTabContent: [UUID: WorkspaceSplitMountedPaneContent] = [:]
    private var emptyContentHostingController: NSHostingController<AnyView>?
    private var emptyContentSlotView: WorkspaceSplitPaneContentSlotView?
    private var activeDropZone: DropZone? = nil

    init(
        rootHost: WorkspaceSplitRootHostView<Content, EmptyContent>,
        pane: PaneState,
        controller: WorkspaceSplitController,
        nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?,
        contentBuilder: @escaping (WorkspaceSplit.Tab, PaneID) -> Content,
        emptyPaneBuilder: @escaping (PaneID) -> EmptyContent,
        showSplitButtons: Bool,
        contentViewLifecycle: ContentViewLifecycle
    ) {
        self.rootHost = rootHost
        self.pane = pane
        self.controller = controller
        self.nativeContentBuilder = nativeContentBuilder
        self.contentBuilder = contentBuilder
        self.emptyPaneBuilder = emptyPaneBuilder
        self.showSplitButtons = showSplitButtons
        self.contentViewLifecycle = contentViewLifecycle
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
            pane: pane,
            controller: controller,
            nativeContentBuilder: nativeContentBuilder,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        pane: PaneState,
        controller: WorkspaceSplitController,
        nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?,
        contentBuilder: @escaping (WorkspaceSplit.Tab, PaneID) -> Content,
        emptyPaneBuilder: @escaping (PaneID) -> EmptyContent,
        showSplitButtons: Bool,
        contentViewLifecycle: ContentViewLifecycle
    ) {
        self.pane = pane
        self.controller = controller
        self.nativeContentBuilder = nativeContentBuilder
        self.contentBuilder = contentBuilder
        self.emptyPaneBuilder = emptyPaneBuilder
        self.showSplitButtons = showSplitButtons
        self.contentViewLifecycle = contentViewLifecycle
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: controller.configuration.appearance
        ).cgColor

        tabBarView.update(
            pane: pane,
            controller: controller,
            showSplitButtons: showSplitButtons,
            isFocused: controller.focusedPaneId == pane.id
        )
        tabBarView.onTabMutation = { [weak self] in
            self?.refreshContent()
            self?.rootHost?.notifyGeometryChanged(isDragging: false)
        }

        dropOverlayView.update(
            pane: pane,
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

    override func layout() {
        super.layout()
        let barHeight = controller.configuration.appearance.tabBarHeight
        let topY = max(0, bounds.height - barHeight)
        tabBarView.frame = CGRect(x: 0, y: topY, width: bounds.width, height: barHeight)
        contentContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: topY)
        dropOverlayView.frame = contentContainer.frame
        emptyContentSlotView?.frame = contentContainer.bounds
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
        guard !pane.tabs.isEmpty else {
            dropOverlayView.prefersNativeDropOverlay = false
            removeAllMountedTabContent()
            showEmptyContent()
            return
        }

        hideEmptyContent()

        let selectedId = pane.selectedTabId ?? pane.tabs.first?.id
        let targetTabs: [TabItem]
        switch contentViewLifecycle {
        case .recreateOnSwitch:
            targetTabs = [pane.selectedTab ?? pane.tabs.first].compactMap { $0 }
        case .keepAllAlive:
            targetTabs = pane.tabs
        }

        let targetIds = Set(targetTabs.map(\.id))
        for tab in targetTabs {
            refreshContent(for: tab, selectedId: selectedId)
        }

        for (tabId, content) in mountedTabContent where !targetIds.contains(tabId) {
            tearDownMountedContent(content)
            mountedTabContent.removeValue(forKey: tabId)
        }
    }

    private func showEmptyContent() {
        let rootView = AnyView(
            emptyPaneBuilder(pane.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )

        if let emptyContentHostingController, let emptyContentSlotView {
            emptyContentHostingController.rootView = rootView
            emptyContentSlotView.isHidden = false
            return
        }

        let next = NSHostingController(rootView: rootView)
        next.view.translatesAutoresizingMaskIntoConstraints = true
        next.view.autoresizingMask = [.width, .height]
        next.view.frame = contentContainer.bounds

        let slotView = WorkspaceSplitPaneContentSlotView(frame: contentContainer.bounds)
        slotView.autoresizingMask = [.width, .height]
        slotView.installContentView(next.view)
        contentContainer.addSubview(slotView)

        emptyContentHostingController = next
        emptyContentSlotView = slotView
    }

    private func hideEmptyContent() {
        emptyContentSlotView?.isHidden = true
    }

    private func removeAllMountedTabContent() {
        for content in mountedTabContent.values {
            tearDownMountedContent(content)
        }
        mountedTabContent.removeAll()
    }

    private func refreshContent(for tab: TabItem, selectedId: UUID?) {
        let tabModel = WorkspaceSplit.Tab(from: tab)
        let isSelected = tab.id == selectedId

        if let nativeContent = nativeContentBuilder?(tabModel, pane.id) {
            if isSelected {
                dropOverlayView.prefersNativeDropOverlay = nativeContent.prefersNativeDropOverlay
            }
            switch nativeContent {
            case .terminal(let descriptor):
                refreshTerminalContent(
                    descriptor,
                    for: tab.id,
                    isSelected: isSelected
                )
            }
#if DEBUG
            if isSelected {
                let paneShort = String(pane.id.id.uuidString.prefix(5))
                let tabShort = String(tab.id.uuidString.prefix(5))
                startupLog(
                    "startup.host.refreshContent.native pane=\(paneShort) " +
                        "tab=\(tabShort)"
                )
            }
#endif
            return
        }

        if let existing = mountedTabContent[tab.id],
           case .terminal(let descriptor, let slotView) = existing {
            if isSelected {
                dropOverlayView.prefersNativeDropOverlay = true
            }
            applyTerminalContent(
                descriptor,
                slotView: slotView,
                isSelected: isSelected
            )
#if DEBUG
            if isSelected {
                let paneShort = String(pane.id.id.uuidString.prefix(5))
                let tabShort = String(tab.id.uuidString.prefix(5))
                let panelShort = String(descriptor.panel.id.uuidString.prefix(5))
                startupLog(
                    "startup.host.refreshContent.cachedTerminal pane=\(paneShort) " +
                        "tab=\(tabShort) panel=\(panelShort)"
                )
            }
#endif
            return
        }

#if DEBUG
        if isSelected {
            let paneShort = String(pane.id.id.uuidString.prefix(5))
            let tabShort = String(tab.id.uuidString.prefix(5))
            startupLog(
                "startup.host.refreshContent.swiftUI pane=\(paneShort) " +
                    "tab=\(tabShort)"
            )
        }
#endif
        if isSelected {
            dropOverlayView.prefersNativeDropOverlay = tabModel.prefersNativeDropOverlay
        }
        refreshSwiftUIContent(
            for: tabModel,
            tabId: tab.id,
            isSelected: isSelected
        )
    }

    private func refreshTerminalContent(
        _ descriptor: WorkspaceTerminalPaneContent,
        for tabId: UUID,
        isSelected: Bool
    ) {
        let slotView: WorkspaceSplitPaneContentSlotView
        if let existing = mountedTabContent[tabId],
           case .terminal(let previousDescriptor, let existingSlotView) = existing,
           previousDescriptor.panel === descriptor.panel {
            slotView = existingSlotView
        } else {
            if let existing = mountedTabContent[tabId] {
                tearDownMountedContent(existing)
            }
            let nextSlotView = WorkspaceSplitPaneContentSlotView(frame: contentContainer.bounds)
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
        slotView: WorkspaceSplitPaneContentSlotView,
        isSelected: Bool
    ) {
        if slotView.superview !== contentContainer {
            slotView.removeFromSuperview()
            contentContainer.addSubview(slotView)
        }
        slotView.frame = contentContainer.bounds
        slotView.installContentView(descriptor.panel.hostedView)
        slotView.isHidden = !isSelected

        let panel = descriptor.panel
        let hostedView = descriptor.panel.hostedView
        hostedView.attachSurface(panel.surface)
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
#if DEBUG
        if isSelected {
            let paneShort = String(pane.id.id.uuidString.prefix(5))
            let panelShort = String(panel.id.uuidString.prefix(5))
            let visible = descriptor.isVisibleInUI ? 1 : 0
            let focused = descriptor.isFocused ? 1 : 0
            let hostWindow = slotView.window != nil ? 1 : 0
            let hostedWindow = hostedView.window != nil ? 1 : 0
            let runtime = panel.surface.surface != nil ? 1 : 0
            startupLog(
                "startup.host.applyTerminal pane=\(paneShort) panel=\(panelShort) " +
                    "visible=\(visible) focused=\(focused) hostWindow=\(hostWindow) " +
                    "hostedWindow=\(hostedWindow) runtime=\(runtime)"
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

    private func refreshSwiftUIContent(
        for tab: WorkspaceSplit.Tab,
        tabId: UUID,
        isSelected: Bool
    ) {
        let rootView = AnyView(
            contentBuilder(tab, pane.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.paneDropZone, isSelected ? activeDropZone : nil)
                .transaction { tx in
                    tx.disablesAnimations = true
                }
                .animation(nil, value: pane.selectedTabId)
        )

        let entry: WorkspaceSplitMountedPaneContent
        if let existing = mountedTabContent[tabId],
           case .swiftUI(let hostingController, let slotView) = existing {
            hostingController.rootView = rootView
            slotView.installContentView(hostingController.view)
            entry = .swiftUI(hostingController: hostingController, slotView: slotView)
        } else {
            if let existing = mountedTabContent[tabId] {
                tearDownMountedContent(existing)
            }
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = true
            hostingController.view.autoresizingMask = [.width, .height]
            hostingController.view.frame = contentContainer.bounds

            let slotView = WorkspaceSplitPaneContentSlotView(frame: contentContainer.bounds)
            slotView.autoresizingMask = [.width, .height]
            slotView.installContentView(hostingController.view)
            contentContainer.addSubview(slotView)

            entry = .swiftUI(hostingController: hostingController, slotView: slotView)
            mountedTabContent[tabId] = entry
        }

        guard case .swiftUI(_, let slotView) = entry else { return }
        if slotView.superview !== contentContainer {
            slotView.removeFromSuperview()
            contentContainer.addSubview(slotView)
        }
        slotView.frame = contentContainer.bounds
        slotView.isHidden = !isSelected
    }

    private func tearDownMountedContent(_ content: WorkspaceSplitMountedPaneContent) {
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
        case .swiftUI(let hostingController, let slotView):
            hostingController.view.removeFromSuperview()
            slotView.removeFromSuperview()
        }
    }
}

@MainActor
private final class WorkspaceSplitPaneContentSlotView: NSView {
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
private enum WorkspaceSplitMountedPaneContent {
    case terminal(descriptor: WorkspaceTerminalPaneContent, slotView: WorkspaceSplitPaneContentSlotView)
    case swiftUI(hostingController: NSHostingController<AnyView>, slotView: WorkspaceSplitPaneContentSlotView)

    var slotView: WorkspaceSplitPaneContentSlotView {
        switch self {
        case .terminal(_, let slotView), .swiftUI(_, let slotView):
            return slotView
        }
    }
}

@MainActor
private final class WorkspaceSplitNativeTabBarView: NSView {
    private var pane: PaneState?
    private var controller: WorkspaceSplitController?
    private var isFocused: Bool = false
    private var showSplitButtons: Bool = true

    private let scrollView = NSScrollView(frame: .zero)
    private let documentView = WorkspaceSplitTabDocumentView(frame: .zero)
    private let splitButtonsView = NSStackView(frame: .zero)
    private var tabButtons: [WorkspaceSplitNativeTabButtonView] = []
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

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
        pane: PaneState,
        controller: WorkspaceSplitController,
        showSplitButtons: Bool,
        isFocused: Bool
    ) {
        self.pane = pane
        self.controller = controller
        self.showSplitButtons = showSplitButtons
        self.isFocused = isFocused
        wantsLayer = true
        layer?.backgroundColor = TabBarColors.nsColorPaneBackground(
            for: controller.configuration.appearance
        ).cgColor
        documentView.update(pane: pane, controller: controller)
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
        let separatorRect = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        separatorRect.fill()
    }

    private func rebuildButtons() {
        guard let pane, let controller else { return }

        let existingById = Dictionary(uniqueKeysWithValues: tabButtons.map { ($0.tab.id, $0) })
        var nextButtons: [WorkspaceSplitNativeTabButtonView] = []

        for (index, tab) in pane.tabs.enumerated() {
            let button = existingById[tab.id] ?? WorkspaceSplitNativeTabButtonView(frame: .zero)
            let context = workspaceSplitContextMenuState(
                for: tab,
                in: pane,
                at: index,
                controller: controller
            )
            button.update(
                tab: tab,
                paneId: pane.id,
                isSelected: pane.selectedTabId == tab.id,
                showsZoomIndicator: controller.zoomedPaneId == pane.id && pane.selectedTabId == tab.id,
                appearance: controller.configuration.appearance,
                contextMenuState: context,
                splitViewController: controller.internalController,
                onSelect: { [weak self] in
                    guard let self else { return }
                    controller.focusPane(pane.id)
                    controller.selectTab(TabID(id: tab.id))
                    self.onTabMutation?()
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    guard !tab.isPinned else { return }
                    controller.onTabCloseRequest?(TabID(id: tab.id), pane.id)
                    _ = controller.closeTab(TabID(id: tab.id), inPane: pane.id)
                    self.onTabMutation?()
                },
                onZoomToggle: { [weak self] in
                    guard let self else { return }
                    _ = controller.togglePaneZoom(inPane: pane.id)
                    self.onTabMutation?()
                },
                onContextAction: { [weak self] action in
                    guard let self else { return }
                    controller.requestTabContextAction(action, for: TabID(id: tab.id), inPane: pane.id)
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
        needsLayout = true
        if let selected = pane.selectedTabId,
           let selectedButton = tabButtons.first(where: { $0.tab.id == selected }) {
            scrollView.contentView.scrollToVisible(selectedButton.frame.insetBy(dx: -32, dy: 0))
        }
    }

    private func rebuildSplitButtons() {
        guard let pane, let controller else { return }

        splitButtonsView.subviews.forEach { $0.removeFromSuperview() }
        guard showSplitButtons else { return }

        let appearance = controller.configuration.appearance
        let tooltips = appearance.splitButtonTooltips

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "terminal",
                tooltip: tooltips.newTerminal,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                controller.requestNewTab(kind: "terminal", inPane: pane.id)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "globe",
                tooltip: tooltips.newBrowser,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                controller.requestNewTab(kind: "browser", inPane: pane.id)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "square.split.2x1",
                tooltip: tooltips.splitRight,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                _ = controller.splitPane(pane.id, orientation: .horizontal)
                self?.onTabMutation?()
            }
        )

        splitButtonsView.addArrangedSubview(
            workspaceSplitMakeSymbolButton(
                symbolName: "square.split.1x2",
                tooltip: tooltips.splitDown,
                color: TabBarColors.nsColorInactiveText(for: appearance)
            ) { [weak self] in
                _ = controller.splitPane(pane.id, orientation: .vertical)
                self?.onTabMutation?()
            }
        )
    }

    private func updateSplitButtonsVisibility() {
        guard let controller else { return }
        let presentationMode = UserDefaults.standard.string(forKey: "workspacePresentationMode") ?? "standard"
        let isMinimalMode = presentationMode == "minimal"
        let shouldShow = showSplitButtons && (!isMinimalMode || isHovering || !controller.configuration.appearance.splitButtonsOnHover)
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
private final class WorkspaceSplitTabDocumentView: NSView {
    private var pane: PaneState?
    private var controller: WorkspaceSplitController?
    private var tabButtons: [WorkspaceSplitNativeTabButtonView] = []
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

    func update(pane: PaneState, controller: WorkspaceSplitController) {
        self.pane = pane
        self.controller = controller
    }

    func setTabButtons(_ buttons: [WorkspaceSplitNativeTabButtonView]) {
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
        if controller.internalController.activeDragTab != nil || controller.internalController.draggingTab != nil {
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
        guard let pane, let controller else { return false }
        let destinationIndex = targetIndex(for: convert(sender.draggingLocation, from: nil))

        if let draggedTab = controller.internalController.activeDragTab ?? controller.internalController.draggingTab,
           let sourcePaneId = controller.internalController.activeDragSourcePaneId ?? controller.internalController.dragSourcePaneId {
            if sourcePaneId == pane.id,
               let sourceIndex = pane.tabs.firstIndex(where: { $0.id == draggedTab.id }),
               (destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1) {
                workspaceSplitClearDragState(controller.internalController)
                updateDropIndicator(targetIndex: nil)
                return true
            }

            if sourcePaneId == pane.id {
                pane.moveTab(from: pane.tabs.firstIndex(where: { $0.id == draggedTab.id }) ?? 0, to: destinationIndex)
                pane.selectTab(draggedTab.id)
                controller.focusPane(pane.id)
            } else {
                _ = controller.moveTab(
                    TabID(id: draggedTab.id),
                    toPane: pane.id,
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

        let request = WorkspaceSplitController.ExternalTabDropRequest(
            tabId: TabID(id: transfer.tab.id),
            sourcePaneId: PaneID(id: transfer.sourcePaneId),
            destination: .insert(targetPane: pane.id, targetIndex: destinationIndex)
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
private final class WorkspaceSplitNativeTabButtonView: NSView, NSDraggingSource {
    private(set) var tab: TabItem = TabItem(title: "")
    private var paneId: PaneID = PaneID()
    private var isSelected: Bool = false
    private var showsZoomIndicator: Bool = false
    private var splitAppearance: WorkspaceSplitConfiguration.Appearance = .default
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
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(frame: .zero)
    private let zoomButton = NSButton(frame: .zero)
    private let pinView = NSImageView(frame: .zero)
    private let dirtyDot = NSView(frame: .zero)
    private let unreadDot = NSView(frame: .zero)
    private let spinner = NSProgressIndicator(frame: .zero)
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isCloseHovered = false
    private var isZoomHovered = false
    private var dragStartLocation: NSPoint?
    private var dragStarted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: TabBarMetrics.titleFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)

        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close Tab"
        )
        closeButton.bezelStyle = .inline
        closeButton.target = self
        closeButton.action = #selector(handleCloseButton)
        closeButton.sendAction(on: .leftMouseUp)
        addSubview(closeButton)

        zoomButton.isBordered = false
        zoomButton.image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Exit Zoom"
        )
        zoomButton.bezelStyle = .inline
        zoomButton.target = self
        zoomButton.action = #selector(handleZoomButton)
        zoomButton.sendAction(on: .leftMouseUp)
        addSubview(zoomButton)

        pinView.image = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: "Pinned Tab"
        )
        pinView.imageScaling = .scaleProportionallyDown
        addSubview(pinView)

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = TabBarMetrics.dirtyIndicatorSize / 2
        addSubview(dirtyDot)

        unreadDot.wantsLayer = true
        unreadDot.layer?.cornerRadius = TabBarMetrics.notificationBadgeSize / 2
        addSubview(unreadDot)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)
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

    func update(
        tab: TabItem,
        paneId: PaneID,
        isSelected: Bool,
        showsZoomIndicator: Bool,
        appearance: WorkspaceSplitConfiguration.Appearance,
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

        titleLabel.stringValue = tab.title
        titleLabel.textColor = isSelected
            ? TabBarColors.nsColorActiveText(for: splitAppearance)
            : TabBarColors.nsColorInactiveText(for: splitAppearance)

        if tab.isLoading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }

        if let imageData = tab.iconImageData,
           let image = NSImage(data: imageData) {
            image.isTemplate = false
            iconView.image = image
            iconView.contentTintColor = nil
        } else if let icon = tab.icon {
            iconView.image = workspaceSplitSymbolImage(named: icon)
            iconView.contentTintColor = isSelected
                ? TabBarColors.nsColorActiveText(for: splitAppearance)
                : TabBarColors.nsColorInactiveText(for: splitAppearance)
        } else {
            iconView.image = nil
        }

        closeButton.isHidden = tab.isPinned || !(isSelected || isHovered || isCloseHovered)
        pinView.isHidden = !tab.isPinned || closeButton.isHidden == false
        zoomButton.isHidden = !showsZoomIndicator

        unreadDot.isHidden = isSelected || isHovered || isCloseHovered || !tab.showsNotificationBadge
        dirtyDot.isHidden = isSelected || isHovered || isCloseHovered || !tab.isDirty
        unreadDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        dirtyDot.layer?.backgroundColor = TabBarColors.nsColorActiveText(for: splitAppearance).withAlphaComponent(0.72).cgColor

        closeButton.contentTintColor = isCloseHovered
            ? TabBarColors.nsColorActiveText(for: splitAppearance)
            : TabBarColors.nsColorInactiveText(for: splitAppearance)
        zoomButton.contentTintColor = isZoomHovered
            ? TabBarColors.nsColorActiveText(for: splitAppearance)
            : TabBarColors.nsColorInactiveText(for: splitAppearance)
        pinView.contentTintColor = TabBarColors.nsColorInactiveText(for: splitAppearance)

        needsLayout = true
        needsDisplay = true
    }

    func preferredWidth(minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let titleWidth = ceil((tab.title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: TabBarMetrics.titleFontSize)
        ]).width)
        let extra: CGFloat = 44
        return min(maxWidth, max(minWidth, titleWidth + extra))
    }

    override func layout() {
        super.layout()
        let contentX = TabBarMetrics.tabHorizontalPadding
        let centerY = bounds.midY

        let iconRect = CGRect(
            x: contentX,
            y: centerY - (TabBarMetrics.iconSize / 2),
            width: TabBarMetrics.iconSize,
            height: TabBarMetrics.iconSize
        )
        iconView.frame = iconRect
        spinner.frame = iconRect

        let trailingX = bounds.maxX - TabBarMetrics.tabHorizontalPadding - TabBarMetrics.closeButtonSize
        closeButton.frame = CGRect(
            x: trailingX,
            y: centerY - (TabBarMetrics.closeButtonSize / 2),
            width: TabBarMetrics.closeButtonSize,
            height: TabBarMetrics.closeButtonSize
        )
        pinView.frame = closeButton.frame

        if showsZoomIndicator {
            zoomButton.frame = CGRect(
                x: trailingX - TabBarMetrics.closeButtonSize - 2,
                y: centerY - (TabBarMetrics.closeButtonSize / 2),
                width: TabBarMetrics.closeButtonSize,
                height: TabBarMetrics.closeButtonSize
            )
        } else {
            zoomButton.frame = .zero
        }

        let trailingAccessoryMinX = showsZoomIndicator ? zoomButton.frame.minX : closeButton.frame.minX
        let titleMinX = iconRect.maxX + TabBarMetrics.contentSpacing
        let titleMaxX = trailingAccessoryMinX - 6
        titleLabel.frame = CGRect(
            x: titleMinX,
            y: centerY - 7,
            width: max(0, titleMaxX - titleMinX),
            height: 14
        )

        unreadDot.frame = CGRect(
            x: bounds.maxX - TabBarMetrics.tabHorizontalPadding - TabBarMetrics.notificationBadgeSize,
            y: centerY - (TabBarMetrics.notificationBadgeSize / 2),
            width: TabBarMetrics.notificationBadgeSize,
            height: TabBarMetrics.notificationBadgeSize
        )
        dirtyDot.frame = CGRect(
            x: unreadDot.isHidden ? unreadDot.frame.minX : unreadDot.frame.minX - TabBarMetrics.dirtyIndicatorSize - 2,
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
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        refreshChrome()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
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

        splitViewController.dragGeneration += 1
        splitViewController.draggingTab = tab
        splitViewController.dragSourcePaneId = paneId
        splitViewController.activeDragTab = tab
        splitViewController.activeDragSourcePaneId = paneId

        let pasteboardItem = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(TabTransferData(tab: tab, sourcePaneId: paneId.id)) {
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
}

@MainActor
private final class WorkspaceSplitPaneDropOverlayView: NSView {
    private var pane: PaneState?
    private var controller: WorkspaceSplitController?
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
        pane: PaneState,
        controller: WorkspaceSplitController,
        activeDropZone: DropZone?,
        onZoneChanged: @escaping (DropZone?) -> Void,
        onDropPerformed: @escaping () -> Void
    ) {
        self.pane = pane
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
        let frame = workspaceSplitOverlayFrame(for: zone, in: bounds.size)
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
        guard let pane, let controller else { return [] }
        guard controller.internalController.isInteractive else { return [] }

        if sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil {
            guard controller.internalController.activeDragTab != nil
                || controller.internalController.draggingTab != nil
                || workspaceSplitDecodeTransfer(from: sender.draggingPasteboard)?.isFromCurrentProcess == true else {
                return []
            }
            let zone = workspaceSplitEffectivePaneDropZone(
                at: convert(sender.draggingLocation, from: nil),
                size: bounds.size,
                pane: pane,
                controller: controller
            )
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
        guard let pane, let controller else { return false }

        if sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)]) != nil {
            let zone = activeDropZone ?? workspaceSplitEffectivePaneDropZone(
                at: convert(sender.draggingLocation, from: nil),
                size: bounds.size,
                pane: pane,
                controller: controller
            )

            if let draggedTab = controller.internalController.activeDragTab ?? controller.internalController.draggingTab,
               let sourcePaneId = controller.internalController.activeDragSourcePaneId ?? controller.internalController.dragSourcePaneId {
                workspaceSplitClearDragState(controller.internalController)
                activeDropZone = nil
                onZoneChanged?(nil)

                if zone == .center {
                    if sourcePaneId != pane.id {
                        _ = controller.moveTab(TabID(id: draggedTab.id), toPane: pane.id, atIndex: nil)
                    }
                    onDropPerformed?()
                    return true
                }

                guard let orientation = zone.orientation else { return false }
                _ = controller.splitPane(
                    pane.id,
                    orientation: orientation,
                    movingTab: TabID(id: draggedTab.id),
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

            let destination: WorkspaceSplitController.ExternalTabDropRequest.Destination
            if zone == .center {
                destination = .insert(targetPane: pane.id, targetIndex: nil)
            } else if let orientation = zone.orientation {
                destination = .split(targetPane: pane.id, orientation: orientation, insertFirst: zone.insertsFirst)
            } else {
                return false
            }

            let request = WorkspaceSplitController.ExternalTabDropRequest(
                tabId: TabID(id: transfer.tab.id),
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
        let handled = controller.onFileDrop?(urls, pane.id) ?? false
        activeDropZone = nil
        onZoneChanged?(nil)
        if handled {
            onDropPerformed?()
        }
        return handled
    }
}

@MainActor
private func workspaceSplitContextMenuState(
    for tab: TabItem,
    in pane: PaneState,
    at index: Int,
    controller: WorkspaceSplitController
) -> TabContextMenuState {
    let leftTabs = pane.tabs.prefix(index)
    let canCloseToLeft = leftTabs.contains(where: { !$0.isPinned })
    let canCloseToRight: Bool
    if (index + 1) < pane.tabs.count {
        canCloseToRight = pane.tabs.suffix(from: index + 1).contains(where: { !$0.isPinned })
    } else {
        canCloseToRight = false
    }
    let canCloseOthers = pane.tabs.enumerated().contains { itemIndex, item in
        itemIndex != index && !item.isPinned
    }
    return TabContextMenuState(
        isPinned: tab.isPinned,
        isUnread: tab.showsNotificationBadge,
        isBrowser: tab.kind == "browser",
        isTerminal: tab.kind == "terminal",
        hasCustomTitle: tab.hasCustomTitle,
        canCloseToLeft: canCloseToLeft,
        canCloseToRight: canCloseToRight,
        canCloseOthers: canCloseOthers,
        canMoveToLeftPane: controller.adjacentPane(to: pane.id, direction: .left) != nil,
        canMoveToRightPane: controller.adjacentPane(to: pane.id, direction: .right) != nil,
        isZoomed: controller.zoomedPaneId == pane.id,
        hasSplits: controller.allPaneIds.count > 1,
        shortcuts: controller.contextMenuShortcuts
    )
}

private func workspaceSplitSymbolImage(named name: String) -> NSImage? {
    let size = (name == "terminal.fill" || name == "terminal" || name == "globe")
        ? max(10, TabBarMetrics.iconSize - 2.5)
        : TabBarMetrics.iconSize
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
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

private func workspaceSplitSnapshotImage(for view: NSView) -> NSImage? {
    guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    guard let rep else { return nil }
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
    for appearance: WorkspaceSplitConfiguration.Appearance
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
    controller.draggingTab = nil
    controller.dragSourcePaneId = nil
    controller.activeDragTab = nil
    controller.activeDragSourcePaneId = nil
}

private func workspaceSplitOverlayFrame(for zone: DropZone, in size: CGSize) -> CGRect {
    let padding: CGFloat = 4
    switch zone {
    case .center:
        return CGRect(x: padding, y: padding, width: size.width - (padding * 2), height: size.height - (padding * 2))
    case .left:
        return CGRect(x: padding, y: padding, width: (size.width / 2) - padding, height: size.height - (padding * 2))
    case .right:
        return CGRect(x: size.width / 2, y: padding, width: (size.width / 2) - padding, height: size.height - (padding * 2))
    case .top:
        return CGRect(x: padding, y: padding, width: size.width - (padding * 2), height: (size.height / 2) - padding)
    case .bottom:
        return CGRect(x: padding, y: size.height / 2, width: size.width - (padding * 2), height: (size.height / 2) - padding)
    }
}

private func workspaceSplitPaneDropZone(for location: CGPoint, size: CGSize) -> DropZone {
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

@MainActor
private func workspaceSplitEffectivePaneDropZone(
    at location: CGPoint,
    size: CGSize,
    pane: PaneState,
    controller: WorkspaceSplitController
) -> DropZone {
    let defaultZone = workspaceSplitPaneDropZone(for: location, size: size)
    guard let draggedTab = controller.internalController.activeDragTab ?? controller.internalController.draggingTab,
          let sourcePaneId = controller.internalController.activeDragSourcePaneId ?? controller.internalController.dragSourcePaneId else {
        return defaultZone
    }

    guard draggedTab.kind == "terminal",
          sourcePaneId != pane.id else {
        return defaultZone
    }

    if defaultZone == .left,
       controller.adjacentPane(to: sourcePaneId, direction: .right) == pane.id {
        return .center
    }

    if defaultZone == .right,
       controller.adjacentPane(to: sourcePaneId, direction: .left) == pane.id {
        return .center
    }

    return defaultZone
}
