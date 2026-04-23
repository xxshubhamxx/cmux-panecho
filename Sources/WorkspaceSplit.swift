import Foundation
import SwiftUI

struct WorkspacePaneID: Hashable, Codable, Sendable, CustomStringConvertible {
    let id: UUID

    init() {
        self.id = UUID()
    }

    init(id: UUID) {
        self.id = id
    }

    var description: String {
        id.uuidString
    }
}

typealias PaneID = WorkspacePaneID

struct WorkspaceTabID: Hashable, Codable, Sendable, CustomStringConvertible {
    private let rawValue: UUID

    private enum CodingKeys: String, CodingKey {
        case id
        case rawValue
    }

    init() {
        self.rawValue = UUID()
    }

    init(uuid: UUID) {
        self.rawValue = uuid
    }

    var uuid: UUID {
        rawValue
    }

    var description: String {
        rawValue.uuidString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(UUID.self, forKey: .id) {
            self.rawValue = id
            return
        }
        // Backward compatibility for older payloads encoded as {"rawValue": ...}.
        self.rawValue = try container.decode(UUID.self, forKey: .rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Keep field name stable for workspace/session restore compatibility.
        try container.encode(rawValue, forKey: .id)
    }
}

typealias TabID = WorkspaceTabID

enum WorkspaceLayoutOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

typealias SplitOrientation = WorkspaceLayoutOrientation

enum WorkspaceNavigationDirection: String, Codable, Sendable {
    case left
    case right
    case up
    case down
}

typealias NavigationDirection = WorkspaceNavigationDirection

enum WorkspaceTabContextAction: String, CaseIterable, Sendable {
    case rename
    case clearName
    case closeToLeft
    case closeToRight
    case closeOthers
    case move
    case moveToLeftPane
    case moveToRightPane
    case newTerminalToRight
    case newBrowserToRight
    case reload
    case duplicate
    case togglePin
    case markAsRead
    case markAsUnread
    case toggleZoom
}

typealias TabContextAction = WorkspaceTabContextAction

struct WorkspacePixelRect: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(from cgRect: CGRect) {
        self.x = Double(cgRect.origin.x)
        self.y = Double(cgRect.origin.y)
        self.width = Double(cgRect.size.width)
        self.height = Double(cgRect.size.height)
    }
}

typealias PixelRect = WorkspacePixelRect

struct PaneGeometry: Codable, Sendable, Equatable {
    let paneId: String
    let frame: PixelRect
    let selectedTabId: String?
    let tabIds: [String]
}

struct LayoutSnapshot: Codable, Sendable, Equatable {
    let containerFrame: PixelRect
    let panes: [PaneGeometry]
    let focusedPaneId: String?
    let timestamp: TimeInterval
}

struct ExternalTab: Codable, Sendable, Equatable {
    let id: String
    let title: String
}

struct ExternalPaneNode: Codable, Sendable, Equatable {
    let id: String
    let frame: PixelRect
    let tabs: [ExternalTab]
    let selectedTabId: String?
}

struct ExternalSplitNode: Codable, Sendable, Equatable {
    let id: String
    let orientation: String
    let dividerPosition: Double
    let first: ExternalTreeNode
    let second: ExternalTreeNode
}

indirect enum ExternalTreeNode: Codable, Sendable, Equatable {
    case pane(ExternalPaneNode)
    case split(ExternalSplitNode)

    private enum CodingKeys: String, CodingKey {
        case type
        case pane
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "pane":
            self = .pane(try container.decode(ExternalPaneNode.self, forKey: .pane))
        case "split":
            self = .split(try container.decode(ExternalSplitNode.self, forKey: .split))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported external tree node"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let pane):
            try container.encode("pane", forKey: .type)
            try container.encode(pane, forKey: .pane)
        case .split(let split):
            try container.encode("split", forKey: .type)
            try container.encode(split, forKey: .split)
        }
    }
}

enum WorkspaceDropZone: Equatable, Sendable {
    case center
    case left
    case right
    case top
    case bottom

    var orientation: SplitOrientation? {
        switch self {
        case .left, .right:
            return .horizontal
        case .top, .bottom:
            return .vertical
        case .center:
            return nil
        }
    }

    var insertFirst: Bool {
        switch self {
        case .left, .top:
            return true
        case .center, .right, .bottom:
            return false
        }
    }
}

typealias DropZone = WorkspaceDropZone

private struct PaneDropZoneEnvironmentKey: EnvironmentKey {
    static let defaultValue: DropZone? = nil
}

extension EnvironmentValues {
    var paneDropZone: DropZone? {
        get { self[PaneDropZoneEnvironmentKey.self] }
        set { self[PaneDropZoneEnvironmentKey.self] = newValue }
    }
}

enum NewTabPosition: Sendable {
    case current
    case end
}

struct WorkspaceLayoutConfiguration: Sendable {
    var allowSplits: Bool
    var allowCloseTabs: Bool
    var allowCloseLastPane: Bool
    var allowTabReordering: Bool
    var allowCrossPaneTabMove: Bool
    var autoCloseEmptyPanes: Bool
    var newTabPosition: NewTabPosition
    var appearance: Appearance

    static let `default` = WorkspaceLayoutConfiguration()

    init(
        allowSplits: Bool = true,
        allowCloseTabs: Bool = true,
        allowCloseLastPane: Bool = false,
        allowTabReordering: Bool = true,
        allowCrossPaneTabMove: Bool = true,
        autoCloseEmptyPanes: Bool = true,
        newTabPosition: NewTabPosition = .current,
        appearance: Appearance = .default
    ) {
        self.allowSplits = allowSplits
        self.allowCloseTabs = allowCloseTabs
        self.allowCloseLastPane = allowCloseLastPane
        self.allowTabReordering = allowTabReordering
        self.allowCrossPaneTabMove = allowCrossPaneTabMove
        self.autoCloseEmptyPanes = autoCloseEmptyPanes
        self.newTabPosition = newTabPosition
        self.appearance = appearance
    }

    struct SplitButtonTooltips: Sendable, Equatable {
        var newTerminal: String
        var newBrowser: String
        var splitRight: String
        var splitDown: String

        static let `default` = SplitButtonTooltips()

        init(
            newTerminal: String = String(localized: "workspace.tooltip.newTerminal", defaultValue: "New Terminal"),
            newBrowser: String = String(localized: "workspace.tooltip.newBrowser", defaultValue: "New Browser"),
            splitRight: String = String(localized: "workspace.tooltip.splitRight", defaultValue: "Split Right"),
            splitDown: String = String(localized: "workspace.tooltip.splitDown", defaultValue: "Split Down")
        ) {
            self.newTerminal = newTerminal
            self.newBrowser = newBrowser
            self.splitRight = splitRight
            self.splitDown = splitDown
        }
    }

    struct Appearance: Sendable {
        struct ChromeColors: Sendable {
            var backgroundHex: String?
            var borderHex: String?

            init(backgroundHex: String? = nil, borderHex: String? = nil) {
                self.backgroundHex = backgroundHex
                self.borderHex = borderHex
            }
        }

        var tabBarHeight: CGFloat
        var tabMinWidth: CGFloat
        var tabMaxWidth: CGFloat
        var tabTitleFontSize: CGFloat
        var tabSpacing: CGFloat
        var minimumPaneWidth: CGFloat
        var minimumPaneHeight: CGFloat
        var showSplitButtons: Bool
        var splitButtonsOnHover: Bool
        var tabBarLeadingInset: CGFloat
        var splitButtonTooltips: SplitButtonTooltips
        var animationDuration: Double
        var enableAnimations: Bool
        var chromeColors: ChromeColors

        static let `default` = Appearance()

        init(
            tabBarHeight: CGFloat = 30,
            tabMinWidth: CGFloat = 48,
            tabMaxWidth: CGFloat = 220,
            tabTitleFontSize: CGFloat = 11,
            tabSpacing: CGFloat = 0,
            minimumPaneWidth: CGFloat = 100,
            minimumPaneHeight: CGFloat = 100,
            showSplitButtons: Bool = true,
            splitButtonsOnHover: Bool = false,
            tabBarLeadingInset: CGFloat = 0,
            splitButtonTooltips: SplitButtonTooltips = .default,
            animationDuration: Double = 0.15,
            enableAnimations: Bool = false,
            chromeColors: ChromeColors = .init()
        ) {
            self.tabBarHeight = tabBarHeight
            self.tabMinWidth = tabMinWidth
            self.tabMaxWidth = tabMaxWidth
            self.tabTitleFontSize = tabTitleFontSize
            self.tabSpacing = tabSpacing
            self.minimumPaneWidth = minimumPaneWidth
            self.minimumPaneHeight = minimumPaneHeight
            self.showSplitButtons = showSplitButtons
            self.splitButtonsOnHover = splitButtonsOnHover
            self.tabBarLeadingInset = tabBarLeadingInset
            self.splitButtonTooltips = splitButtonTooltips
            self.animationDuration = animationDuration
            self.enableAnimations = enableAnimations
            self.chromeColors = chromeColors
        }
    }
}

enum WorkspaceLayout {
    struct Tab: Identifiable, Hashable, Codable, Sendable {
        var id: TabID
        var title: String
        var hasCustomTitle: Bool
        var icon: String?
        var iconImageData: Data?
        var kind: PanelType?
        var isDirty: Bool
        var showsNotificationBadge: Bool
        var isLoading: Bool
        var isPinned: Bool

        init(
            id: TabID = TabID(),
            title: String,
            hasCustomTitle: Bool = false,
            icon: String? = nil,
            iconImageData: Data? = nil,
            kind: PanelType? = nil,
            isDirty: Bool = false,
            showsNotificationBadge: Bool = false,
            isLoading: Bool = false,
            isPinned: Bool = false
        ) {
            self.id = id
            self.title = title
            self.hasCustomTitle = hasCustomTitle
            self.icon = icon
            self.iconImageData = iconImageData
            self.kind = kind
            self.isDirty = isDirty
            self.showsNotificationBadge = showsNotificationBadge
            self.isLoading = isLoading
            self.isPinned = isPinned
        }

        static func rendered(
            id: TabID = TabID(),
            title: String,
            hasCustomTitle: Bool = false,
            icon: String? = nil,
            iconImageData: Data? = nil,
            kind: PanelType? = nil,
            isDirty: Bool = false,
            showsNotificationBadge: Bool = false,
            isLoading: Bool = false,
            isPinned: Bool = false
        ) -> Self {
            var tab = Self(id: id, title: title, isPinned: isPinned)
            tab.hasCustomTitle = hasCustomTitle
            tab.icon = icon
            tab.iconImageData = iconImageData
            tab.kind = kind
            tab.isDirty = isDirty
            tab.showsNotificationBadge = showsNotificationBadge
            tab.isLoading = isLoading
            return tab
        }
    }
}

@MainActor
protocol WorkspaceLayoutDelegate: AnyObject {
    func workspaceSplit(shouldCreateTab tabId: TabID, inPane pane: PaneID) -> Bool
    func workspaceSplit(shouldCloseTab tabId: TabID, inPane pane: PaneID) -> Bool
    func workspaceSplit(didCreateTab tabId: TabID, inPane pane: PaneID)
    func workspaceSplit(didCloseTab tabId: TabID, fromPane pane: PaneID)
    func workspaceSplit(didSelectTab tabId: TabID, inPane pane: PaneID)
    func workspaceSplit(didMoveTab tabId: TabID, fromPane source: PaneID, toPane destination: PaneID)
    func workspaceSplit(shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool
    func workspaceSplit(shouldClosePane pane: PaneID) -> Bool
    func workspaceSplit(didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation)
    func workspaceSplit(didClosePane paneId: PaneID)
    func workspaceSplit(didFocusPane pane: PaneID)
    func workspaceSplit(didRequestNewTab kind: PanelType, inPane pane: PaneID)
    func workspaceSplit(didRequestTabContextAction action: TabContextAction, for tabId: TabID, inPane pane: PaneID)
}

struct WorkspaceLayoutRenderContext {
    let notificationStore: TerminalNotificationStore?
    let isWorkspaceVisible: Bool
    let isWorkspaceInputActive: Bool
    let isMinimalMode: Bool
    let appearance: PanelAppearance
    let workspacePortalPriority: Int
    let usesWorkspacePaneOverlay: Bool
    let showSplitButtons: Bool

    func panelVisibleInUI(isSelectedInPane: Bool, isFocused: Bool) -> Bool {
        guard isWorkspaceVisible else { return false }
        return isSelectedInPane || isFocused
    }

    func panelPresentationFacts(
        paneId: PaneID,
        panelId: UUID,
        isSelectedInPane: Bool,
        isFocused: Bool
    ) -> WorkspacePanelPresentationFacts {
        WorkspacePanelPresentationFacts(
            paneId: paneId,
            panelId: panelId,
            isWorkspaceVisible: isWorkspaceVisible,
            isWorkspaceInputActive: isWorkspaceInputActive,
            isSelectedInPane: isSelectedInPane,
            isFocused: isFocused
        )
    }
}

struct WorkspacePanelPresentationFacts: Equatable, Sendable {
    let paneId: PaneID
    let panelId: UUID
    let isWorkspaceVisible: Bool
    let isWorkspaceInputActive: Bool
    let isSelectedInPane: Bool
    let isFocused: Bool

    var isVisibleInUI: Bool {
        guard isWorkspaceVisible else { return false }
        return isSelectedInPane || isFocused
    }

    var wantsFirstResponder: Bool {
        isVisibleInUI && isWorkspaceInputActive && isFocused
    }
}

enum WorkspaceTerminalPresentationOperation: Equatable, Sendable {
    case setVisibleInUI(Bool)
    case setActive(Bool)
    case requestFirstResponderReconcile
}

struct WorkspaceTerminalPresentationState: Equatable, Sendable {
    let isVisibleInUI: Bool
    let isActive: Bool

    var wantsFirstResponder: Bool {
        isVisibleInUI && isActive
    }
}

enum WorkspaceTerminalPresentationTransitionResolver {
    static func operations(
        previous: WorkspaceTerminalPresentationState?,
        next: WorkspaceTerminalPresentationState
    ) -> [WorkspaceTerminalPresentationOperation] {
        var operations: [WorkspaceTerminalPresentationOperation] = []

        if previous?.isVisibleInUI != next.isVisibleInUI {
            operations.append(.setVisibleInUI(next.isVisibleInUI))
        }

        if previous?.isActive != next.isActive {
            operations.append(.setActive(next.isActive))
        }

        if next.wantsFirstResponder && previous?.wantsFirstResponder != true {
            operations.append(.requestFirstResponderReconcile)
        }

        return operations
    }
}

extension WorkspaceLayoutDelegate {
    func workspaceSplit(shouldCreateTab tabId: TabID, inPane pane: PaneID) -> Bool { true }
    func workspaceSplit(shouldCloseTab tabId: TabID, inPane pane: PaneID) -> Bool { true }
    func workspaceSplit(didCreateTab tabId: TabID, inPane pane: PaneID) {}
    func workspaceSplit(didCloseTab tabId: TabID, fromPane pane: PaneID) {}
    func workspaceSplit(didSelectTab tabId: TabID, inPane pane: PaneID) {}
    func workspaceSplit(didMoveTab tabId: TabID, fromPane source: PaneID, toPane destination: PaneID) {}
    func workspaceSplit(shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool { true }
    func workspaceSplit(shouldClosePane pane: PaneID) -> Bool { true }
    func workspaceSplit(didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {}
    func workspaceSplit(didClosePane paneId: PaneID) {}
    func workspaceSplit(didFocusPane pane: PaneID) {}
    func workspaceSplit(didRequestNewTab kind: PanelType, inPane pane: PaneID) {}
    func workspaceSplit(didRequestTabContextAction action: TabContextAction, for tabId: TabID, inPane pane: PaneID) {}
}


extension WorkspaceTabID {
    init(id: UUID) {
        self.rawValue = id
    }

    var id: UUID {
        rawValue
    }
}

extension WorkspaceDropZone {
    var insertsFirst: Bool {
        insertFirst
    }
}

#if DEBUG
enum WorkspaceLayoutDebugCounters {
    private(set) static var arrangedSubviewUnderflowCount: Int = 0

    static func reset() {
        arrangedSubviewUnderflowCount = 0
    }

    static func recordArrangedSubviewUnderflow() {
        arrangedSubviewUnderflowCount += 1
    }
}
#else
enum WorkspaceLayoutDebugCounters {
    static let arrangedSubviewUnderflowCount: Int = 0

    static func reset() {}
    static func recordArrangedSubviewUnderflow() {}
}
#endif

func dlog(_ message: String) {
    NSLog("%@", message)
}

#if DEBUG
func startupLog(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    let logPath = "/tmp/cmux-startup-debug.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: Data(line.utf8))
    }
}
#else
func startupLog(_ message: String) {
    _ = message
}
#endif

#if DEBUG
private let cmuxLatencyLogPath = "/tmp/cmux-key-latency-debug.log"
private let cmuxLatencyLogLock = NSLock()
private var cmuxLatencyLogSequence: UInt64 = 0

func latencyLog(_ name: String, data: [String: String] = [:]) {
    let ts = ISO8601DateFormatter().string(from: Date())
    cmuxLatencyLogLock.lock()
    cmuxLatencyLogSequence &+= 1
    let seq = cmuxLatencyLogSequence
    cmuxLatencyLogLock.unlock()

    let monoMs = Int((ProcessInfo.processInfo.systemUptime * 1000.0).rounded())
    let payload = data
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
    let suffix = payload.isEmpty ? "" : " " + payload
    let line = "[\(ts)] seq=\(seq) mono_ms=\(monoMs) event=\(name)\(suffix)\n"

    cmuxLatencyLogLock.lock()
    defer { cmuxLatencyLogLock.unlock() }
    if let handle = FileHandle(forWritingAtPath: cmuxLatencyLogPath) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: cmuxLatencyLogPath, contents: Data(line.utf8))
    }
}

func isDebugCmdD(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return flags == [.command] && (event.charactersIgnoringModifiers ?? "").lowercased() == "d"
}

func isDebugCtrlD(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return flags == [.control] && (event.charactersIgnoringModifiers ?? "").lowercased() == "d"
}
#else
func latencyLog(_ name: String, data: [String: String] = [:]) {
    _ = name
    _ = data
}

func isDebugCmdD(_ event: NSEvent) -> Bool {
    _ = event
    return false
}

func isDebugCtrlD(_ event: NSEvent) -> Bool {
    _ = event
    return false
}
#endif
import AppKit
import SwiftUI

private struct SafeTooltipModifier: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        content.background {
            SafeTooltipViewRepresentable(text: text)
                .allowsHitTesting(false)
        }
    }
}

private struct SafeTooltipViewRepresentable: NSViewRepresentable {
    let text: String?

    func makeNSView(context: Context) -> SafeTooltipView {
        let view = SafeTooltipView()
        view.updateTooltip(text)
        return view
    }

    func updateNSView(_ nsView: SafeTooltipView, context: Context) {
        nsView.updateTooltip(text)
    }

    static func dismantleNSView(_ nsView: SafeTooltipView, coordinator: ()) {
        nsView.invalidateTooltip()
    }
}

private final class SafeTooltipView: NSView {
    private var tooltipTag: NSView.ToolTipTag?
    private var registeredBounds: NSRect = .zero
    private var registeredText: String?
    private var tooltipText: String?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        refreshTooltipRegistration()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshTooltipRegistration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            invalidateTooltip()
        } else {
            refreshTooltipRegistration()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            invalidateTooltip()
        } else {
            refreshTooltipRegistration()
        }
    }

    func updateTooltip(_ text: String?) {
        let normalized = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        tooltipText = normalized?.isEmpty == false ? normalized : nil
        refreshTooltipRegistration()
    }

    func invalidateTooltip() {
        if let tooltipTag {
            removeToolTip(tooltipTag)
            self.tooltipTag = nil
        }
        registeredBounds = .zero
        registeredText = nil
    }

    private func refreshTooltipRegistration() {
        guard let tooltipText,
              window != nil,
              superview != nil else {
            invalidateTooltip()
            return
        }

        let nextBounds = bounds.standardized.integral
        guard nextBounds.width > 0, nextBounds.height > 0 else {
            invalidateTooltip()
            return
        }

        if tooltipTag != nil,
           nextBounds == registeredBounds,
           tooltipText == registeredText {
            return
        }

        invalidateTooltip()
        tooltipTag = addToolTip(nextBounds, owner: self, userData: nil)
        registeredBounds = nextBounds
        registeredText = tooltipText
    }

    @objc
    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        tooltipText ?? ""
    }

    deinit {
        invalidateTooltip()
    }
}

extension View {
    /// Uses an AppKit-backed tooltip host that explicitly unregisters its tooltip
    /// before the view is detached or deallocated.
    func safeHelp(_ text: String?) -> some View {
        modifier(SafeTooltipModifier(text: text))
    }
}

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Custom UTTypes for tab drag and drop
extension UTType {
    static var tabItem: UTType {
        UTType(exportedAs: "com.splittabbar.tabitem")
    }

    static var tabTransfer: UTType {
        UTType(exportedAs: "com.splittabbar.tabtransfer", conformingTo: .data)
    }
}

/// Transfer data that includes source pane information for cross-pane moves
struct TabTransferData: Codable, Transferable {
    private struct LegacyTabInfo: Codable {
        let id: UUID
    }

    let tabId: TabID
    let sourcePaneId: UUID
    let sourceProcessId: Int32

    init(tabId: TabID, sourcePaneId: UUID, sourceProcessId: Int32 = Int32(ProcessInfo.processInfo.processIdentifier)) {
        self.tabId = tabId
        self.sourcePaneId = sourcePaneId
        self.sourceProcessId = sourceProcessId
    }

    var isFromCurrentProcess: Bool {
        sourceProcessId == Int32(ProcessInfo.processInfo.processIdentifier)
    }

    private enum CodingKeys: String, CodingKey {
        case tabId
        case tab
        case sourcePaneId
        case sourceProcessId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let tabId = try container.decodeIfPresent(TabID.self, forKey: .tabId) {
            self.tabId = tabId
        } else if let legacyTab = try container.decodeIfPresent(LegacyTabInfo.self, forKey: .tab) {
            self.tabId = TabID(id: legacyTab.id)
        } else {
            let legacyTab = try container.decode(WorkspaceLayout.Tab.self, forKey: .tab)
            self.tabId = legacyTab.id
        }
        self.sourcePaneId = try container.decode(UUID.self, forKey: .sourcePaneId)
        // Legacy payloads won't include this field. Treat as foreign process to reject cross-instance drops.
        self.sourceProcessId = try container.decodeIfPresent(Int32.self, forKey: .sourceProcessId) ?? -1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabId, forKey: .tabId)
        // Keep legacy tab.id payload for older in-process drop consumers.
        try container.encode(LegacyTabInfo(id: tabId.id), forKey: .tab)
        try container.encode(sourcePaneId, forKey: .sourcePaneId)
        try container.encode(sourceProcessId, forKey: .sourceProcessId)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabTransfer)
    }
}

import Foundation
import SwiftUI

/// State for a single pane (leaf node in the split tree)
struct PaneState: Identifiable {
    let id: PaneID
    var tabIds: [UUID]
    var selectedTabId: UUID?
    // AppKit tab chrome is driven by snapshots of this pane. Bump explicitly on
    // metadata edits so hosts don't depend on nested array observation quirks.
    var chromeRevision: UInt64 = 0

    init(
        id: PaneID = PaneID(),
        tabIds: [UUID] = [],
        selectedTabId: UUID? = nil
    ) {
        self.id = id
        self.tabIds = tabIds
        self.selectedTabId = selectedTabId ?? tabIds.first
    }

    /// Select a tab by ID
    mutating func selectTab(_ tabId: UUID) {
        guard tabIds.contains(tabId) else { return }
        guard selectedTabId != tabId else { return }
        selectedTabId = tabId
        chromeRevision &+= 1
    }

    /// Add a new tab
    mutating func addTab(_ tabId: UUID, select: Bool = true) {
        tabIds.append(tabId)
        if select {
            selectedTabId = tabId
        }
        chromeRevision &+= 1
    }

    /// Insert a tab at a specific index
    mutating func insertTab(_ tabId: UUID, at index: Int, select: Bool = true) {
        let safeIndex = min(max(0, index), tabIds.count)
        tabIds.insert(tabId, at: safeIndex)
        if select {
            selectedTabId = tabId
        }
        chromeRevision &+= 1
    }

    /// Remove a tab and return it
    @discardableResult
    mutating func removeTab(_ tabId: UUID) -> UUID? {
        guard let index = tabIds.firstIndex(of: tabId) else { return nil }
        let removedTabId = tabIds.remove(at: index)

        // If we removed the selected tab, keep the index stable when possible:
        // prefer selecting the tab that moved into the removed tab's slot (the "next" tab),
        // and only fall back to selecting the previous tab when we removed the last tab.
        if selectedTabId == tabId {
            if !tabIds.isEmpty {
                let newIndex = min(index, max(0, tabIds.count - 1))
                selectedTabId = tabIds[newIndex]
            } else {
                selectedTabId = nil
            }
        }

        chromeRevision &+= 1

        return removedTabId
    }

    /// Move a tab within this pane
    mutating func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard tabIds.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabIds.count else { return }

        // Treat dropping "on itself" or "after itself" as a no-op.
        // This avoids remove/insert churn that can cause brief visual artifacts during drag/drop.
        if destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1 {
            return
        }

        let tabId = tabIds.remove(at: sourceIndex)
        let requestedIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        let safeIndex = min(max(0, requestedIndex), tabIds.count)
        tabIds.insert(tabId, at: safeIndex)
        chromeRevision &+= 1
    }
}

extension PaneState: Equatable {
    static func == (lhs: PaneState, rhs: PaneState) -> Bool {
        lhs.id == rhs.id
    }
}

import Foundation

/// Represents a pane with its computed bounds in normalized coordinates (0-1)
struct PaneBounds {
    let paneId: PaneID
    let bounds: CGRect
}

/// Recursive structure representing the split tree
/// - pane: A leaf node containing a single pane with tabs
/// - split: A branch node containing two children with a divider
indirect enum SplitNode: Identifiable, Equatable {
    case pane(PaneState)
    case split(SplitState)

    var id: UUID {
        switch self {
        case .pane(let state):
            return state.id.id
        case .split(let state):
            return state.id
        }
    }

    /// Find a pane by its ID
    func findPane(_ paneId: PaneID) -> PaneState? {
        switch self {
        case .pane(let state):
            return state.id == paneId ? state : nil
        case .split(let state):
            return state.first.findPane(paneId) ?? state.second.findPane(paneId)
        }
    }

    /// Mutate a pane in place.
    @discardableResult
    mutating func updatePane(_ paneId: PaneID, _ update: (inout PaneState) -> Void) -> Bool {
        switch self {
        case .pane(var state):
            guard state.id == paneId else { return false }
            update(&state)
            self = .pane(state)
            return true
        case .split(var state):
            if state.first.updatePane(paneId, update) {
                self = .split(state)
                return true
            }
            if state.second.updatePane(paneId, update) {
                self = .split(state)
                return true
            }
            return false
        }
    }

    /// Find the leaf node for a pane by ID.
    func findNode(containing paneId: PaneID) -> SplitNode? {
        switch self {
        case .pane(let state):
            return state.id == paneId ? self : nil
        case .split(let state):
            return state.first.findNode(containing: paneId) ?? state.second.findNode(containing: paneId)
        }
    }

    /// Find a split by its ID.
    func findSplit(_ splitId: UUID) -> SplitState? {
        switch self {
        case .pane:
            return nil
        case .split(let state):
            if state.id == splitId {
                return state
            }
            return state.first.findSplit(splitId) ?? state.second.findSplit(splitId)
        }
    }

    /// Mutate a split in place.
    @discardableResult
    mutating func updateSplit(_ splitId: UUID, _ update: (inout SplitState) -> Void) -> Bool {
        switch self {
        case .pane:
            return false
        case .split(var state):
            if state.id == splitId {
                update(&state)
                self = .split(state)
                return true
            }
            if state.first.updateSplit(splitId, update) {
                self = .split(state)
                return true
            }
            if state.second.updateSplit(splitId, update) {
                self = .split(state)
                return true
            }
            return false
        }
    }

    /// Get all pane IDs in the tree
    var allPaneIds: [PaneID] {
        switch self {
        case .pane(let state):
            return [state.id]
        case .split(let state):
            return state.first.allPaneIds + state.second.allPaneIds
        }
    }

    /// Get all panes in the tree
    var allPanes: [PaneState] {
        switch self {
        case .pane(let state):
            return [state]
        case .split(let state):
            return state.first.allPanes + state.second.allPanes
        }
    }

    /// Find a tab by ID.
    func findTab(_ tabId: TabID) -> (paneId: PaneID, tabIndex: Int)? {
        switch self {
        case .pane(let state):
            guard let tabIndex = state.tabIds.firstIndex(of: tabId.id) else { return nil }
            return (state.id, tabIndex)
        case .split(let state):
            return state.first.findTab(tabId) ?? state.second.findTab(tabId)
        }
    }

    /// Discriminator for detecting structural changes in the tree
    enum NodeType: Equatable {
        case pane
        case split
    }

    var nodeType: NodeType {
        switch self {
        case .pane: return .pane
        case .split: return .split
        }
    }

    static func == (lhs: SplitNode, rhs: SplitNode) -> Bool {
        lhs.id == rhs.id
    }

    /// Compute normalized bounds (0-1) for all panes in the tree
    /// - Parameter availableRect: The rect available for this subtree (starts as unit rect)
    /// - Returns: Array of pane IDs with their computed bounds
    func computePaneBounds(in availableRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [PaneBounds] {
        switch self {
        case .pane(let paneState):
            return [PaneBounds(paneId: paneState.id, bounds: availableRect)]

        case .split(let splitState):
            let dividerPos = splitState.dividerPosition
            let firstRect: CGRect
            let secondRect: CGRect

            switch splitState.orientation {
            case .horizontal:  // Side-by-side: first=LEFT, second=RIGHT
                firstRect = CGRect(x: availableRect.minX, y: availableRect.minY,
                                   width: availableRect.width * dividerPos, height: availableRect.height)
                secondRect = CGRect(x: availableRect.minX + availableRect.width * dividerPos, y: availableRect.minY,
                                    width: availableRect.width * (1 - dividerPos), height: availableRect.height)
            case .vertical:  // Stacked: first=TOP, second=BOTTOM
                firstRect = CGRect(x: availableRect.minX, y: availableRect.minY,
                                   width: availableRect.width, height: availableRect.height * dividerPos)
                secondRect = CGRect(x: availableRect.minX, y: availableRect.minY + availableRect.height * dividerPos,
                                    width: availableRect.width, height: availableRect.height * (1 - dividerPos))
            }

            return splitState.first.computePaneBounds(in: firstRect)
                 + splitState.second.computePaneBounds(in: secondRect)
        }
    }
}

import Foundation
import SwiftUI

/// Direction from which a new split animates in
enum SplitAnimationOrigin: Equatable, Sendable {
    case fromFirst   // New pane slides in from start (left/top)
    case fromSecond  // New pane slides in from end (right/bottom)
}

/// State for a split node (branch in the split tree)
struct SplitState: Identifiable {
    let id: UUID
    var orientation: SplitOrientation
    var first: SplitNode
    var second: SplitNode
    var dividerPosition: CGFloat  // 0.0 to 1.0

    /// Animation origin for entry animation (nil = no animation needed)
    var animationOrigin: SplitAnimationOrigin?

    init(
        id: UUID = UUID(),
        orientation: SplitOrientation,
        first: SplitNode,
        second: SplitNode,
        dividerPosition: CGFloat = 0.5,
        animationOrigin: SplitAnimationOrigin? = nil
    ) {
        self.id = id
        self.orientation = orientation
        self.first = first
        self.second = second
        self.dividerPosition = dividerPosition
        self.animationOrigin = animationOrigin
    }
}

extension SplitState: Equatable {
    static func == (lhs: SplitState, rhs: SplitState) -> Bool {
        lhs.id == rhs.id
    }
}

import Foundation

/// Sizing and spacing constants for the tab bar (following macOS HIG)
enum TabBarMetrics {
    // MARK: - Tab Bar

    static let barHeight: CGFloat = 30
    static let barPadding: CGFloat = 0

    // MARK: - Individual Tabs

    static let tabHeight: CGFloat = 30
    static let tabMinWidth: CGFloat = 48
    static let tabMaxWidth: CGFloat = 220
    static let tabCornerRadius: CGFloat = 0
    static let tabHorizontalPadding: CGFloat = 6
    static let tabSpacing: CGFloat = 0
    static let activeIndicatorHeight: CGFloat = 1.5

    // MARK: - Tab Content

    static let iconSize: CGFloat = 14
    static let titleFontSize: CGFloat = 11
    static let closeButtonSize: CGFloat = 16
    static let closeIconSize: CGFloat = 9
    static let dirtyIndicatorSize: CGFloat = 8
    static let notificationBadgeSize: CGFloat = 6
    static let contentSpacing: CGFloat = 6

    // MARK: - Drop Indicator

    static let dropIndicatorWidth: CGFloat = 2
    static let dropIndicatorHeight: CGFloat = 20

    // MARK: - Split View

    static let minimumPaneWidth: CGFloat = 100
    static let minimumPaneHeight: CGFloat = 100
    static let dividerThickness: CGFloat = 1

    // MARK: - Animations

    static let selectionDuration: Double = 0.15
    static let closeDuration: Double = 0.2
    static let reorderDuration: Double = 0.3
    static let reorderBounce: Double = 0.15
    static let hoverDuration: Double = 0.1

    // MARK: - Split Animations (120fps via CADisplayLink)

    /// Duration for split entry animation (fast and snappy like Hyprland)
    static let splitAnimationDuration: Double = 0.15
}

import SwiftUI
import AppKit

/// Native macOS colors for the tab bar
enum TabBarColors {
    private enum Constants {
        static let darkTextAlpha: CGFloat = 0.82
        static let darkSecondaryTextAlpha: CGFloat = 0.62
        static let darkTertiaryTextAlpha: CGFloat = 0.35
        static let lightTextAlpha: CGFloat = 0.82
        static let lightSecondaryTextAlpha: CGFloat = 0.68
        static let lightTertiaryTextAlpha: CGFloat = 0.35
    }

    private static func chromeBackgroundColor(
        for appearance: WorkspaceLayoutConfiguration.Appearance
    ) -> NSColor? {
        guard let value = appearance.chromeColors.backgroundHex else { return nil }
        return NSColor(workspaceSplitHex: value)
    }

    private static func chromeBorderColor(
        for appearance: WorkspaceLayoutConfiguration.Appearance
    ) -> NSColor? {
        guard let value = appearance.chromeColors.borderHex else { return nil }
        return NSColor(workspaceSplitHex: value)
    }

    private static func effectiveBackgroundColor(
        for appearance: WorkspaceLayoutConfiguration.Appearance,
        fallback fallbackColor: NSColor
    ) -> NSColor {
        chromeBackgroundColor(for: appearance) ?? fallbackColor
    }

    private static func effectiveTextColor(
        for appearance: WorkspaceLayoutConfiguration.Appearance,
        secondary: Bool
    ) -> NSColor {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return secondary ? .secondaryLabelColor : .labelColor
        }

        if custom.isWorkspaceLayoutLightColor {
            let alpha = secondary ? Constants.darkSecondaryTextAlpha : Constants.darkTextAlpha
            return NSColor.black.withAlphaComponent(alpha)
        }

        let alpha = secondary ? Constants.lightSecondaryTextAlpha : Constants.lightTextAlpha
        return NSColor.white.withAlphaComponent(alpha)
    }

    private static func effectiveInactiveSelectedIndicatorColor(
        for appearance: WorkspaceLayoutConfiguration.Appearance
    ) -> NSColor {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return .tertiaryLabelColor
        }

        if custom.isWorkspaceLayoutLightColor {
            return NSColor.black.withAlphaComponent(Constants.darkTertiaryTextAlpha)
        }

        return NSColor.white.withAlphaComponent(Constants.lightTertiaryTextAlpha)
    }

    static func paneBackground(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveBackgroundColor(for: appearance, fallback: .textBackgroundColor))
    }

    static func nsColorPaneBackground(for appearance: WorkspaceLayoutConfiguration.Appearance) -> NSColor {
        effectiveBackgroundColor(for: appearance, fallback: .textBackgroundColor)
    }

    // MARK: - Tab Bar Background

    static var barBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func barBackground(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveBackgroundColor(for: appearance, fallback: .windowBackgroundColor))
    }

    static var barMaterial: Material {
        .bar
    }

    // MARK: - Tab States

    static var activeTabBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func activeTabBackground(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return activeTabBackground
        }
        let adjusted = custom.isWorkspaceLayoutLightColor
            ? custom.workspaceSplitDarken(by: 0.065)
            : custom.workspaceSplitLighten(by: 0.12)
        return Color(nsColor: adjusted)
    }

    static var hoveredTabBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    static func hoveredTabBackground(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return hoveredTabBackground
        }
        let adjusted = custom.isWorkspaceLayoutLightColor
            ? custom.workspaceSplitDarken(by: 0.03)
            : custom.workspaceSplitLighten(by: 0.07)
        return Color(nsColor: adjusted.withAlphaComponent(0.78))
    }

    static var inactiveTabBackground: Color {
        .clear
    }

    // MARK: - Text Colors

    static var activeText: Color {
        Color(nsColor: .labelColor)
    }

    static func activeText(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveTextColor(for: appearance, secondary: false))
    }

    static func nsColorActiveText(for appearance: WorkspaceLayoutConfiguration.Appearance) -> NSColor {
        effectiveTextColor(for: appearance, secondary: false)
    }

    static var inactiveText: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    static func inactiveText(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveTextColor(for: appearance, secondary: true))
    }

    static func nsColorInactiveText(for appearance: WorkspaceLayoutConfiguration.Appearance) -> NSColor {
        effectiveTextColor(for: appearance, secondary: true)
    }

    static func splitActionIcon(for appearance: WorkspaceLayoutConfiguration.Appearance, isPressed: Bool) -> Color {
        Color(nsColor: nsColorSplitActionIcon(for: appearance, isPressed: isPressed))
    }

    static func nsColorSplitActionIcon(
        for appearance: WorkspaceLayoutConfiguration.Appearance,
        isPressed: Bool
    ) -> NSColor {
        isPressed ? nsColorActiveText(for: appearance) : nsColorInactiveText(for: appearance)
    }

    // MARK: - Borders & Indicators

    static var separator: Color {
        Color(nsColor: .separatorColor)
    }

    static func separator(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        Color(nsColor: nsColorSeparator(for: appearance))
    }

    static func nsColorSeparator(for appearance: WorkspaceLayoutConfiguration.Appearance) -> NSColor {
        if let explicit = chromeBorderColor(for: appearance) {
            return explicit
        }

        guard let custom = chromeBackgroundColor(for: appearance) else {
            return .separatorColor
        }
        let alpha: CGFloat = custom.isWorkspaceLayoutLightColor ? 0.26 : 0.36
        let tone = custom.isWorkspaceLayoutLightColor
            ? custom.workspaceSplitDarken(by: 0.12)
            : custom.workspaceSplitLighten(by: 0.16)
        return tone.withAlphaComponent(alpha)
    }

    static func selectedIndicator(
        for appearance: WorkspaceLayoutConfiguration.Appearance,
        focused: Bool
    ) -> Color {
        Color(nsColor: nsColorSelectedIndicator(for: appearance, focused: focused))
    }

    static func nsColorSelectedIndicator(
        for appearance: WorkspaceLayoutConfiguration.Appearance,
        focused: Bool
    ) -> NSColor {
        if focused {
            return .controlAccentColor
        }

        return effectiveInactiveSelectedIndicatorColor(for: appearance)
    }

    static var dropIndicator: Color {
        Color.accentColor
    }

    static func dropIndicator(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        _ = appearance
        return dropIndicator
    }

    static var focusRing: Color {
        Color.accentColor.opacity(0.5)
    }

    static var dirtyIndicator: Color {
        Color(nsColor: .labelColor).opacity(0.6)
    }

    static func dirtyIndicator(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        guard chromeBackgroundColor(for: appearance) != nil else { return dirtyIndicator }
        return activeText(for: appearance).opacity(0.72)
    }

    static var notificationBadge: Color {
        Color(nsColor: .systemBlue)
    }

    static func notificationBadge(for appearance: WorkspaceLayoutConfiguration.Appearance) -> Color {
        _ = appearance
        return notificationBadge
    }

    // MARK: - Shadows

    static var tabShadow: Color {
        Color.black.opacity(0.08)
    }
}

private extension NSColor {
    private static let workspaceSplitHexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    convenience init?(workspaceSplitHex value: String) {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 || hex.count == 8 else { return nil }
        guard hex.unicodeScalars.allSatisfy({ Self.workspaceSplitHexDigits.contains($0) }) else { return nil }
        guard let rgba = UInt64(hex, radix: 16) else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if hex.count == 8 {
            red = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
            green = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
            blue = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
            alpha = CGFloat(rgba & 0x000000FF) / 255.0
        } else {
            red = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
            green = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
            blue = CGFloat(rgba & 0x0000FF) / 255.0
            alpha = 1.0
        }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    var isWorkspaceLayoutLightColor: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.5
    }

    func workspaceSplitLighten(by amount: CGFloat) -> NSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return NSColor(
            red: min(1.0, red + amount),
            green: min(1.0, green + amount),
            blue: min(1.0, blue + amount),
            alpha: alpha
        )
    }

    func workspaceSplitDarken(by amount: CGFloat) -> NSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return NSColor(
            red: max(0.0, red - amount),
            green: max(0.0, green - amount),
            blue: max(0.0, blue - amount),
            alpha: alpha
        )
    }
}

import Foundation
import AppKit
import QuartzCore
import CoreVideo

/// Animates split view divider positions with display-synced updates and pixel-perfect positioning
@MainActor
final class SplitAnimator {

    // MARK: - Types

    private struct Animation {
        weak var splitView: NSSplitView?
        let startPosition: CGFloat
        let endPosition: CGFloat
        let startTime: CFTimeInterval
        let duration: CFTimeInterval
        var onComplete: (() -> Void)?
    }

    // MARK: - Properties

    private var displayLink: CVDisplayLink?
    private var animations: [UUID: Animation] = [:]

    /// Shared animator instance
    static let shared = SplitAnimator()

    /// Default animation duration in seconds
    nonisolated static let defaultAnimationDuration: CFTimeInterval = 0.16
    // MARK: - Initialization

    private init() {
        setupDisplayLink()
    }

    deinit {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
    }

    // MARK: - Display Link

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
            let animator = Unmanaged<SplitAnimator>.fromOpaque(context!).takeUnretainedValue()
            DispatchQueue.main.async {
                Task { @MainActor in
                    animator.tick()
                }
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        displayLink = link
    }

    // MARK: - Animation Control

    @discardableResult
    func animate(
        splitView: NSSplitView,
        from startPosition: CGFloat,
        to endPosition: CGFloat,
        duration: CFTimeInterval = SplitAnimator.defaultAnimationDuration,
        onComplete: (() -> Void)? = nil
    ) -> UUID {
        let id = UUID()

        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(round(startPosition), ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()

        animations[id] = Animation(
            splitView: splitView,
            startPosition: startPosition,
            endPosition: endPosition,
            startTime: CACurrentMediaTime(),
            duration: duration,
            onComplete: onComplete
        )

        if let displayLink, !CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStart(displayLink)
        }

        return id
    }

    func cancel(_ id: UUID) {
        animations.removeValue(forKey: id)
        stopIfNeeded()
    }

    // MARK: - Frame Update

    private func tick() {
        let currentTime = CACurrentMediaTime()
        var completedIds: [UUID] = []

        for (id, animation) in animations {
            guard let splitView = animation.splitView else {
                completedIds.append(id)
                continue
            }

            let elapsed = currentTime - animation.startTime
            let progress = min(elapsed / animation.duration, 1.0)
            let eased = progress == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * progress)

            let position = animation.startPosition + (animation.endPosition - animation.startPosition) * eased

            // Round to whole pixels to prevent artifacts
            splitView.setPosition(round(position), ofDividerAt: 0)

            if progress >= 1.0 {
                completedIds.append(id)
                animation.onComplete?()
            }
        }

        for id in completedIds {
            animations.removeValue(forKey: id)
        }

        stopIfNeeded()
    }

    private func stopIfNeeded() {
        if animations.isEmpty, let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
    }
}

struct TabContextMenuState {
    let isPinned: Bool
    let isUnread: Bool
    let isBrowser: Bool
    let isTerminal: Bool
    let hasCustomTitle: Bool
    let canCloseToLeft: Bool
    let canCloseToRight: Bool
    let canCloseOthers: Bool
    let canMoveToLeftPane: Bool
    let canMoveToRightPane: Bool
    let isZoomed: Bool
    let hasSplits: Bool
    let shortcuts: [TabContextAction: KeyboardShortcut]

    var canMarkAsUnread: Bool {
        !isUnread
    }

    var canMarkAsRead: Bool {
        isUnread
    }
}

struct WorkspacePaneActionEligibilityFacts {
    let paneId: PaneID
    let tabs: [WorkspaceLayout.Tab]
    let canMoveToLeftPane: Bool
    let canMoveToRightPane: Bool
    let isZoomed: Bool
    let hasSplits: Bool
    let shortcuts: [TabContextAction: KeyboardShortcut]

    private let canCloseToLeftByIndex: [Bool]
    private let canCloseToRightByIndex: [Bool]
    private let canCloseOthersByIndex: [Bool]

    init(
        paneId: PaneID,
        tabs: [WorkspaceLayout.Tab],
        canMoveToLeftPane: Bool,
        canMoveToRightPane: Bool,
        isZoomed: Bool,
        hasSplits: Bool,
        shortcuts: [TabContextAction: KeyboardShortcut]
    ) {
        self.paneId = paneId
        self.tabs = tabs
        self.canMoveToLeftPane = canMoveToLeftPane
        self.canMoveToRightPane = canMoveToRightPane
        self.isZoomed = isZoomed
        self.hasSplits = hasSplits
        self.shortcuts = shortcuts

        var prefixUnpinned = Array(repeating: 0, count: tabs.count + 1)
        for index in tabs.indices {
            let unpinnedDelta = tabs[index].isPinned ? 0 : 1
            prefixUnpinned[index + 1] = prefixUnpinned[index] + unpinnedDelta
        }
        let totalUnpinned = prefixUnpinned[tabs.count]

        var canCloseLeft: [Bool] = []
        var canCloseRight: [Bool] = []
        var canCloseOthers: [Bool] = []
        canCloseLeft.reserveCapacity(tabs.count)
        canCloseRight.reserveCapacity(tabs.count)
        canCloseOthers.reserveCapacity(tabs.count)

        for index in tabs.indices {
            let leftUnpinned = prefixUnpinned[index]
            let rightUnpinned = totalUnpinned - prefixUnpinned[index + 1]
            let selfUnpinned = tabs[index].isPinned ? 0 : 1
            let otherUnpinned = totalUnpinned - selfUnpinned

            canCloseLeft.append(leftUnpinned > 0)
            canCloseRight.append(rightUnpinned > 0)
            canCloseOthers.append(otherUnpinned > 0)
        }

        canCloseToLeftByIndex = canCloseLeft
        canCloseToRightByIndex = canCloseRight
        canCloseOthersByIndex = canCloseOthers
    }

    func contextMenuState(for tab: WorkspaceLayout.Tab, at index: Int) -> TabContextMenuState {
        let canCloseToLeft = canCloseToLeftByIndex.indices.contains(index) ? canCloseToLeftByIndex[index] : false
        let canCloseToRight = canCloseToRightByIndex.indices.contains(index) ? canCloseToRightByIndex[index] : false
        let canCloseOthers = canCloseOthersByIndex.indices.contains(index) ? canCloseOthersByIndex[index] : false

        return TabContextMenuState(
            isPinned: tab.isPinned,
            isUnread: tab.showsNotificationBadge,
            isBrowser: tab.kind == .browser,
            isTerminal: tab.kind == .terminal,
            hasCustomTitle: tab.hasCustomTitle,
            canCloseToLeft: canCloseToLeft,
            canCloseToRight: canCloseToRight,
            canCloseOthers: canCloseOthers,
            canMoveToLeftPane: canMoveToLeftPane,
            canMoveToRightPane: canMoveToRightPane,
            isZoomed: isZoomed,
            hasSplits: hasSplits,
            shortcuts: shortcuts
        )
    }
}

@MainActor
struct WorkspaceLayoutExternalTabDropRequest {
    enum Destination {
        case insert(targetPane: PaneID, targetIndex: Int?)
        case split(targetPane: PaneID, orientation: SplitOrientation, insertFirst: Bool)
    }

    let tabId: TabID
    let sourcePaneId: PaneID
    let destination: Destination
}

@MainActor
final class WorkspaceLayoutController {

    // MARK: - Delegate

    /// Delegate for receiving callbacks about tab bar events
    weak var delegate: WorkspaceLayoutDelegate?

    // MARK: - Configuration

    /// Configuration for behavior and appearance
    var configuration: WorkspaceLayoutConfiguration

    // MARK: - Layout State

    /// The root node of the split tree.
    var rootNode: SplitNode

    /// Currently zoomed pane. When set, rendering should only show this pane.
    var zoomedPaneId: PaneID?

    /// Currently focused pane ID.
    var focusedPaneId: PaneID?

    /// Tab currently being dragged (for visual feedback and hit-testing).
    var draggingTabId: TabID?

    /// Monotonic counter incremented on each drag start.
    var dragGeneration: Int = 0

    /// Source pane of the dragging tab.
    var dragSourcePaneId: PaneID?

    /// Non-observable drag session state used by drop delegates.
    var activeDragTabId: TabID?
    var activeDragSourcePaneId: PaneID?

    /// Current frame of the entire split view container.
    var containerFrame: CGRect = .zero

    /// Flag to prevent notification loops during external updates.
    var isExternalUpdateInProgress: Bool = false

    /// Workspace-owned sink for published layout geometry snapshots.
    var onGeometryChanged: ((LayoutSnapshot) -> Void)?

    // MARK: - Initialization

    /// Create a new controller with the specified configuration
    init(
        configuration: WorkspaceLayoutConfiguration = .default,
        rootNode: SplitNode? = nil
    ) {
        self.configuration = configuration
        if let rootNode {
            self.rootNode = rootNode
        } else {
            let initialPane = PaneState()
            self.rootNode = .pane(initialPane)
            self.focusedPaneId = initialPane.id
        }
    }

    // MARK: - Renderer-facing state

    var renderRootNode: SplitNode {
        zoomedNode ?? rootNode
    }

    var isHandlingLocalTabDrag: Bool {
        currentDragTabId != nil
    }

    var currentDragTabId: TabID? {
        activeDragTabId ?? draggingTabId
    }

    var currentDragSourcePaneId: PaneID? {
        activeDragSourcePaneId ?? dragSourcePaneId
    }

    func beginTabDrag(tabId: TabID, sourcePaneId: PaneID) {
        dragGeneration += 1
        draggingTabId = tabId
        dragSourcePaneId = sourcePaneId
        activeDragTabId = tabId
        activeDragSourcePaneId = sourcePaneId
    }

    func clearDragState() {
        draggingTabId = nil
        dragSourcePaneId = nil
        activeDragTabId = nil
        activeDragSourcePaneId = nil
    }

    // MARK: - WorkspaceLayout.Tab Operations

    /// Create a new tab in the focused pane (or specified pane)
    /// - Parameters:
    ///   - id: Optional stable surface ID to use for the tab
    ///   - title: The tab title
    ///   - isPinned: Whether the tab should be treated as pinned
    ///   - pane: Optional pane to add the tab to (defaults to focused pane)
    /// - Returns: The TabID of the created tab, or nil if creation was vetoed by delegate
    @discardableResult
    func createTab(
        id: TabID? = nil,
        title: String,
        isPinned: Bool = false,
        inPane pane: PaneID? = nil,
        select: Bool = true
    ) -> TabID? {
        let tabId = id ?? TabID()
        guard let targetPane = pane ?? focusedPaneId ?? rootNode.allPaneIds.first.map({ PaneID(id: $0.id) }) else {
            return nil
        }
        guard rootNode.findPane(PaneID(id: targetPane.id)) != nil else {
            return nil
        }

        // Check with delegate
        if delegate?.workspaceSplit(shouldCreateTab: tabId, inPane: targetPane) == false {
            return nil
        }

        // Calculate insertion index based on configuration
        let insertIndex: Int?
        switch configuration.newTabPosition {
        case .current:
            // Insert after the currently selected tab
            if let paneState = rootNode.findPane(PaneID(id: targetPane.id)),
               let selectedTabId = paneState.selectedTabId,
               let currentIndex = paneState.tabIds.firstIndex(of: selectedTabId) {
                insertIndex = currentIndex + 1
            } else {
                // No selected tab, append to end
                insertIndex = nil
            }
        case .end:
            insertIndex = nil
        }

        addTabInternal(
            tabId.id,
            toPane: PaneID(id: targetPane.id),
            atIndex: insertIndex,
            select: select
        )

        // Notify delegate
        delegate?.workspaceSplit(didCreateTab: tabId, inPane: targetPane)

        return tabId
    }

    /// Request the delegate to create a new tab of the given kind in a pane.
    /// The delegate is responsible for the actual creation logic.
    func requestNewTab(kind: PanelType, inPane pane: PaneID) {
        delegate?.workspaceSplit(didRequestNewTab: kind, inPane: pane)
    }

    /// Request the delegate to handle a tab context-menu action.
    func requestTabContextAction(_ action: TabContextAction, for tabId: TabID, inPane pane: PaneID) {
        guard findTabInternal(tabId) != nil else { return }
        delegate?.workspaceSplit(didRequestTabContextAction: action, for: tabId, inPane: pane)
    }

    /// Update an existing tab's layout-affecting metadata
    /// - Parameters:
    ///   - tabId: The tab to update
    ///   - title: New fallback title (pass nil to keep current)
    ///   - isPinned: New pinned state (pass nil to keep current)
    func updateTab(
        _ tabId: TabID,
        title: String? = nil,
        isPinned: Bool? = nil
    ) {
        guard let (paneId, _) = findTabInternal(tabId) else { return }
        guard title != nil || isPinned != nil else { return }
        rootNode.updatePane(paneId) { pane in
            pane.chromeRevision &+= 1
        }
    }

    /// Close a tab by ID
    /// - Parameter tabId: The tab to close
    /// - Returns: true if the tab was closed, false if vetoed by delegate
    @discardableResult
    func closeTab(_ tabId: TabID) -> Bool {
        guard let (paneId, tabIndex) = findTabInternal(tabId),
              let pane = rootNode.findPane(paneId) else { return false }
        return closeTab(tabId, with: tabIndex, inPane: pane.id)
    }
    
    /// Close a tab by ID in a specific pane.
    /// - Parameter tabId: The tab to close
    /// - Parameter paneId: The pane in which to close the tab
    func closeTab(_ tabId: TabID, inPane paneId: PaneID) -> Bool {
        guard let pane = rootNode.findPane(paneId),
              let tabIndex = pane.tabIds.firstIndex(of: tabId.id) else {
            return false
        }

        return closeTab(tabId, with: tabIndex, inPane: pane.id)
    }
    
    /// Internal helper to close a tab given its index in a pane
    /// - Parameter tabId: The tab to close
    /// - Parameter tabIndex: The position of the tab within the pane
    /// - Parameter paneId: The pane in which to close the tab
    private func closeTab(_ tabId: TabID, with tabIndex: Int, inPane paneId: PaneID) -> Bool {
        // Check with delegate
        if delegate?.workspaceSplit(shouldCloseTab: tabId, inPane: paneId) == false {
            return false
        }

        performCloseTab(tabId.id, inPane: paneId)

        // Notify delegate
        delegate?.workspaceSplit(didCloseTab: tabId, fromPane: paneId)
        notifyGeometryChange()

        return true
    }

    /// Select a tab by ID
    /// - Parameter tabId: The tab to select
    func selectTab(_ tabId: TabID) {
        guard let (paneId, _) = findTabInternal(tabId) else { return }

        rootNode.updatePane(paneId) { pane in
            pane.selectTab(tabId.id)
        }
        setFocusedPane(paneId)

        // Notify delegate
        delegate?.workspaceSplit(didSelectTab: tabId, inPane: paneId)
    }

    /// Move a tab to a specific pane (and optional index) inside this controller.
    /// - Parameters:
    ///   - tabId: The tab to move.
    ///   - targetPaneId: Destination pane.
    ///   - index: Optional destination index. When nil, appends at the end.
    /// - Returns: true if moved.
    @discardableResult
    func moveTab(_ tabId: TabID, toPane targetPaneId: PaneID, atIndex index: Int? = nil) -> Bool {
        guard let (sourcePaneId, sourceIndex) = findTabInternal(tabId),
              let sourcePane = rootNode.findPane(sourcePaneId),
              let targetPane = rootNode.findPane(PaneID(id: targetPaneId.id)) else { return false }

        let surfaceId = sourcePane.tabIds[sourceIndex]
        if sourcePaneId == targetPane.id {
            // Reorder within same pane.
            let destinationIndex: Int = {
                if let index { return max(0, min(index, sourcePane.tabIds.count)) }
                return sourcePane.tabIds.count
            }()
            rootNode.updatePane(sourcePaneId) { pane in
                pane.moveTab(from: sourceIndex, to: destinationIndex)
                pane.selectTab(surfaceId)
            }
            setFocusedPane(sourcePaneId)
            delegate?.workspaceSplit(didSelectTab: tabId, inPane: sourcePaneId)
            notifyGeometryChange()
            return true
        }

        performMoveTab(surfaceId, from: sourcePaneId, to: targetPane.id, atIndex: index)
        delegate?.workspaceSplit(didMoveTab: tabId, fromPane: sourcePaneId, toPane: targetPane.id)
        notifyGeometryChange()
        return true
    }

    /// Reorder a tab within its pane.
    /// - Parameters:
    ///   - tabId: The tab to reorder.
    ///   - toIndex: Destination index.
    /// - Returns: true if reordered.
    @discardableResult
    func reorderTab(_ tabId: TabID, toIndex: Int) -> Bool {
        guard let (paneId, sourceIndex) = findTabInternal(tabId),
              let pane = rootNode.findPane(paneId) else { return false }
        let destinationIndex = max(0, min(toIndex, pane.tabIds.count))
        rootNode.updatePane(paneId) { pane in
            pane.moveTab(from: sourceIndex, to: destinationIndex)
            pane.selectTab(tabId.id)
        }
        setFocusedPane(paneId)
        delegate?.workspaceSplit(didSelectTab: tabId, inPane: paneId)
        notifyGeometryChange()
        return true
    }

    /// Move to previous tab in focused pane
    func selectPreviousTab() {
        selectPreviousTabInternal()
        notifyTabSelection()
    }

    /// Move to next tab in focused pane
    func selectNextTab() {
        selectNextTabInternal()
        notifyTabSelection()
    }

    // MARK: - Split Operations

    /// Split the focused pane (or specified pane)
    /// - Parameters:
    ///   - paneId: Optional pane to split (defaults to focused pane)
    ///   - orientation: Direction to split (horizontal = side-by-side, vertical = stacked)
    ///   - tab: Optional tab to add to the new pane
    /// - Returns: The new pane ID, or nil if vetoed by delegate
    @discardableResult
    func splitPane(
        _ paneId: PaneID? = nil,
        orientation: SplitOrientation,
        withTabId tabId: TabID? = nil,
        focusNewPane: Bool = true
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }

        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId,
              rootNode.findPane(targetPaneId) != nil else { return nil }
        let previousPaneIds = Set(rootNode.allPaneIds)

        // Check with delegate
        if delegate?.workspaceSplit(shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        // Perform split
        performSplitPane(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            with: tabId?.id,
            focusNewPane: focusNewPane
        )

        guard let newPaneId = Set(rootNode.allPaneIds)
            .subtracting(previousPaneIds)
            .first else { return nil }

        // Notify delegate
        delegate?.workspaceSplit(didSplitPane: targetPaneId, newPane: newPaneId, orientation: orientation)

        notifyGeometryChange()

        return newPaneId
    }

    /// Split a pane and place a specific tab in the newly created pane, choosing which side to insert on.
    ///
    /// This is like `splitPane(_:orientation:withTab:)`, but allows choosing left/top vs right/bottom insertion
    /// without needing to create then move a tab.
    ///
    /// - Parameters:
    ///   - paneId: Optional pane to split (defaults to focused pane).
    ///   - orientation: Direction to split (horizontal = side-by-side, vertical = stacked).
    ///   - tab: The tab to add to the new pane.
    ///   - insertFirst: If true, insert the new pane first (left/top). Otherwise insert second (right/bottom).
    /// - Returns: The new pane ID, or nil if vetoed by delegate.
    @discardableResult
    func splitPane(
        _ paneId: PaneID? = nil,
        orientation: SplitOrientation,
        withTabId tabId: TabID,
        insertFirst: Bool,
        focusNewPane: Bool = true
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }

        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId,
              rootNode.findPane(targetPaneId) != nil else { return nil }
        let previousPaneIds = Set(rootNode.allPaneIds)

        // Check with delegate
        if delegate?.workspaceSplit(shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        // Perform split with insertion side.
        performSplitPaneWithTab(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            tabId: tabId.id,
            insertFirst: insertFirst,
            focusNewPane: focusNewPane
        )

        guard let newPaneId = Set(rootNode.allPaneIds)
            .subtracting(previousPaneIds)
            .first else { return nil }

        // Notify delegate
        delegate?.workspaceSplit(didSplitPane: targetPaneId, newPane: newPaneId, orientation: orientation)

        notifyGeometryChange()

        return newPaneId
    }

    /// Split a pane by moving an existing tab into the new pane.
    ///
    /// This mirrors the "drag a tab to a pane edge to create a split" interaction:
    /// the tab is removed from its source pane first, then inserted into the newly
    /// created pane on the chosen edge.
    ///
    /// - Parameters:
    ///   - paneId: Optional target pane to split (defaults to the tab's current pane).
    ///   - orientation: Direction to split (horizontal = side-by-side, vertical = stacked).
    ///   - tabId: The existing tab to move into the new pane.
    ///   - insertFirst: If true, the new pane is inserted first (left/top). Otherwise it is inserted second (right/bottom).
    /// - Returns: The new pane ID, or nil if the tab couldn't be found or the split was vetoed.
    @discardableResult
    func splitPane(
        _ paneId: PaneID? = nil,
        orientation: SplitOrientation,
        movingTab tabId: TabID,
        insertFirst: Bool,
        focusNewPane: Bool = true
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }
        let previousPaneIds = Set(rootNode.allPaneIds)

        // Find the existing tab and its source pane.
        guard let (sourcePaneId, tabIndex) = findTabInternal(tabId),
              let sourcePane = rootNode.findPane(sourcePaneId) else { return nil }
        let surfaceId = sourcePane.tabIds[tabIndex]
        let sourceWasSelected = sourcePane.selectedTabId == surfaceId

        // Default target to the tab's current pane to match edge-drop behavior on the source pane.
        let targetPaneId = paneId ?? sourcePaneId
        guard rootNode.findPane(targetPaneId) != nil else { return nil }

        // Check with delegate
        if delegate?.workspaceSplit(shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        // Remove from source first.
        rootNode.updatePane(sourcePaneId) { pane in
            pane.removeTab(surfaceId)
        }

        // Perform split with the moved tab.
        performSplitPaneWithTab(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            tabId: surfaceId,
            insertFirst: insertFirst,
            focusNewPane: focusNewPane
        )

        guard let newPaneId = Set(rootNode.allPaneIds)
            .subtracting(previousPaneIds)
            .first else {
            rootNode.updatePane(sourcePaneId) { pane in
                pane.insertTab(surfaceId, at: tabIndex, select: sourceWasSelected)
            }
            return nil
        }

        let updatedSourcePane = rootNode.findPane(sourcePaneId)
        if updatedSourcePane?.tabIds.isEmpty == true,
           sourcePaneId != targetPaneId,
           rootNode.allPaneIds.count > 1 {
            // If the source pane is now empty, close it after the split succeeds.
            performClosePane(sourcePaneId)
        }

        let desiredFocusPaneId = focusNewPane ? newPaneId : targetPaneId
        if rootNode.findPane(desiredFocusPaneId) != nil {
            focusPane(desiredFocusPaneId)
        }

        // Notify delegate
        delegate?.workspaceSplit(didSplitPane: targetPaneId, newPane: newPaneId, orientation: orientation)

        notifyGeometryChange()

        return newPaneId
    }

    /// Close a specific pane
    /// - Parameter paneId: The pane to close
    /// - Returns: true if the pane was closed, false if vetoed by delegate
    @discardableResult
    func closePane(_ paneId: PaneID) -> Bool {
        let paneId = PaneID(id: paneId.id)
        guard rootNode.findPane(paneId) != nil else {
            return false
        }

        // Don't close if it's the last pane and not allowed
        if !configuration.allowCloseLastPane && rootNode.allPaneIds.count <= 1 {
            return false
        }

        // Check with delegate
        if delegate?.workspaceSplit(shouldClosePane: paneId) == false {
            return false
        }

        performClosePane(paneId)
        guard rootNode.findPane(paneId) == nil else {
            return false
        }

        // Notify delegate
        delegate?.workspaceSplit(didClosePane: paneId)

        notifyGeometryChange()

        return true
    }

    // MARK: - Focus Management

    /// Focus a specific pane
    func focusPane(_ paneId: PaneID) {
        setFocusedPane(PaneID(id: paneId.id))
        delegate?.workspaceSplit(didFocusPane: paneId)
    }

    /// Navigate focus in a direction
    func navigateFocus(direction: NavigationDirection) {
        performNavigateFocus(direction: direction)
        if let focusedPaneId {
            delegate?.workspaceSplit(didFocusPane: focusedPaneId)
        }
    }

    /// Find the closest pane in the requested direction from the given pane.
    func adjacentPane(to paneId: PaneID, direction: NavigationDirection) -> PaneID? {
        adjacentPaneInternal(to: paneId, direction: direction)
    }

    // MARK: - Split Zoom

    var isSplitZoomed: Bool {
        zoomedPaneId != nil
    }

    @discardableResult
    func clearPaneZoom() -> Bool {
        clearPaneZoomInternal()
    }

    /// Toggle zoom for a pane. When zoomed, only that pane is rendered in the split area.
    /// Passing nil toggles the currently focused pane.
    @discardableResult
    func togglePaneZoom(inPane paneId: PaneID? = nil) -> Bool {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId else { return false }
        return togglePaneZoomInternal(targetPaneId)
    }

    // MARK: - Context Menu Shortcut Hints

    /// Keyboard shortcuts to display in tab context menus, keyed by context action.
    /// Set by the host app to sync with its customizable keyboard shortcut settings.
    var contextMenuShortcuts: [TabContextAction: KeyboardShortcut] = [:]

    // MARK: - Query Methods

    /// Get all tab IDs
    var allTabIds: [TabID] {
        rootNode.allPanes.flatMap { pane in
            pane.tabIds.map { TabID(id: $0) }
        }
    }

    /// Get all pane IDs
    var allPaneIds: [PaneID] {
        rootNode.allPaneIds
    }

    /// Get all tab IDs in a specific pane.
    func tabIds(inPane paneId: PaneID) -> [TabID] {
        guard let pane = rootNode.findPane(PaneID(id: paneId.id)) else {
            return []
        }
        return pane.tabIds.map { TabID(id: $0) }
    }

    /// Get the selected tab ID in a pane.
    func selectedTabId(inPane paneId: PaneID) -> TabID? {
        guard let pane = rootNode.findPane(PaneID(id: paneId.id)),
              let selectedTabId = pane.selectedTabId else {
            return nil
        }
        return TabID(id: selectedTabId)
    }

    // MARK: - Geometry Query API

    /// Get current layout snapshot with pixel coordinates
    func layoutSnapshot() -> LayoutSnapshot {
        let containerFrame = containerFrame
        let paneBounds = rootNode.computePaneBounds()

        let paneGeometries = paneBounds.map { bounds -> PaneGeometry in
            let pane = rootNode.findPane(bounds.paneId)
            let pixelFrame = PixelRect(
                x: Double(bounds.bounds.minX * containerFrame.width + containerFrame.origin.x),
                y: Double(bounds.bounds.minY * containerFrame.height + containerFrame.origin.y),
                width: Double(bounds.bounds.width * containerFrame.width),
                height: Double(bounds.bounds.height * containerFrame.height)
            )
            return PaneGeometry(
                paneId: bounds.paneId.id.uuidString,
                frame: pixelFrame,
                selectedTabId: pane?.selectedTabId?.uuidString,
                tabIds: pane?.tabIds.map { $0.uuidString } ?? []
            )
        }

        return LayoutSnapshot(
            containerFrame: PixelRect(from: containerFrame),
            panes: paneGeometries,
            focusedPaneId: focusedPaneId?.id.uuidString,
            timestamp: Date().timeIntervalSince1970
        )
    }

    /// Check if a split exists by ID
    func findSplit(_ splitId: UUID) -> Bool {
        return splitState(splitId) != nil
    }

    // MARK: - Geometry Update API

    /// Set divider position for a split node (0.0-1.0)
    /// - Parameters:
    ///   - position: The new divider position (clamped to 0.1-0.9)
    ///   - splitId: The UUID of the split to update
    ///   - fromExternal: Set to true to suppress outgoing notifications (prevents loops)
    /// - Returns: true if the split was found and updated
    @discardableResult
    func setDividerPosition(_ position: CGFloat, forSplit splitId: UUID, fromExternal: Bool = false) -> Bool {
        guard splitState(splitId) != nil else { return false }

        if fromExternal {
            isExternalUpdateInProgress = true
        }

        // Clamp position to valid range
        let clampedPosition = min(max(position, 0.1), 0.9)
        rootNode.updateSplit(splitId) { split in
            split.dividerPosition = clampedPosition
        }

        if fromExternal {
            // External restore/config loads should suppress only the immediate geometry echo
            // from the same update turn, not an arbitrary timed window.
            DispatchQueue.main.async { [weak self] in
                self?.isExternalUpdateInProgress = false
            }
        }

        return true
    }

    func consumeSplitEntryAnimation(_ splitId: UUID) {
        guard let split = splitState(splitId),
              split.animationOrigin != nil else { return }
        rootNode.updateSplit(splitId) { split in
            split.animationOrigin = nil
        }
    }

    /// Update container frame (called when window moves/resizes)
    func setContainerFrame(_ frame: CGRect) {
        containerFrame = frame
    }

    /// Notify geometry change to delegate (internal use)
    /// - Parameter isDragging: Whether the change is due to active divider dragging
    internal func notifyGeometryChange(isDragging: Bool = false) {
        guard !isExternalUpdateInProgress, !isDragging else { return }
        onGeometryChanged?(layoutSnapshot())
    }

    // MARK: - Private Helpers

    private var focusedPane: PaneState? {
        guard let focusedPaneId else { return nil }
        return rootNode.findPane(focusedPaneId)
    }

    private var zoomedNode: SplitNode? {
        guard let zoomedPaneId else { return nil }
        return rootNode.findNode(containing: zoomedPaneId)
    }

    private func setFocusedPane(_ paneId: PaneID) {
        guard rootNode.findPane(paneId) != nil else { return }
#if DEBUG
        dlog("focus.WorkspaceLayout pane=\(paneId.id.uuidString.prefix(5))")
#endif
        focusedPaneId = paneId
    }

    @discardableResult
    private func clearPaneZoomInternal() -> Bool {
        guard zoomedPaneId != nil else { return false }
        zoomedPaneId = nil
        return true
    }

    @discardableResult
    private func togglePaneZoomInternal(_ paneId: PaneID) -> Bool {
        guard rootNode.findPane(paneId) != nil else { return false }

        if zoomedPaneId == paneId {
            zoomedPaneId = nil
            return true
        }

        guard rootNode.allPaneIds.count > 1 else { return false }
        zoomedPaneId = paneId
        focusedPaneId = paneId
        return true
    }

    private func performSplitPane(
        _ paneId: PaneID,
        orientation: SplitOrientation,
        with newTabId: UUID? = nil,
        focusNewPane: Bool = true
    ) {
        clearPaneZoomInternal()
        rootNode = splitNodeRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            newTabId: newTabId,
            focusNewPane: focusNewPane
        )
    }

    private func splitNodeRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        newTabId: UUID?,
        focusNewPane: Bool
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                let newPane: PaneState
                if let newTabId {
                    newPane = PaneState(tabIds: [newTabId])
                } else {
                    newPane = PaneState()
                }

                let splitState = SplitState(
                    orientation: orientation,
                    first: .pane(paneState),
                    second: .pane(newPane),
                    dividerPosition: 0.5,
                    animationOrigin: .fromSecond
                )

                if focusNewPane {
                    focusedPaneId = newPane.id
                }

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            var splitState = splitState
            splitState.first = splitNodeRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTabId: newTabId,
                focusNewPane: focusNewPane
            )
            splitState.second = splitNodeRecursively(
                node: splitState.second,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTabId: newTabId,
                focusNewPane: focusNewPane
            )
            return .split(splitState)
        }
    }

    private func performSplitPaneWithTab(
        _ paneId: PaneID,
        orientation: SplitOrientation,
        tabId: UUID,
        insertFirst: Bool,
        focusNewPane: Bool = true
    ) {
        clearPaneZoomInternal()
        rootNode = splitNodeWithTabRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            tabId: tabId,
            insertFirst: insertFirst,
            focusNewPane: focusNewPane
        )
    }

    private func splitNodeWithTabRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        tabId: UUID,
        insertFirst: Bool,
        focusNewPane: Bool
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                let newPane = PaneState(tabIds: [tabId])
                let splitState: SplitState
                if insertFirst {
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(newPane),
                        second: .pane(paneState),
                        dividerPosition: 0.5,
                        animationOrigin: .fromFirst
                    )
                } else {
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(paneState),
                        second: .pane(newPane),
                        dividerPosition: 0.5,
                        animationOrigin: .fromSecond
                    )
                }

                if focusNewPane {
                    focusedPaneId = newPane.id
                }

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            var splitState = splitState
            splitState.first = splitNodeWithTabRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tabId: tabId,
                insertFirst: insertFirst,
                focusNewPane: focusNewPane
            )
            splitState.second = splitNodeWithTabRecursively(
                node: splitState.second,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tabId: tabId,
                insertFirst: insertFirst,
                focusNewPane: focusNewPane
            )
            return .split(splitState)
        }
    }

    private func performClosePane(_ paneId: PaneID) {
        guard rootNode.allPaneIds.count > 1 else { return }

        let (newRoot, siblingPaneId) = closePaneRecursively(node: rootNode, targetPaneId: paneId)

        if let newRoot {
            rootNode = newRoot
        }

        if let siblingPaneId {
            focusedPaneId = siblingPaneId
        } else if let firstPane = rootNode.allPaneIds.first {
            focusedPaneId = firstPane
        }

        if let zoomedPaneId, rootNode.findPane(zoomedPaneId) == nil {
            self.zoomedPaneId = nil
        }
    }

    private func closePaneRecursively(
        node: SplitNode,
        targetPaneId: PaneID
    ) -> (SplitNode?, PaneID?) {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                return (nil, nil)
            }
            return (node, nil)

        case .split(let splitState):
            if case .pane(let firstPane) = splitState.first, firstPane.id == targetPaneId {
                let focusTarget = splitState.second.allPaneIds.first
                return (splitState.second, focusTarget)
            }

            if case .pane(let secondPane) = splitState.second, secondPane.id == targetPaneId {
                let focusTarget = splitState.first.allPaneIds.first
                return (splitState.first, focusTarget)
            }

            let (newFirst, focusFromFirst) = closePaneRecursively(node: splitState.first, targetPaneId: targetPaneId)
            if newFirst == nil {
                return (splitState.second, splitState.second.allPaneIds.first)
            }

            let (newSecond, focusFromSecond) = closePaneRecursively(node: splitState.second, targetPaneId: targetPaneId)
            if newSecond == nil {
                return (splitState.first, splitState.first.allPaneIds.first)
            }

            var updatedSplit = splitState
            if let newFirst { updatedSplit.first = newFirst }
            if let newSecond { updatedSplit.second = newSecond }

            return (.split(updatedSplit), focusFromFirst ?? focusFromSecond)
        }
    }

    private func addTabInternal(
        _ tabId: UUID,
        toPane paneId: PaneID? = nil,
        atIndex index: Int? = nil,
        select: Bool = true
    ) {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId else { return }

        rootNode.updatePane(targetPaneId) { pane in
            if let index {
                pane.insertTab(tabId, at: index, select: select)
            } else {
                pane.addTab(tabId, select: select)
            }
        }
    }

    private func performMoveTab(_ tabId: UUID, from sourcePaneId: PaneID, to targetPaneId: PaneID, atIndex index: Int? = nil) {
        guard rootNode.findPane(sourcePaneId) != nil,
              rootNode.findPane(targetPaneId) != nil else { return }

        rootNode.updatePane(sourcePaneId) { pane in
            pane.removeTab(tabId)
        }

        rootNode.updatePane(targetPaneId) { pane in
            if let index {
                pane.insertTab(tabId, at: index)
            } else {
                pane.addTab(tabId)
            }
        }

        setFocusedPane(targetPaneId)

        if rootNode.findPane(sourcePaneId)?.tabIds.isEmpty == true && rootNode.allPaneIds.count > 1 {
            performClosePane(sourcePaneId)
        }
    }

    private func performCloseTab(_ tabId: UUID, inPane paneId: PaneID) {
        guard rootNode.findPane(paneId) != nil else { return }

        rootNode.updatePane(paneId) { pane in
            pane.removeTab(tabId)
        }

        if rootNode.findPane(paneId)?.tabIds.isEmpty == true && rootNode.allPaneIds.count > 1 {
            performClosePane(paneId)
        }
    }

    private func performNavigateFocus(direction: NavigationDirection) {
        guard let currentPaneId = focusedPaneId else { return }

        let allPaneBounds = rootNode.computePaneBounds()
        guard let currentBounds = allPaneBounds.first(where: { $0.paneId == currentPaneId })?.bounds else { return }

        if let targetPaneId = findBestNeighbor(
            from: currentBounds,
            currentPaneId: currentPaneId,
            direction: direction,
            allPaneBounds: allPaneBounds
        ) {
            setFocusedPane(targetPaneId)
        }
    }

    private func adjacentPaneInternal(to paneId: PaneID, direction: NavigationDirection) -> PaneID? {
        let allPaneBounds = rootNode.computePaneBounds()
        guard let currentBounds = allPaneBounds.first(where: { $0.paneId == paneId })?.bounds else {
            return nil
        }
        return findBestNeighbor(
            from: currentBounds,
            currentPaneId: paneId,
            direction: direction,
            allPaneBounds: allPaneBounds
        )
    }

    private func findBestNeighbor(
        from currentBounds: CGRect,
        currentPaneId: PaneID,
        direction: NavigationDirection,
        allPaneBounds: [PaneBounds]
    ) -> PaneID? {
        let epsilon: CGFloat = 0.001

        let candidates = allPaneBounds.filter { paneBounds in
            guard paneBounds.paneId != currentPaneId else { return false }
            let bounds = paneBounds.bounds
            switch direction {
            case .left: return bounds.maxX <= currentBounds.minX + epsilon
            case .right: return bounds.minX >= currentBounds.maxX - epsilon
            case .up: return bounds.maxY <= currentBounds.minY + epsilon
            case .down: return bounds.minY >= currentBounds.maxY - epsilon
            }
        }

        guard !candidates.isEmpty else { return nil }

        let scored: [(PaneID, CGFloat, CGFloat)] = candidates.map { candidate in
            let overlap: CGFloat
            let distance: CGFloat

            switch direction {
            case .left, .right:
                overlap = max(0, min(currentBounds.maxY, candidate.bounds.maxY) - max(currentBounds.minY, candidate.bounds.minY))
                distance = direction == .left
                    ? (currentBounds.minX - candidate.bounds.maxX)
                    : (candidate.bounds.minX - currentBounds.maxX)
            case .up, .down:
                overlap = max(0, min(currentBounds.maxX, candidate.bounds.maxX) - max(currentBounds.minX, candidate.bounds.minX))
                distance = direction == .up
                    ? (currentBounds.minY - candidate.bounds.maxY)
                    : (candidate.bounds.minY - currentBounds.maxY)
            }

            return (candidate.paneId, overlap, distance)
        }

        return scored.sorted { lhs, rhs in
            if abs(lhs.1 - rhs.1) > epsilon {
                return lhs.1 > rhs.1
            }
            return lhs.2 < rhs.2
        }.first?.0
    }

    private func selectPreviousTabInternal() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabIds.firstIndex(of: selectedTabId),
              !pane.tabIds.isEmpty else { return }

        let newIndex = currentIndex > 0 ? currentIndex - 1 : pane.tabIds.count - 1
        rootNode.updatePane(pane.id) { pane in
            pane.selectTab(pane.tabIds[newIndex])
        }
    }

    private func selectNextTabInternal() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabIds.firstIndex(of: selectedTabId),
              !pane.tabIds.isEmpty else { return }

        let newIndex = currentIndex < pane.tabIds.count - 1 ? currentIndex + 1 : 0
        rootNode.updatePane(pane.id) { pane in
            pane.selectTab(pane.tabIds[newIndex])
        }
    }

    private func splitState(_ splitId: UUID) -> SplitState? {
        rootNode.findSplit(splitId)
    }

    private func findTabInternal(_ tabId: TabID) -> (PaneID, Int)? {
        rootNode.findTab(tabId)
    }

    private func notifyTabSelection() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId else { return }
        delegate?.workspaceSplit(didSelectTab: TabID(id: selectedTabId), inPane: pane.id)
    }
}

@MainActor
struct WorkspaceLayoutInteractionHandlers {
    let notifyGeometryChangeHandler: (Bool) -> Void
    let setContainerFrameHandler: (CGRect) -> Void
    let setDividerPositionHandler: (CGFloat, UUID) -> Bool
    let consumeSplitEntryAnimationHandler: (UUID) -> Void
    let beginTabDragHandler: (TabID, PaneID) -> Void
    let clearDragStateHandler: () -> Void
    let focusPaneHandler: (PaneID) -> Bool
    let selectTabHandler: (TabID) -> Void
    let requestCloseTabHandler: (TabID, PaneID) -> Bool
    let togglePaneZoomHandler: (PaneID) -> Bool
    let requestTabContextActionHandler: (TabContextAction, TabID, PaneID) -> Void
    let requestNewTabHandler: (PanelType, PaneID) -> Void
    let splitPaneHandler: (PaneID?, SplitOrientation) -> PaneID?
    let splitPaneMovingTabHandler: (PaneID?, SplitOrientation, TabID, Bool, Bool) -> PaneID?
    let moveTabHandler: (TabID, PaneID, Int?) -> Bool
    let handleExternalTabDropHandler: (WorkspaceLayoutExternalTabDropRequest) -> Bool
    let handleFileDropHandler: ([URL], PaneID) -> Bool

    func notifyGeometryChange(isDragging: Bool) {
        notifyGeometryChangeHandler(isDragging)
    }

    func setContainerFrame(_ frame: CGRect) {
        setContainerFrameHandler(frame)
    }

    func setDividerPosition(_ position: CGFloat, forSplit splitId: UUID) -> Bool {
        setDividerPositionHandler(position, splitId)
    }

    func consumeSplitEntryAnimation(_ splitId: UUID) {
        consumeSplitEntryAnimationHandler(splitId)
    }

    func beginTabDrag(tabId: TabID, sourcePaneId: PaneID) {
        beginTabDragHandler(tabId, sourcePaneId)
    }

    func clearDragState() {
        clearDragStateHandler()
    }

    func focusPane(_ paneId: PaneID) -> Bool {
        focusPaneHandler(paneId)
    }

    func selectTab(_ tabId: TabID) {
        selectTabHandler(tabId)
    }

    func requestCloseTab(_ tabId: TabID, inPane paneId: PaneID) -> Bool {
        requestCloseTabHandler(tabId, paneId)
    }

    func togglePaneZoom(inPane paneId: PaneID) -> Bool {
        togglePaneZoomHandler(paneId)
    }

    func requestTabContextAction(_ action: TabContextAction, for tabId: TabID, inPane paneId: PaneID) {
        requestTabContextActionHandler(action, tabId, paneId)
    }

    func requestNewTab(kind: PanelType, inPane paneId: PaneID) {
        requestNewTabHandler(kind, paneId)
    }

    func splitPane(_ paneId: PaneID?, orientation: SplitOrientation) -> PaneID? {
        splitPaneHandler(paneId, orientation)
    }

    func splitPane(
        _ paneId: PaneID?,
        orientation: SplitOrientation,
        movingTab tabId: TabID,
        insertFirst: Bool,
        focusNewPane: Bool
    ) -> PaneID? {
        splitPaneMovingTabHandler(paneId, orientation, tabId, insertFirst, focusNewPane)
    }

    func moveTab(_ tabId: TabID, toPane paneId: PaneID, atIndex index: Int?) -> Bool {
        moveTabHandler(tabId, paneId, index)
    }

    func handleExternalTabDrop(_ request: WorkspaceLayoutExternalTabDropRequest) -> Bool {
        handleExternalTabDropHandler(request)
    }

    func handleFileDrop(_ urls: [URL], in paneId: PaneID) -> Bool {
        handleFileDropHandler(urls, paneId)
    }

    static let noop = WorkspaceLayoutInteractionHandlers(
        notifyGeometryChangeHandler: { _ in },
        setContainerFrameHandler: { _ in },
        setDividerPositionHandler: { _, _ in false },
        consumeSplitEntryAnimationHandler: { _ in },
        beginTabDragHandler: { _, _ in },
        clearDragStateHandler: {},
        focusPaneHandler: { _ in false },
        selectTabHandler: { _ in },
        requestCloseTabHandler: { _, _ in false },
        togglePaneZoomHandler: { _ in false },
        requestTabContextActionHandler: { _, _, _ in },
        requestNewTabHandler: { _, _ in },
        splitPaneHandler: { _, _ in nil },
        splitPaneMovingTabHandler: { _, _, _, _, _ in nil },
        moveTabHandler: { _, _, _ in false },
        handleExternalTabDropHandler: { _ in false },
        handleFileDropHandler: { _, _ in false }
    )
}

/// Main entry point for the WorkspaceLayout library.
struct WorkspaceLayoutView: View {
    private let host: WorkspaceLayoutInteractionHandlers
    private let renderSnapshot: WorkspaceLayoutRenderSnapshot
    private let surfaceRegistry: WorkspaceSurfaceRegistry

    /// Initialize with a workspace-owned host boundary and the canonical render snapshot.
    /// - Parameters:
    ///   - host: Workspace-owned AppKit host boundary
    ///   - renderSnapshot: The canonical snapshot resolved by the workspace runtime owner
    ///   - surfaceRegistry: Workspace-owned retained surface registry
    init(
        host: WorkspaceLayoutInteractionHandlers,
        renderSnapshot: WorkspaceLayoutRenderSnapshot,
        surfaceRegistry: WorkspaceSurfaceRegistry
    ) {
        self.host = host
        self.renderSnapshot = renderSnapshot
        self.surfaceRegistry = surfaceRegistry
    }

    var body: some View {
        WorkspaceLayoutNativeHost(
            hostBridge: host,
            renderSnapshot: renderSnapshot,
            surfaceRegistry: surfaceRegistry
        )
    }
}

@MainActor
enum WorkspacePaneContent {
    case terminal(WorkspaceTerminalPaneContent)
    case browser(WorkspaceBrowserPaneContent)
    case markdown(WorkspaceMarkdownPaneContent)
    case placeholder(WorkspacePlaceholderPaneContent)
}

enum WorkspacePaneMountIdentity: Hashable {
    case terminal(UUID)
    case browser(UUID)
    case markdown(UUID)
    case placeholder(UUID)
}

extension WorkspacePaneContent {
    var usesDirectPaneHost: Bool {
        switch self {
        case .terminal, .browser:
            return true
        case .markdown, .placeholder:
            return false
        }
    }

    func mountIdentity(contentId: UUID) -> WorkspacePaneMountIdentity {
        switch self {
        case .terminal(let descriptor):
            return .terminal(descriptor.surfaceId)
        case .browser(let descriptor):
            return .browser(descriptor.surfaceId)
        case .markdown(let descriptor):
            return .markdown(descriptor.surfaceId)
        case .placeholder:
            return .placeholder(contentId)
        }
    }
}

enum WorkspaceSurfaceRevealPhase: Equatable, Sendable {
    case hidden
    case waitingForWindow
    case waitingForGeometry
    case waitingForRuntime
    case waitingForFirstFrame
    case visible

    init(terminalFacts: TerminalViewportLifecycleFacts) {
        if !terminalFacts.isVisibleInUI {
            self = .hidden
        } else if !terminalFacts.isWindowed {
            self = .waitingForWindow
        } else if !terminalFacts.hasUsableGeometry {
            self = .waitingForGeometry
        } else if !terminalFacts.hasRuntime {
            self = .waitingForRuntime
        } else if !terminalFacts.hasPresentedFrame {
            self = .waitingForFirstFrame
        } else {
            self = .visible
        }
    }

    var showsLoadingCover: Bool {
        switch self {
        case .hidden, .visible:
            false
        case .waitingForWindow, .waitingForGeometry, .waitingForRuntime, .waitingForFirstFrame:
            true
        }
    }
}

struct WorkspaceSurfacePresentationFacts: Equatable, Sendable {
    let revealPhase: WorkspaceSurfaceRevealPhase

    var isVisible: Bool {
        revealPhase == .visible
    }

    var showsLoadingCover: Bool {
        revealPhase.showsLoadingCover
    }

    static let hidden = WorkspaceSurfacePresentationFacts(revealPhase: .hidden)
    static let visible = WorkspaceSurfacePresentationFacts(revealPhase: .visible)

    static func terminal(_ facts: TerminalViewportLifecycleFacts) -> WorkspaceSurfacePresentationFacts {
        WorkspaceSurfacePresentationFacts(revealPhase: WorkspaceSurfaceRevealPhase(terminalFacts: facts))
    }
}

@MainActor
protocol WorkspacePaneContentProvider: Panel {
    func workspacePaneContent(
        using context: WorkspacePaneContentBuildContext
    ) -> WorkspacePaneContent
}

@MainActor
struct WorkspacePaneContentBuildContext {
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let workspacePortalPriority: Int
    let onRequestFocus: () -> Void
    let onTriggerFlash: () -> Void
}

@MainActor
struct WorkspaceTerminalPaneContent {
    let surfaceId: UUID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let onFocus: () -> Void
    let onTriggerFlash: () -> Void
}

@MainActor
struct WorkspaceBrowserPaneContent {
    let surfaceId: UUID
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let prefersLocalInlineHosting: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void
}

@MainActor
struct WorkspaceMarkdownPaneContent {
    let surfaceId: UUID
    let isVisibleInUI: Bool
    let onRequestPanelFocus: () -> Void
}

@MainActor
struct WorkspacePlaceholderPaneContent {
    let paneId: PaneID
    let onCreateTerminal: () -> Void
    let onCreateBrowser: () -> Void
}

struct WorkspaceLayoutTabChromeSnapshot {
    let tab: WorkspaceLayout.Tab
    let contextMenuState: TabContextMenuState
    let isSelected: Bool
    let showsZoomIndicator: Bool
}

struct WorkspaceLayoutPaneChromeSnapshot {
    let paneId: PaneID
    let tabs: [WorkspaceLayoutTabChromeSnapshot]
    let selectedTabId: UUID?
    let isFocused: Bool
    let showSplitButtons: Bool
    let chromeRevision: UInt64
}

struct WorkspaceLayoutPaneRenderSnapshot {
    let paneId: PaneID
    let chrome: WorkspaceLayoutPaneChromeSnapshot
    let contentId: UUID
    let content: WorkspacePaneContent
}

struct WorkspaceLayoutViewportSnapshot {
    let paneId: PaneID
    let contentId: UUID
    let mountIdentity: WorkspacePaneMountIdentity
    let content: WorkspacePaneContent
    let frame: CGRect
}

struct WorkspaceLayoutSplitRenderSnapshot {
    let splitId: UUID
    let orientation: SplitOrientation
    let dividerPosition: CGFloat
    let animationOrigin: SplitAnimationOrigin?
    let first: WorkspaceLayoutRenderNodeSnapshot
    let second: WorkspaceLayoutRenderNodeSnapshot
}

indirect enum WorkspaceLayoutRenderNodeSnapshot {
    case pane(WorkspaceLayoutPaneRenderSnapshot)
    case split(WorkspaceLayoutSplitRenderSnapshot)

    var paneIds: Set<UUID> {
        switch self {
        case .pane(let pane):
            return [pane.paneId.id]
        case .split(let split):
            return split.first.paneIds.union(split.second.paneIds)
        }
    }

    var splitIds: Set<UUID> {
        switch self {
        case .pane:
            return []
        case .split(let split):
            return Set([split.splitId])
                .union(split.first.splitIds)
                .union(split.second.splitIds)
        }
    }
}

struct WorkspaceLayoutLocalDragSnapshot: Equatable {
    let tabId: TabID
    let sourcePaneId: PaneID
}

func workspaceLayoutEffectiveTabDropTargetIndex(
    rawTargetIndex: Int,
    tabIds: [TabID],
    paneId: PaneID,
    localTabDrag: WorkspaceLayoutLocalDragSnapshot?
) -> Int? {
    guard let localTabDrag,
          localTabDrag.sourcePaneId == paneId,
          let sourceIndex = tabIds.firstIndex(of: localTabDrag.tabId) else {
        return rawTargetIndex
    }

    if rawTargetIndex == sourceIndex || rawTargetIndex == sourceIndex + 1 {
        return nil
    }

    return rawTargetIndex
}

enum WorkspacePaneDropOverlayPhase: Equatable {
    case hidden
    case visible
    case hiding
}

struct WorkspacePaneDropOverlayPresentation: Equatable {
    let phase: WorkspacePaneDropOverlayPhase
    let zone: DropZone?
    let generation: UInt64

    static let hidden = WorkspacePaneDropOverlayPresentation(
        phase: .hidden,
        zone: nil,
        generation: 0
    )

    static func visible(zone: DropZone, generation: UInt64) -> WorkspacePaneDropOverlayPresentation {
        WorkspacePaneDropOverlayPresentation(
            phase: .visible,
            zone: zone,
            generation: generation
        )
    }

    static func hiding(zone: DropZone, generation: UInt64) -> WorkspacePaneDropOverlayPresentation {
        WorkspacePaneDropOverlayPresentation(
            phase: .hiding,
            zone: zone,
            generation: generation
        )
    }
}

struct WorkspacePaneDropOverlayCoordinator {
    private(set) var activeDropZones: [UUID: DropZone] = [:]
    private(set) var presentations: [UUID: WorkspacePaneDropOverlayPresentation] = [:]
    private var nextGenerationValue: UInt64 = 1

    mutating func setZone(_ zone: DropZone, for paneId: PaneID) -> Bool {
        let key = paneId.id
        let previousZone = activeDropZones[key]
        let previousPresentation = presentations[key] ?? .hidden
        activeDropZones[key] = zone
        if previousPresentation.phase != .visible || previousPresentation.zone != zone {
            presentations[key] = .visible(zone: zone, generation: nextGeneration())
        }
        let nextPresentation = presentations[key] ?? .hidden
        return previousZone != zone || previousPresentation != nextPresentation
    }

    mutating func clearZone(for paneId: PaneID) -> Bool {
        let key = paneId.id
        let previousZone = activeDropZones.removeValue(forKey: key)
        let previousPresentation = presentations[key] ?? .hidden
        let lastZone = previousPresentation.zone ?? previousZone
        if let lastZone, previousPresentation.phase != .hiding {
            presentations[key] = .hiding(zone: lastZone, generation: nextGeneration())
        } else if lastZone == nil {
            presentations.removeValue(forKey: key)
        }
        let nextPresentation = presentations[key] ?? .hidden
        return previousZone != nil || previousPresentation != nextPresentation
    }

    mutating func clearZoneImmediately(for paneId: PaneID) -> Bool {
        let key = paneId.id
        let previousZone = activeDropZones.removeValue(forKey: key)
        let previousPresentation = presentations.removeValue(forKey: key) ?? .hidden
        return previousZone != nil || previousPresentation != .hidden
    }

    mutating func completeHide(for paneId: PaneID, generation: UInt64) -> Bool {
        let key = paneId.id
        guard let presentation = presentations[key],
              presentation.phase == .hiding,
              presentation.generation == generation else {
            return false
        }
        presentations.removeValue(forKey: key)
        return true
    }

    func activeDropZone(for paneId: PaneID) -> DropZone? {
        activeDropZones[paneId.id]
    }

    func overlayPresentation(for paneId: PaneID) -> WorkspacePaneDropOverlayPresentation {
        presentations[paneId.id] ?? .hidden
    }

    func viewportDropZones() -> [UUID: DropZone?] {
        activeDropZones.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }
    }

    mutating func removePane(_ paneId: PaneID) {
        activeDropZones.removeValue(forKey: paneId.id)
        presentations.removeValue(forKey: paneId.id)
    }

    mutating func clearAll() {
        activeDropZones.removeAll()
        presentations.removeAll()
    }

    private mutating func nextGeneration() -> UInt64 {
        defer { nextGenerationValue &+= 1 }
        return nextGenerationValue
    }
}

struct WorkspaceLayoutPresentationSnapshot {
    let appearance: WorkspaceLayoutConfiguration.Appearance
    let isInteractive: Bool
    let isMinimalMode: Bool
    let localTabDrag: WorkspaceLayoutLocalDragSnapshot?

    var isHandlingLocalTabDrag: Bool {
        localTabDrag != nil
    }
}

struct WorkspaceLayoutRenderSnapshot {
    let presentation: WorkspaceLayoutPresentationSnapshot
    let root: WorkspaceLayoutRenderNodeSnapshot
    let viewports: [WorkspaceLayoutViewportSnapshot]
}
