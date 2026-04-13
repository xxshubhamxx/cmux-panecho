import Foundation
import SwiftUI
import Observation

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
}

typealias TabID = WorkspaceTabID

enum WorkspaceSplitOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

typealias SplitOrientation = WorkspaceSplitOrientation

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

enum ContentViewLifecycle: Sendable {
    case recreateOnSwitch
    case keepAllAlive
}

enum NewTabPosition: Sendable {
    case current
    case end
}

struct WorkspaceSplitConfiguration: Sendable {
    var allowSplits: Bool
    var allowCloseTabs: Bool
    var allowCloseLastPane: Bool
    var allowTabReordering: Bool
    var allowCrossPaneTabMove: Bool
    var autoCloseEmptyPanes: Bool
    var contentViewLifecycle: ContentViewLifecycle
    var newTabPosition: NewTabPosition
    var appearance: Appearance

    static let `default` = WorkspaceSplitConfiguration()

    init(
        allowSplits: Bool = true,
        allowCloseTabs: Bool = true,
        allowCloseLastPane: Bool = false,
        allowTabReordering: Bool = true,
        allowCrossPaneTabMove: Bool = true,
        autoCloseEmptyPanes: Bool = true,
        contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch,
        newTabPosition: NewTabPosition = .current,
        appearance: Appearance = .default
    ) {
        self.allowSplits = allowSplits
        self.allowCloseTabs = allowCloseTabs
        self.allowCloseLastPane = allowCloseLastPane
        self.allowTabReordering = allowTabReordering
        self.allowCrossPaneTabMove = allowCrossPaneTabMove
        self.autoCloseEmptyPanes = autoCloseEmptyPanes
        self.contentViewLifecycle = contentViewLifecycle
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
            newTerminal: String = "New Terminal",
            newBrowser: String = "New Browser",
            splitRight: String = "Split Right",
            splitDown: String = "Split Down"
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

enum WorkspaceSplit {
    struct Tab: Identifiable, Hashable, Sendable {
        var id: TabID
        var title: String
        var hasCustomTitle: Bool
        var icon: String?
        var iconImageData: Data?
        var kind: String?
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
            kind: String? = nil,
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
    }
}

protocol WorkspaceSplitDelegate: AnyObject {
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldCreateTab tab: WorkspaceSplit.Tab, inPane pane: PaneID) -> Bool
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldCloseTab tab: WorkspaceSplit.Tab, inPane pane: PaneID) -> Bool
    func workspaceSplit(_ controller: WorkspaceSplitController, didCreateTab tab: WorkspaceSplit.Tab, inPane pane: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didCloseTab tabId: TabID, fromPane pane: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didSelectTab tab: WorkspaceSplit.Tab, inPane pane: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didMoveTab tab: WorkspaceSplit.Tab, fromPane source: PaneID, toPane destination: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldClosePane pane: PaneID) -> Bool
    func workspaceSplit(_ controller: WorkspaceSplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation)
    func workspaceSplit(_ controller: WorkspaceSplitController, didClosePane paneId: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didFocusPane pane: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didRequestNewTab kind: String, inPane pane: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didRequestTabContextAction action: TabContextAction, for tab: WorkspaceSplit.Tab, inPane pane: PaneID)
    func workspaceSplit(_ controller: WorkspaceSplitController, didChangeGeometry snapshot: LayoutSnapshot)
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldNotifyDuringDrag: Bool) -> Bool
}

extension WorkspaceSplitDelegate {
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldCreateTab tab: WorkspaceSplit.Tab, inPane pane: PaneID) -> Bool { true }
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldCloseTab tab: WorkspaceSplit.Tab, inPane pane: PaneID) -> Bool { true }
    func workspaceSplit(_ controller: WorkspaceSplitController, didCreateTab tab: WorkspaceSplit.Tab, inPane pane: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didSelectTab tab: WorkspaceSplit.Tab, inPane pane: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didMoveTab tab: WorkspaceSplit.Tab, fromPane source: PaneID, toPane destination: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool { true }
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldClosePane pane: PaneID) -> Bool { true }
    func workspaceSplit(_ controller: WorkspaceSplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didClosePane paneId: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didFocusPane pane: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didRequestNewTab kind: String, inPane pane: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didRequestTabContextAction action: TabContextAction, for tab: WorkspaceSplit.Tab, inPane pane: PaneID) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, didChangeGeometry snapshot: LayoutSnapshot) {}
    func workspaceSplit(_ controller: WorkspaceSplitController, shouldNotifyDuringDrag: Bool) -> Bool { false }
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

extension WorkspaceSplit.Tab {
    init(from tabItem: TabItem) {
        self.init(
            id: TabID(id: tabItem.id),
            title: tabItem.title,
            hasCustomTitle: tabItem.hasCustomTitle,
            icon: tabItem.icon,
            iconImageData: tabItem.iconImageData,
            kind: tabItem.kind,
            isDirty: tabItem.isDirty,
            showsNotificationBadge: tabItem.showsNotificationBadge,
            isLoading: tabItem.isLoading,
            isPinned: tabItem.isPinned
        )
    }
}

#if DEBUG
enum WorkspaceSplitDebugCounters {
    private(set) static var arrangedSubviewUnderflowCount: Int = 0

    static func reset() {
        arrangedSubviewUnderflowCount = 0
    }

    static func recordArrangedSubviewUnderflow() {
        arrangedSubviewUnderflowCount += 1
    }
}
#else
enum WorkspaceSplitDebugCounters {
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

/// Represents a single tab in a pane's tab bar (internal representation)
struct TabItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var hasCustomTitle: Bool
    var icon: String?
    var iconImageData: Data?
    var kind: String?
    var isDirty: Bool
    var showsNotificationBadge: Bool
    var isLoading: Bool
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        hasCustomTitle: Bool = false,
        icon: String? = "doc.text",
        iconImageData: Data? = nil,
        kind: String? = nil,
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case hasCustomTitle
        case icon
        case iconImageData
        case kind
        case isDirty
        case showsNotificationBadge
        case isLoading
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.hasCustomTitle = try c.decodeIfPresent(Bool.self, forKey: .hasCustomTitle) ?? false
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.iconImageData = try c.decodeIfPresent(Data.self, forKey: .iconImageData)
        self.kind = try c.decodeIfPresent(String.self, forKey: .kind)
        self.isDirty = try c.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        self.showsNotificationBadge = try c.decodeIfPresent(Bool.self, forKey: .showsNotificationBadge) ?? false
        self.isLoading = try c.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(hasCustomTitle, forKey: .hasCustomTitle)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(iconImageData, forKey: .iconImageData)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encode(isDirty, forKey: .isDirty)
        try c.encode(showsNotificationBadge, forKey: .showsNotificationBadge)
        try c.encode(isLoading, forKey: .isLoading)
        try c.encode(isPinned, forKey: .isPinned)
    }
}

// MARK: - Transferable for Drag & Drop

extension TabItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabItem)
    }
}

/// Transfer data that includes source pane information for cross-pane moves
struct TabTransferData: Codable, Transferable {
    let tab: TabItem
    let sourcePaneId: UUID
    let sourceProcessId: Int32

    init(tab: TabItem, sourcePaneId: UUID, sourceProcessId: Int32 = Int32(ProcessInfo.processInfo.processIdentifier)) {
        self.tab = tab
        self.sourcePaneId = sourcePaneId
        self.sourceProcessId = sourceProcessId
    }

    var isFromCurrentProcess: Bool {
        sourceProcessId == Int32(ProcessInfo.processInfo.processIdentifier)
    }

    private enum CodingKeys: String, CodingKey {
        case tab
        case sourcePaneId
        case sourceProcessId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tab = try container.decode(TabItem.self, forKey: .tab)
        self.sourcePaneId = try container.decode(UUID.self, forKey: .sourcePaneId)
        // Legacy payloads won't include this field. Treat as foreign process to reject cross-instance drops.
        self.sourceProcessId = try container.decodeIfPresent(Int32.self, forKey: .sourceProcessId) ?? -1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tab, forKey: .tab)
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
@Observable
final class PaneState: Identifiable {
    let id: PaneID
    var tabs: [TabItem]
    var selectedTabId: UUID?

    init(
        id: PaneID = PaneID(),
        tabs: [TabItem] = [],
        selectedTabId: UUID? = nil
    ) {
        self.id = id
        self.tabs = tabs
        self.selectedTabId = selectedTabId ?? tabs.first?.id
    }

    /// Currently selected tab
    var selectedTab: TabItem? {
        tabs.first { $0.id == selectedTabId }
    }

    /// Select a tab by ID
    func selectTab(_ tabId: UUID) {
        guard tabs.contains(where: { $0.id == tabId }) else { return }
        selectedTabId = tabId
    }

    /// Add a new tab
    func addTab(_ tab: TabItem, select: Bool = true) {
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let insertIndex = tab.isPinned ? pinnedCount : tabs.count
        tabs.insert(tab, at: insertIndex)
        if select {
            selectedTabId = tab.id
        }
    }

    /// Insert a tab at a specific index
    func insertTab(_ tab: TabItem, at index: Int, select: Bool = true) {
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let requested = min(max(0, index), tabs.count)
        let safeIndex: Int
        if tab.isPinned {
            safeIndex = min(requested, pinnedCount)
        } else {
            safeIndex = max(requested, pinnedCount)
        }
        tabs.insert(tab, at: safeIndex)
        if select {
            selectedTabId = tab.id
        }
    }

    /// Remove a tab and return it
    @discardableResult
    func removeTab(_ tabId: UUID) -> TabItem? {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        let tab = tabs.remove(at: index)

        // If we removed the selected tab, keep the index stable when possible:
        // prefer selecting the tab that moved into the removed tab's slot (the "next" tab),
        // and only fall back to selecting the previous tab when we removed the last tab.
        if selectedTabId == tabId {
            if !tabs.isEmpty {
                let newIndex = min(index, max(0, tabs.count - 1))
                selectedTabId = tabs[newIndex].id
            } else {
                selectedTabId = nil
            }
        }

        return tab
    }

    /// Move a tab within this pane
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }

        // Treat dropping "on itself" or "after itself" as a no-op.
        // This avoids remove/insert churn that can cause brief visual artifacts during drag/drop.
        if destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1 {
            return
        }

        let tab = tabs.remove(at: sourceIndex)
        let requestedIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let adjustedIndex: Int
        if tab.isPinned {
            adjustedIndex = min(requestedIndex, pinnedCount)
        } else {
            adjustedIndex = max(requestedIndex, pinnedCount)
        }
        let safeIndex = min(max(0, adjustedIndex), tabs.count)
        tabs.insert(tab, at: safeIndex)
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

    /// Find the leaf node for a pane by ID.
    func findNode(containing paneId: PaneID) -> SplitNode? {
        switch self {
        case .pane(let state):
            return state.id == paneId ? self : nil
        case .split(let state):
            return state.first.findNode(containing: paneId) ?? state.second.findNode(containing: paneId)
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
enum SplitAnimationOrigin {
    case fromFirst   // New pane slides in from start (left/top)
    case fromSecond  // New pane slides in from end (right/bottom)
}

/// State for a split node (branch in the split tree)
@Observable
final class SplitState: Identifiable {
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
import SwiftUI

/// Central controller managing the entire split view state (internal implementation)
@Observable
@MainActor
final class SplitViewController {
    /// The root node of the split tree
    var rootNode: SplitNode

    /// Currently zoomed pane. When set, rendering should only show this pane.
    var zoomedPaneId: PaneID?

    /// Currently focused pane ID
    var focusedPaneId: PaneID?

    /// Tab currently being dragged (for visual feedback and hit-testing).
    /// This is @Observable so SwiftUI views react (e.g. allowsHitTesting).
    var draggingTab: TabItem?

    /// Monotonic counter incremented on each drag start. Used to invalidate stale
    /// timeout timers that would otherwise cancel a new drag of the same tab.
    var dragGeneration: Int = 0

    /// Source pane of the dragging tab
    var dragSourcePaneId: PaneID?

    /// Non-observable drag session state. Drop delegates read these instead of the
    /// @Observable properties above, because SwiftUI batches observable updates and
    /// createItemProvider's writes may not be visible to validateDrop/performDrop yet.
    @ObservationIgnored var activeDragTab: TabItem?
    @ObservationIgnored var activeDragSourcePaneId: PaneID?

    /// When false, drop delegates reject all drags and NSViews are hidden.
    /// Mirrors WorkspaceSplitController.isInteractive. Must be observable so
    /// updateNSView is called to toggle isHidden on the AppKit containers.
    var isInteractive: Bool = true

    /// Handler for file/URL drops from external apps (e.g. Finder).
    /// Receives the dropped URLs and the pane ID where the drop occurred.
    @ObservationIgnored var onFileDrop: ((_ urls: [URL], _ paneId: PaneID) -> Bool)?

    /// During drop, SwiftUI may keep the source tab view alive briefly (default removal animation)
    /// even after we've updated the model. Hide it explicitly so it disappears immediately.
    var dragHiddenSourceTabId: UUID?
    var dragHiddenSourcePaneId: PaneID?

    /// Current frame of the entire split view container
    var containerFrame: CGRect = .zero

    /// Flag to prevent notification loops during external updates
    var isExternalUpdateInProgress: Bool = false

    /// Timestamp of last geometry notification for debouncing
    var lastGeometryNotificationTime: TimeInterval = 0

    /// Callback for geometry changes
    var onGeometryChange: (() -> Void)?

    init(rootNode: SplitNode? = nil) {
        if let rootNode {
            self.rootNode = rootNode
        } else {
            // Initialize with a single pane containing a welcome tab
            let welcomeTab = TabItem(title: "Welcome", icon: "star")
            let initialPane = PaneState(tabs: [welcomeTab])
            self.rootNode = .pane(initialPane)
            self.focusedPaneId = initialPane.id
        }
    }

    // MARK: - Focus Management

    /// Set focus to a specific pane
    func focusPane(_ paneId: PaneID) {
        guard rootNode.findPane(paneId) != nil else { return }
#if DEBUG
        dlog("focus.WorkspaceSplit pane=\(paneId.id.uuidString.prefix(5))")
#endif
        focusedPaneId = paneId
    }

    /// Get the currently focused pane state
    var focusedPane: PaneState? {
        guard let focusedPaneId else { return nil }
        return rootNode.findPane(focusedPaneId)
    }

    var zoomedNode: SplitNode? {
        guard let zoomedPaneId else { return nil }
        return rootNode.findNode(containing: zoomedPaneId)
    }

    @discardableResult
    func clearPaneZoom() -> Bool {
        guard zoomedPaneId != nil else { return false }
        zoomedPaneId = nil
        return true
    }

    @discardableResult
    func togglePaneZoom(_ paneId: PaneID) -> Bool {
        guard rootNode.findPane(paneId) != nil else { return false }

        if zoomedPaneId == paneId {
            zoomedPaneId = nil
            return true
        }

        // Match Ghostty behavior: a single-pane layout can't be zoomed.
        guard rootNode.allPaneIds.count > 1 else { return false }
        zoomedPaneId = paneId
        focusedPaneId = paneId
        return true
    }

    // MARK: - Split Operations

    /// Split the specified pane in the given orientation
    func splitPane(_ paneId: PaneID, orientation: SplitOrientation, with newTab: TabItem? = nil) {
        clearPaneZoom()
        rootNode = splitNodeRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            newTab: newTab
        )
    }

    private func splitNodeRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        newTab: TabItem?
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                // Create new pane - empty if no tab provided (gives developer full control)
                let newPane: PaneState
                if let tab = newTab {
                    newPane = PaneState(tabs: [tab])
                } else {
                    newPane = PaneState(tabs: [])
                }

                // Start with divider at the edge so there's no flash before animation
                let splitState = SplitState(
                    orientation: orientation,
                    first: .pane(paneState),
                    second: .pane(newPane),
                    // Keep the model at its steady-state ratio. The view layer can still animate
                    // from an edge via animationOrigin, but the model should never represent a
                    // fully-collapsed pane (which can get stuck under view reparenting timing).
                    dividerPosition: 0.5,
                    animationOrigin: .fromSecond  // New pane slides in from right/bottom
                )

                // Focus the new pane
                focusedPaneId = newPane.id

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            splitState.first = splitNodeRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTab: newTab
            )
            splitState.second = splitNodeRecursively(
                node: splitState.second,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTab: newTab
            )
            return .split(splitState)
        }
    }

    /// Split a pane with a specific tab, optionally inserting the new pane first
    func splitPaneWithTab(_ paneId: PaneID, orientation: SplitOrientation, tab: TabItem, insertFirst: Bool) {
        clearPaneZoom()
        rootNode = splitNodeWithTabRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            tab: tab,
            insertFirst: insertFirst
        )
    }

    private func splitNodeWithTabRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        tab: TabItem,
        insertFirst: Bool
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                // Create new pane with the tab
                let newPane = PaneState(tabs: [tab])

                // Start with divider at the edge so there's no flash before animation
                let splitState: SplitState
                if insertFirst {
                    // New pane goes first (left or top).
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(newPane),
                        second: .pane(paneState),
                        dividerPosition: 0.5,
                        animationOrigin: .fromFirst
                    )
                } else {
                    // New pane goes second (right or bottom).
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(paneState),
                        second: .pane(newPane),
                        dividerPosition: 0.5,
                        animationOrigin: .fromSecond
                    )
                }

                // Focus the new pane
                focusedPaneId = newPane.id

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            splitState.first = splitNodeWithTabRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tab: tab,
                insertFirst: insertFirst
            )
            splitState.second = splitNodeWithTabRecursively(
                node: splitState.second,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tab: tab,
                insertFirst: insertFirst
            )
            return .split(splitState)
        }
    }

    /// Close a pane and collapse the split
    func closePane(_ paneId: PaneID) {
        // Don't close the last pane
        guard rootNode.allPaneIds.count > 1 else { return }

        let (newRoot, siblingPaneId) = closePaneRecursively(node: rootNode, targetPaneId: paneId)

        if let newRoot {
            rootNode = newRoot
        }

        // Focus the sibling or first available pane
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
            // Check if either direct child is the target
            if case .pane(let firstPane) = splitState.first, firstPane.id == targetPaneId {
                let focusTarget = splitState.second.allPaneIds.first
                return (splitState.second, focusTarget)
            }

            if case .pane(let secondPane) = splitState.second, secondPane.id == targetPaneId {
                let focusTarget = splitState.first.allPaneIds.first
                return (splitState.first, focusTarget)
            }

            // Recursively check children
            let (newFirst, focusFromFirst) = closePaneRecursively(node: splitState.first, targetPaneId: targetPaneId)
            if newFirst == nil {
                return (splitState.second, splitState.second.allPaneIds.first)
            }

            let (newSecond, focusFromSecond) = closePaneRecursively(node: splitState.second, targetPaneId: targetPaneId)
            if newSecond == nil {
                return (splitState.first, splitState.first.allPaneIds.first)
            }

            if let newFirst { splitState.first = newFirst }
            if let newSecond { splitState.second = newSecond }

            return (.split(splitState), focusFromFirst ?? focusFromSecond)
        }
    }

    // MARK: - Tab Operations

    /// Add a tab to the focused pane (or specified pane)
    func addTab(_ tab: TabItem, toPane paneId: PaneID? = nil, atIndex index: Int? = nil) {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId,
              let pane = rootNode.findPane(targetPaneId) else { return }

        if let index {
            pane.insertTab(tab, at: index)
        } else {
            pane.addTab(tab)
        }
    }

    /// Move a tab from one pane to another
    func moveTab(_ tab: TabItem, from sourcePaneId: PaneID, to targetPaneId: PaneID, atIndex index: Int? = nil) {
        guard let sourcePane = rootNode.findPane(sourcePaneId),
              let targetPane = rootNode.findPane(targetPaneId) else { return }

        // Remove from source
        sourcePane.removeTab(tab.id)

        // Add to target
        if let index {
            targetPane.insertTab(tab, at: index)
        } else {
            targetPane.addTab(tab)
        }

        // Focus target pane
        focusPane(targetPaneId)

        // If source pane is now empty and not the only pane, close it
        if sourcePane.tabs.isEmpty && rootNode.allPaneIds.count > 1 {
            closePane(sourcePaneId)
        }
    }

    /// Close a tab in a specific pane
    func closeTab(_ tabId: UUID, inPane paneId: PaneID) {
        guard let pane = rootNode.findPane(paneId) else { return }

        pane.removeTab(tabId)

        // If pane is now empty and not the only pane, close it
        if pane.tabs.isEmpty && rootNode.allPaneIds.count > 1 {
            closePane(paneId)
        }
    }

    // MARK: - Keyboard Navigation

    /// Navigate focus to an adjacent pane based on spatial position
    func navigateFocus(direction: NavigationDirection) {
        guard let currentPaneId = focusedPaneId else { return }

        let allPaneBounds = rootNode.computePaneBounds()
        guard let currentBounds = allPaneBounds.first(where: { $0.paneId == currentPaneId })?.bounds else { return }

        if let targetPaneId = findBestNeighbor(from: currentBounds, currentPaneId: currentPaneId,
                                               direction: direction, allPaneBounds: allPaneBounds) {
            focusPane(targetPaneId)
        }
        // No neighbor found = at edge, do nothing
    }

    /// Find the closest pane in the requested direction from the given pane.
    func adjacentPane(to paneId: PaneID, direction: NavigationDirection) -> PaneID? {
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

    private func findBestNeighbor(from currentBounds: CGRect, currentPaneId: PaneID,
                                  direction: NavigationDirection, allPaneBounds: [PaneBounds]) -> PaneID? {
        let epsilon: CGFloat = 0.001

        // Filter to panes in the target direction
        let candidates = allPaneBounds.filter { paneBounds in
            guard paneBounds.paneId != currentPaneId else { return false }
            let b = paneBounds.bounds
            switch direction {
            case .left:  return b.maxX <= currentBounds.minX + epsilon
            case .right: return b.minX >= currentBounds.maxX - epsilon
            case .up:    return b.maxY <= currentBounds.minY + epsilon
            case .down:  return b.minY >= currentBounds.maxY - epsilon
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Score by overlap (perpendicular axis) and distance
        let scored: [(PaneID, CGFloat, CGFloat)] = candidates.map { c in
            let overlap: CGFloat
            let distance: CGFloat

            switch direction {
            case .left, .right:
                // Vertical overlap for horizontal movement
                overlap = max(0, min(currentBounds.maxY, c.bounds.maxY) - max(currentBounds.minY, c.bounds.minY))
                distance = direction == .left ? (currentBounds.minX - c.bounds.maxX) : (c.bounds.minX - currentBounds.maxX)
            case .up, .down:
                // Horizontal overlap for vertical movement
                overlap = max(0, min(currentBounds.maxX, c.bounds.maxX) - max(currentBounds.minX, c.bounds.minX))
                distance = direction == .up ? (currentBounds.minY - c.bounds.maxY) : (c.bounds.minY - currentBounds.maxY)
            }

            return (c.paneId, overlap, distance)
        }

        // Sort: prefer more overlap, then closer distance
        let sorted = scored.sorted { a, b in
            if abs(a.1 - b.1) > epsilon { return a.1 > b.1 }
            return a.2 < b.2
        }

        return sorted.first?.0
    }

    /// Create a new tab in the focused pane
    func createNewTab() {
        guard let pane = focusedPane else { return }
        let count = pane.tabs.count + 1
        let newTab = TabItem(title: "Untitled \(count)", icon: "doc")
        pane.addTab(newTab)
    }

    /// Close the currently selected tab in the focused pane
    func closeSelectedTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId else { return }
        closeTab(selectedTabId, inPane: pane.id)
    }

    /// Select the previous tab in the focused pane
    func selectPreviousTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex > 0 ? currentIndex - 1 : pane.tabs.count - 1
        pane.selectTab(pane.tabs[newIndex].id)
    }

    /// Select the next tab in the focused pane
    func selectNextTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex < pane.tabs.count - 1 ? currentIndex + 1 : 0
        pane.selectTab(pane.tabs[newIndex].id)
    }

    // MARK: - Split State Access

    /// Find a split state by its UUID
    func findSplit(_ splitId: UUID) -> SplitState? {
        return findSplitRecursively(in: rootNode, id: splitId)
    }

    private func findSplitRecursively(in node: SplitNode, id: UUID) -> SplitState? {
        switch node {
        case .pane:
            return nil
        case .split(let splitState):
            if splitState.id == id {
                return splitState
            }
            if let found = findSplitRecursively(in: splitState.first, id: id) {
                return found
            }
            return findSplitRecursively(in: splitState.second, id: id)
        }
    }

    /// Get all split states in the tree
    var allSplits: [SplitState] {
        return collectSplits(from: rootNode)
    }

    private func collectSplits(from node: SplitNode) -> [SplitState] {
        switch node {
        case .pane:
            return []
        case .split(let splitState):
            return [splitState] + collectSplits(from: splitState.first) + collectSplits(from: splitState.second)
        }
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
    static let activeIndicatorHeight: CGFloat = 2

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
        static let lightTextAlpha: CGFloat = 0.82
        static let lightSecondaryTextAlpha: CGFloat = 0.68
    }

    private static func chromeBackgroundColor(
        for appearance: WorkspaceSplitConfiguration.Appearance
    ) -> NSColor? {
        guard let value = appearance.chromeColors.backgroundHex else { return nil }
        return NSColor(workspaceSplitHex: value)
    }

    private static func chromeBorderColor(
        for appearance: WorkspaceSplitConfiguration.Appearance
    ) -> NSColor? {
        guard let value = appearance.chromeColors.borderHex else { return nil }
        return NSColor(workspaceSplitHex: value)
    }

    private static func effectiveBackgroundColor(
        for appearance: WorkspaceSplitConfiguration.Appearance,
        fallback fallbackColor: NSColor
    ) -> NSColor {
        chromeBackgroundColor(for: appearance) ?? fallbackColor
    }

    private static func effectiveTextColor(
        for appearance: WorkspaceSplitConfiguration.Appearance,
        secondary: Bool
    ) -> NSColor {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return secondary ? .secondaryLabelColor : .labelColor
        }

        if custom.isWorkspaceSplitLightColor {
            let alpha = secondary ? Constants.darkSecondaryTextAlpha : Constants.darkTextAlpha
            return NSColor.black.withAlphaComponent(alpha)
        }

        let alpha = secondary ? Constants.lightSecondaryTextAlpha : Constants.lightTextAlpha
        return NSColor.white.withAlphaComponent(alpha)
    }

    static func paneBackground(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveBackgroundColor(for: appearance, fallback: .textBackgroundColor))
    }

    static func nsColorPaneBackground(for appearance: WorkspaceSplitConfiguration.Appearance) -> NSColor {
        effectiveBackgroundColor(for: appearance, fallback: .textBackgroundColor)
    }

    // MARK: - Tab Bar Background

    static var barBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func barBackground(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveBackgroundColor(for: appearance, fallback: .windowBackgroundColor))
    }

    static var barMaterial: Material {
        .bar
    }

    // MARK: - Tab States

    static var activeTabBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func activeTabBackground(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return activeTabBackground
        }
        let adjusted = custom.isWorkspaceSplitLightColor
            ? custom.workspaceSplitDarken(by: 0.065)
            : custom.workspaceSplitLighten(by: 0.12)
        return Color(nsColor: adjusted)
    }

    static var hoveredTabBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    static func hoveredTabBackground(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return hoveredTabBackground
        }
        let adjusted = custom.isWorkspaceSplitLightColor
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

    static func activeText(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveTextColor(for: appearance, secondary: false))
    }

    static func nsColorActiveText(for appearance: WorkspaceSplitConfiguration.Appearance) -> NSColor {
        effectiveTextColor(for: appearance, secondary: false)
    }

    static var inactiveText: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    static func inactiveText(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveTextColor(for: appearance, secondary: true))
    }

    static func nsColorInactiveText(for appearance: WorkspaceSplitConfiguration.Appearance) -> NSColor {
        effectiveTextColor(for: appearance, secondary: true)
    }

    static func splitActionIcon(for appearance: WorkspaceSplitConfiguration.Appearance, isPressed: Bool) -> Color {
        Color(nsColor: nsColorSplitActionIcon(for: appearance, isPressed: isPressed))
    }

    static func nsColorSplitActionIcon(
        for appearance: WorkspaceSplitConfiguration.Appearance,
        isPressed: Bool
    ) -> NSColor {
        isPressed ? nsColorActiveText(for: appearance) : nsColorInactiveText(for: appearance)
    }

    // MARK: - Borders & Indicators

    static var separator: Color {
        Color(nsColor: .separatorColor)
    }

    static func separator(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        Color(nsColor: nsColorSeparator(for: appearance))
    }

    static func nsColorSeparator(for appearance: WorkspaceSplitConfiguration.Appearance) -> NSColor {
        if let explicit = chromeBorderColor(for: appearance) {
            return explicit
        }

        guard let custom = chromeBackgroundColor(for: appearance) else {
            return .separatorColor
        }
        let alpha: CGFloat = custom.isWorkspaceSplitLightColor ? 0.26 : 0.36
        let tone = custom.isWorkspaceSplitLightColor
            ? custom.workspaceSplitDarken(by: 0.12)
            : custom.workspaceSplitLighten(by: 0.16)
        return tone.withAlphaComponent(alpha)
    }

    static var dropIndicator: Color {
        Color.accentColor
    }

    static func dropIndicator(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        _ = appearance
        return dropIndicator
    }

    static var focusRing: Color {
        Color.accentColor.opacity(0.5)
    }

    static var dirtyIndicator: Color {
        Color(nsColor: .labelColor).opacity(0.6)
    }

    static func dirtyIndicator(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
        guard chromeBackgroundColor(for: appearance) != nil else { return dirtyIndicator }
        return activeText(for: appearance).opacity(0.72)
    }

    static var notificationBadge: Color {
        Color(nsColor: .systemBlue)
    }

    static func notificationBadge(for appearance: WorkspaceSplitConfiguration.Appearance) -> Color {
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

    var isWorkspaceSplitLightColor: Bool {
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

import SwiftUI

/// Preview shown during tab drag operations
struct TabDragPreview: View {
    let tab: TabItem
    let appearance: WorkspaceSplitConfiguration.Appearance

    var body: some View {
        HStack(spacing: TabBarMetrics.contentSpacing) {
            if let iconName = tab.icon {
                Image(systemName: iconName)
                    .font(.system(size: TabBarMetrics.iconSize))
                    .foregroundStyle(TabBarColors.activeText(for: appearance))
            }

            Text(tab.title)
                .font(.system(size: TabBarMetrics.titleFontSize))
                .lineLimit(1)
                .foregroundStyle(TabBarColors.activeText(for: appearance))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: TabBarMetrics.tabCornerRadius, style: .continuous)
                .fill(TabBarColors.activeTabBackground(for: appearance))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .opacity(0.9)
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

@MainActor
@Observable
final class WorkspaceSplitController {

    struct ExternalTabDropRequest {
        enum Destination {
            case insert(targetPane: PaneID, targetIndex: Int?)
            case split(targetPane: PaneID, orientation: SplitOrientation, insertFirst: Bool)
        }

        let tabId: TabID
        let sourcePaneId: PaneID
        let destination: Destination

        init(tabId: TabID, sourcePaneId: PaneID, destination: Destination) {
            self.tabId = tabId
            self.sourcePaneId = sourcePaneId
            self.destination = destination
        }
    }

    // MARK: - Delegate

    /// Delegate for receiving callbacks about tab bar events
    weak var delegate: WorkspaceSplitDelegate?

    // MARK: - Configuration

    /// Configuration for behavior and appearance
    var configuration: WorkspaceSplitConfiguration

    /// When false, drop delegates reject all drags. Set to false for inactive workspaces
    /// so their views (kept alive in a ZStack for state preservation) don't intercept drags
    /// meant for the active workspace.
    @ObservationIgnored var isInteractive: Bool = true {
        didSet { internalController.isInteractive = isInteractive }
    }

    /// Handler for file/URL drops from external apps (e.g., Finder).
    /// Called when files are dropped onto a pane's content area.
    /// Return `true` if the drop was handled.
    @ObservationIgnored var onFileDrop: ((_ urls: [URL], _ paneId: PaneID) -> Bool)? {
        didSet { internalController.onFileDrop = onFileDrop }
    }

    /// Handler for tab drops originating from another WorkspaceSplit controller (e.g. another workspace/window).
    /// Return `true` when the drop has been handled by the host application.
    @ObservationIgnored var onExternalTabDrop: ((ExternalTabDropRequest) -> Bool)?

    /// Called when the user explicitly requests to close a tab from the tab strip UI.
    /// Internal host-driven closes should not use this hook.
    @ObservationIgnored var onTabCloseRequest: ((_ tabId: TabID, _ paneId: PaneID) -> Void)?

    // MARK: - Internal State

    internal var internalController: SplitViewController

    // MARK: - Initialization

    /// Create a new controller with the specified configuration
    init(configuration: WorkspaceSplitConfiguration = .default) {
        self.configuration = configuration
        self.internalController = SplitViewController()
    }

    // MARK: - WorkspaceSplit.Tab Operations

    /// Create a new tab in the focused pane (or specified pane)
    /// - Parameters:
    ///   - title: The tab title
    ///   - icon: Optional SF Symbol name for the tab icon
    ///   - iconImageData: Optional image data (PNG recommended) for the tab icon. When present, takes precedence over `icon`.
    ///   - kind: Consumer-defined tab kind identifier (e.g. "terminal", "browser")
    ///   - hasCustomTitle: Whether the tab title came from a custom user override
    ///   - isDirty: Whether the tab shows a dirty indicator
    ///   - showsNotificationBadge: Whether the tab shows an "unread/activity" badge
    ///   - isLoading: Whether the tab shows an activity/loading indicator (e.g. spinning icon)
    ///   - isPinned: Whether the tab should be treated as pinned
    ///   - pane: Optional pane to add the tab to (defaults to focused pane)
    /// - Returns: The TabID of the created tab, or nil if creation was vetoed by delegate
    @discardableResult
    func createTab(
        title: String,
        hasCustomTitle: Bool = false,
        icon: String? = "doc.text",
        iconImageData: Data? = nil,
        kind: String? = nil,
        isDirty: Bool = false,
        showsNotificationBadge: Bool = false,
        isLoading: Bool = false,
        isPinned: Bool = false,
        inPane pane: PaneID? = nil
    ) -> TabID? {
        let tabId = TabID()
        let tab = WorkspaceSplit.Tab(
            id: tabId,
            title: title,
            hasCustomTitle: hasCustomTitle,
            icon: icon,
            iconImageData: iconImageData,
            kind: kind,
            isDirty: isDirty,
            showsNotificationBadge: showsNotificationBadge,
            isLoading: isLoading,
            isPinned: isPinned
        )
        let targetPane = pane ?? focusedPaneId ?? PaneID(id: internalController.rootNode.allPaneIds.first!.id)

        // Check with delegate
        if delegate?.workspaceSplit(self, shouldCreateTab: tab, inPane: targetPane) == false {
            return nil
        }

        // Calculate insertion index based on configuration
        let insertIndex: Int?
        switch configuration.newTabPosition {
        case .current:
            // Insert after the currently selected tab
            if let paneState = internalController.rootNode.findPane(PaneID(id: targetPane.id)),
               let selectedTabId = paneState.selectedTabId,
               let currentIndex = paneState.tabs.firstIndex(where: { $0.id == selectedTabId }) {
                insertIndex = currentIndex + 1
            } else {
                // No selected tab, append to end
                insertIndex = nil
            }
        case .end:
            insertIndex = nil
        }

        // Create internal TabItem
        let tabItem = TabItem(
            id: tabId.id,
            title: title,
            hasCustomTitle: hasCustomTitle,
            icon: icon,
            iconImageData: iconImageData,
            kind: kind,
            isDirty: isDirty,
            showsNotificationBadge: showsNotificationBadge,
            isLoading: isLoading,
            isPinned: isPinned
        )
        internalController.addTab(tabItem, toPane: PaneID(id: targetPane.id), atIndex: insertIndex)

        // Notify delegate
        delegate?.workspaceSplit(self, didCreateTab: tab, inPane: targetPane)

        return tabId
    }

    /// Request the delegate to create a new tab of the given kind in a pane.
    /// The delegate is responsible for the actual creation logic.
    func requestNewTab(kind: String, inPane pane: PaneID) {
        delegate?.workspaceSplit(self, didRequestNewTab: kind, inPane: pane)
    }

    /// Request the delegate to handle a tab context-menu action.
    func requestTabContextAction(_ action: TabContextAction, for tabId: TabID, inPane pane: PaneID) {
        guard let tab = tab(tabId) else { return }
        delegate?.workspaceSplit(self, didRequestTabContextAction: action, for: tab, inPane: pane)
    }

    /// Update an existing tab's metadata
    /// - Parameters:
    ///   - tabId: The tab to update
    ///   - title: New title (pass nil to keep current)
    ///   - icon: New icon (pass nil to keep current, pass .some(nil) to remove icon)
    ///   - iconImageData: New icon image data (pass nil to keep current, pass .some(nil) to remove)
    ///   - kind: New tab kind (pass nil to keep current, pass .some(nil) to clear)
    ///   - hasCustomTitle: New custom-title state (pass nil to keep current)
    ///   - isDirty: New dirty state (pass nil to keep current)
    ///   - showsNotificationBadge: New badge state (pass nil to keep current)
    ///   - isLoading: New loading/busy state (pass nil to keep current)
    ///   - isPinned: New pinned state (pass nil to keep current)
    func updateTab(
        _ tabId: TabID,
        title: String? = nil,
        icon: String?? = nil,
        iconImageData: Data?? = nil,
        kind: String?? = nil,
        hasCustomTitle: Bool? = nil,
        isDirty: Bool? = nil,
        showsNotificationBadge: Bool? = nil,
        isLoading: Bool? = nil,
        isPinned: Bool? = nil
    ) {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return }

        if let title = title {
            pane.tabs[tabIndex].title = title
        }
        if let icon = icon {
            pane.tabs[tabIndex].icon = icon
        }
        if let iconImageData = iconImageData {
            pane.tabs[tabIndex].iconImageData = iconImageData
        }
        if let kind = kind {
            pane.tabs[tabIndex].kind = kind
        }
        if let hasCustomTitle = hasCustomTitle {
            pane.tabs[tabIndex].hasCustomTitle = hasCustomTitle
        }
        if let isDirty = isDirty {
            pane.tabs[tabIndex].isDirty = isDirty
        }
        if let showsNotificationBadge = showsNotificationBadge {
            pane.tabs[tabIndex].showsNotificationBadge = showsNotificationBadge
        }
        if let isLoading = isLoading {
            pane.tabs[tabIndex].isLoading = isLoading
        }
        if let isPinned = isPinned {
            pane.tabs[tabIndex].isPinned = isPinned
        }
    }

    /// Close a tab by ID
    /// - Parameter tabId: The tab to close
    /// - Returns: true if the tab was closed, false if vetoed by delegate
    @discardableResult
    func closeTab(_ tabId: TabID) -> Bool {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return false }
        return closeTab(tabId, with: tabIndex, in: pane)
    }
    
    /// Close a tab by ID in a specific pane.
    /// - Parameter tabId: The tab to close
    /// - Parameter paneId: The pane in which to close the tab
    func closeTab(_ tabId: TabID, inPane paneId: PaneID) -> Bool {
        guard let pane = internalController.rootNode.findPane(paneId),
              let tabIndex = pane.tabs.firstIndex(where: { $0.id == tabId.id }) else {
            return false
        }
        
        return closeTab(tabId, with: tabIndex, in: pane)
    }
    
    /// Internal helper to close a tab given its index in a pane
    /// - Parameter tabId: The tab to close
    /// - Parameter tabIndex: The position of the tab within the pane
    /// - Parameter pane: The pane in which to close the tab
    private func closeTab(_ tabId: TabID, with tabIndex: Int, in pane: PaneState) -> Bool {
        let tabItem = pane.tabs[tabIndex]
        let tab = WorkspaceSplit.Tab(from: tabItem)
        let paneId = pane.id

        // Check with delegate
        if delegate?.workspaceSplit(self, shouldCloseTab: tab, inPane: paneId) == false {
            return false
        }

        internalController.closeTab(tabId.id, inPane: pane.id)

        // Notify delegate
        delegate?.workspaceSplit(self, didCloseTab: tabId, fromPane: paneId)
        notifyGeometryChange()

        return true
    }

    /// Select a tab by ID
    /// - Parameter tabId: The tab to select
    func selectTab(_ tabId: TabID) {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return }

        pane.selectTab(tabId.id)
        internalController.focusPane(pane.id)

        // Notify delegate
        let tab = WorkspaceSplit.Tab(from: pane.tabs[tabIndex])
        delegate?.workspaceSplit(self, didSelectTab: tab, inPane: pane.id)
    }

    /// Move a tab to a specific pane (and optional index) inside this controller.
    /// - Parameters:
    ///   - tabId: The tab to move.
    ///   - targetPaneId: Destination pane.
    ///   - index: Optional destination index. When nil, appends at the end.
    /// - Returns: true if moved.
    @discardableResult
    func moveTab(_ tabId: TabID, toPane targetPaneId: PaneID, atIndex index: Int? = nil) -> Bool {
        guard let (sourcePane, sourceIndex) = findTabInternal(tabId) else { return false }
        guard let targetPane = internalController.rootNode.findPane(PaneID(id: targetPaneId.id)) else { return false }

        let tabItem = sourcePane.tabs[sourceIndex]
        let movedTab = WorkspaceSplit.Tab(from: tabItem)
        let sourcePaneId = sourcePane.id

        if sourcePaneId == targetPane.id {
            // Reorder within same pane.
            let destinationIndex: Int = {
                if let index { return max(0, min(index, sourcePane.tabs.count)) }
                return sourcePane.tabs.count
            }()
            sourcePane.moveTab(from: sourceIndex, to: destinationIndex)
            sourcePane.selectTab(tabItem.id)
            internalController.focusPane(sourcePane.id)
            delegate?.workspaceSplit(self, didSelectTab: movedTab, inPane: sourcePane.id)
            notifyGeometryChange()
            return true
        }

        internalController.moveTab(tabItem, from: sourcePaneId, to: targetPane.id, atIndex: index)
        delegate?.workspaceSplit(self, didMoveTab: movedTab, fromPane: sourcePaneId, toPane: targetPane.id)
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
        guard let (pane, sourceIndex) = findTabInternal(tabId) else { return false }
        let destinationIndex = max(0, min(toIndex, pane.tabs.count))
        pane.moveTab(from: sourceIndex, to: destinationIndex)
        pane.selectTab(tabId.id)
        internalController.focusPane(pane.id)
        if let tabIndex = pane.tabs.firstIndex(where: { $0.id == tabId.id }) {
            let tab = WorkspaceSplit.Tab(from: pane.tabs[tabIndex])
            delegate?.workspaceSplit(self, didSelectTab: tab, inPane: pane.id)
        }
        notifyGeometryChange()
        return true
    }

    /// Move to previous tab in focused pane
    func selectPreviousTab() {
        internalController.selectPreviousTab()
        notifyTabSelection()
    }

    /// Move to next tab in focused pane
    func selectNextTab() {
        internalController.selectNextTab()
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
        withTab tab: WorkspaceSplit.Tab? = nil
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }

        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId else { return nil }

        // Check with delegate
        if delegate?.workspaceSplit(self, shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        let internalTab: TabItem?
        if let tab {
            internalTab = TabItem(
                id: tab.id.id,
                title: tab.title,
                hasCustomTitle: tab.hasCustomTitle,
                icon: tab.icon,
                iconImageData: tab.iconImageData,
                kind: tab.kind,
                isDirty: tab.isDirty,
                showsNotificationBadge: tab.showsNotificationBadge,
                isLoading: tab.isLoading,
                isPinned: tab.isPinned
            )
        } else {
            internalTab = nil
        }

        // Perform split
        internalController.splitPane(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            with: internalTab
        )

        // Find new pane (will be focused after split)
        let newPaneId = focusedPaneId!

        // Notify delegate
        delegate?.workspaceSplit(self, didSplitPane: targetPaneId, newPane: newPaneId, orientation: orientation)

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
        withTab tab: WorkspaceSplit.Tab,
        insertFirst: Bool
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }

        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId else { return nil }

        // Check with delegate
        if delegate?.workspaceSplit(self, shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        let internalTab = TabItem(
            id: tab.id.id,
            title: tab.title,
            hasCustomTitle: tab.hasCustomTitle,
            icon: tab.icon,
            iconImageData: tab.iconImageData,
            kind: tab.kind,
            isDirty: tab.isDirty,
            showsNotificationBadge: tab.showsNotificationBadge,
            isLoading: tab.isLoading,
            isPinned: tab.isPinned
        )

        // Perform split with insertion side.
        internalController.splitPaneWithTab(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            tab: internalTab,
            insertFirst: insertFirst
        )

        let newPaneId = focusedPaneId!

        // Notify delegate
        delegate?.workspaceSplit(self, didSplitPane: targetPaneId, newPane: newPaneId, orientation: orientation)

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
        insertFirst: Bool
    ) -> PaneID? {
        guard configuration.allowSplits else { return nil }

        // Find the existing tab and its source pane.
        guard let (sourcePane, tabIndex) = findTabInternal(tabId) else { return nil }
        let tabItem = sourcePane.tabs[tabIndex]

        // Default target to the tab's current pane to match edge-drop behavior on the source pane.
        let targetPaneId = paneId ?? sourcePane.id

        // Check with delegate
        if delegate?.workspaceSplit(self, shouldSplitPane: targetPaneId, orientation: orientation) == false {
            return nil
        }

        // Remove from source first.
        sourcePane.removeTab(tabItem.id)

        if sourcePane.tabs.isEmpty {
            if sourcePane.id == targetPaneId {
                // Keep a placeholder tab so the original pane isn't left "tabless".
                // This makes the empty side closable via tab close, and avoids apps
                // needing to special-case empty panes.
                sourcePane.addTab(TabItem(title: "Empty", icon: nil), select: true)
            } else if internalController.rootNode.allPaneIds.count > 1 {
                // If the source pane is now empty, close it (unless it's also the split target).
                internalController.closePane(sourcePane.id)
            }
        }

        // Perform split with the moved tab.
        internalController.splitPaneWithTab(
            PaneID(id: targetPaneId.id),
            orientation: orientation,
            tab: tabItem,
            insertFirst: insertFirst
        )

        let newPaneId = focusedPaneId!

        // Notify delegate
        delegate?.workspaceSplit(self, didSplitPane: targetPaneId, newPane: newPaneId, orientation: orientation)

        notifyGeometryChange()

        return newPaneId
    }

    /// Close a specific pane
    /// - Parameter paneId: The pane to close
    /// - Returns: true if the pane was closed, false if vetoed by delegate
    @discardableResult
    func closePane(_ paneId: PaneID) -> Bool {
        // Don't close if it's the last pane and not allowed
        if !configuration.allowCloseLastPane && internalController.rootNode.allPaneIds.count <= 1 {
            return false
        }

        // Check with delegate
        if delegate?.workspaceSplit(self, shouldClosePane: paneId) == false {
            return false
        }

        internalController.closePane(PaneID(id: paneId.id))

        // Notify delegate
        delegate?.workspaceSplit(self, didClosePane: paneId)

        notifyGeometryChange()

        return true
    }

    // MARK: - Focus Management

    /// Currently focused pane ID
    var focusedPaneId: PaneID? {
        guard let internalId = internalController.focusedPaneId else { return nil }
        return internalId
    }

    /// Focus a specific pane
    func focusPane(_ paneId: PaneID) {
        internalController.focusPane(PaneID(id: paneId.id))
        delegate?.workspaceSplit(self, didFocusPane: paneId)
    }

    /// Navigate focus in a direction
    func navigateFocus(direction: NavigationDirection) {
        internalController.navigateFocus(direction: direction)
        if let focusedPaneId {
            delegate?.workspaceSplit(self, didFocusPane: focusedPaneId)
        }
    }

    /// Find the closest pane in the requested direction from the given pane.
    func adjacentPane(to paneId: PaneID, direction: NavigationDirection) -> PaneID? {
        internalController.adjacentPane(to: paneId, direction: direction)
    }

    // MARK: - Split Zoom

    /// Currently zoomed pane ID, if any.
    var zoomedPaneId: PaneID? {
        internalController.zoomedPaneId
    }

    var isSplitZoomed: Bool {
        internalController.zoomedPaneId != nil
    }

    @discardableResult
    func clearPaneZoom() -> Bool {
        internalController.clearPaneZoom()
    }

    /// Toggle zoom for a pane. When zoomed, only that pane is rendered in the split area.
    /// Passing nil toggles the currently focused pane.
    @discardableResult
    func togglePaneZoom(inPane paneId: PaneID? = nil) -> Bool {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId else { return false }
        return internalController.togglePaneZoom(targetPaneId)
    }

    // MARK: - Context Menu Shortcut Hints

    /// Keyboard shortcuts to display in tab context menus, keyed by context action.
    /// Set by the host app to sync with its customizable keyboard shortcut settings.
    var contextMenuShortcuts: [TabContextAction: KeyboardShortcut] = [:]

    // MARK: - Query Methods

    /// Get all tab IDs
    var allTabIds: [TabID] {
        internalController.rootNode.allPanes.flatMap { pane in
            pane.tabs.map { TabID(id: $0.id) }
        }
    }

    /// Get all pane IDs
    var allPaneIds: [PaneID] {
        internalController.rootNode.allPaneIds
    }

    /// Get tab metadata by ID
    func tab(_ tabId: TabID) -> WorkspaceSplit.Tab? {
        guard let (pane, tabIndex) = findTabInternal(tabId) else { return nil }
        return WorkspaceSplit.Tab(from: pane.tabs[tabIndex])
    }

    /// Get tabs in a specific pane
    func tabs(inPane paneId: PaneID) -> [WorkspaceSplit.Tab] {
        guard let pane = internalController.rootNode.findPane(PaneID(id: paneId.id)) else {
            return []
        }
        return pane.tabs.map { WorkspaceSplit.Tab(from: $0) }
    }

    /// Get selected tab in a pane
    func selectedTab(inPane paneId: PaneID) -> WorkspaceSplit.Tab? {
        guard let pane = internalController.rootNode.findPane(PaneID(id: paneId.id)),
              let selected = pane.selectedTab else {
            return nil
        }
        return WorkspaceSplit.Tab(from: selected)
    }

    // MARK: - Geometry Query API

    /// Get current layout snapshot with pixel coordinates
    func layoutSnapshot() -> LayoutSnapshot {
        let containerFrame = internalController.containerFrame
        let paneBounds = internalController.rootNode.computePaneBounds()

        let paneGeometries = paneBounds.map { bounds -> PaneGeometry in
            let pane = internalController.rootNode.findPane(bounds.paneId)
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
                tabIds: pane?.tabs.map { $0.id.uuidString } ?? []
            )
        }

        return LayoutSnapshot(
            containerFrame: PixelRect(from: containerFrame),
            panes: paneGeometries,
            focusedPaneId: focusedPaneId?.id.uuidString,
            timestamp: Date().timeIntervalSince1970
        )
    }

    /// Get full tree structure for external consumption
    func treeSnapshot() -> ExternalTreeNode {
        let containerFrame = internalController.containerFrame
        return buildExternalTree(from: internalController.rootNode, containerFrame: containerFrame)
    }

    private func buildExternalTree(from node: SplitNode, containerFrame: CGRect, bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> ExternalTreeNode {
        switch node {
        case .pane(let paneState):
            let pixelFrame = PixelRect(
                x: Double(bounds.minX * containerFrame.width + containerFrame.origin.x),
                y: Double(bounds.minY * containerFrame.height + containerFrame.origin.y),
                width: Double(bounds.width * containerFrame.width),
                height: Double(bounds.height * containerFrame.height)
            )
            let tabs = paneState.tabs.map { ExternalTab(id: $0.id.uuidString, title: $0.title) }
            let paneNode = ExternalPaneNode(
                id: paneState.id.id.uuidString,
                frame: pixelFrame,
                tabs: tabs,
                selectedTabId: paneState.selectedTabId?.uuidString
            )
            return .pane(paneNode)

        case .split(let splitState):
            let dividerPos = splitState.dividerPosition
            let firstBounds: CGRect
            let secondBounds: CGRect

            switch splitState.orientation {
            case .horizontal:
                firstBounds = CGRect(x: bounds.minX, y: bounds.minY,
                                     width: bounds.width * dividerPos, height: bounds.height)
                secondBounds = CGRect(x: bounds.minX + bounds.width * dividerPos, y: bounds.minY,
                                      width: bounds.width * (1 - dividerPos), height: bounds.height)
            case .vertical:
                firstBounds = CGRect(x: bounds.minX, y: bounds.minY,
                                     width: bounds.width, height: bounds.height * dividerPos)
                secondBounds = CGRect(x: bounds.minX, y: bounds.minY + bounds.height * dividerPos,
                                      width: bounds.width, height: bounds.height * (1 - dividerPos))
            }

            let splitNode = ExternalSplitNode(
                id: splitState.id.uuidString,
                orientation: splitState.orientation == .horizontal ? "horizontal" : "vertical",
                dividerPosition: Double(splitState.dividerPosition),
                first: buildExternalTree(from: splitState.first, containerFrame: containerFrame, bounds: firstBounds),
                second: buildExternalTree(from: splitState.second, containerFrame: containerFrame, bounds: secondBounds)
            )
            return .split(splitNode)
        }
    }

    /// Check if a split exists by ID
    func findSplit(_ splitId: UUID) -> Bool {
        return internalController.findSplit(splitId) != nil
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
        guard let split = internalController.findSplit(splitId) else { return false }

        if fromExternal {
            internalController.isExternalUpdateInProgress = true
        }

        // Clamp position to valid range
        let clampedPosition = min(max(position, 0.1), 0.9)
        split.dividerPosition = clampedPosition

        if fromExternal {
            // Use a slight delay to allow the UI to update before re-enabling notifications
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.internalController.isExternalUpdateInProgress = false
            }
        }

        return true
    }

    /// Update container frame (called when window moves/resizes)
    func setContainerFrame(_ frame: CGRect) {
        internalController.containerFrame = frame
    }

    /// Notify geometry change to delegate (internal use)
    /// - Parameter isDragging: Whether the change is due to active divider dragging
    internal func notifyGeometryChange(isDragging: Bool = false) {
        guard !internalController.isExternalUpdateInProgress else { return }

        // If dragging, check if delegate wants notifications during drag
        if isDragging {
            let shouldNotify = delegate?.workspaceSplit(self, shouldNotifyDuringDrag: true) ?? false
            guard shouldNotify else { return }
        }

        if isDragging {
            // Debounce drag updates to avoid flooding delegates during divider moves.
            let now = Date().timeIntervalSince1970
            let debounceInterval: TimeInterval = 0.05
            guard now - internalController.lastGeometryNotificationTime >= debounceInterval else { return }
            internalController.lastGeometryNotificationTime = now
        }

        let snapshot = layoutSnapshot()
        delegate?.workspaceSplit(self, didChangeGeometry: snapshot)
    }

    // MARK: - Private Helpers

    private func findTabInternal(_ tabId: TabID) -> (PaneState, Int)? {
        for pane in internalController.rootNode.allPanes {
            if let index = pane.tabs.firstIndex(where: { $0.id == tabId.id }) {
                return (pane, index)
            }
        }
        return nil
    }

    private func notifyTabSelection() {
        guard let pane = internalController.focusedPane,
              let tabItem = pane.selectedTab else { return }
        let tab = WorkspaceSplit.Tab(from: tabItem)
        delegate?.workspaceSplit(self, didSelectTab: tab, inPane: pane.id)
    }
}

import SwiftUI

/// Main entry point for the WorkspaceSplit library
///
/// Usage:
/// ```swift
/// struct MyApp: View {
///     @State private var controller = WorkspaceSplitController()
///
///     var body: some View {
///         WorkspaceSplitView(controller: controller) { tab, paneId in
///             MyContentView(for: tab)
///                 .onTapGesture { controller.focusPane(paneId) }
///         } emptyPane: { paneId in
///             Text("Empty pane")
///         }
///     }
/// }
/// ```
struct WorkspaceSplitView<Content: View, EmptyContent: View>: View {
    @Bindable private var controller: WorkspaceSplitController
    private let contentBuilder: (WorkspaceSplit.Tab, PaneID) -> Content
    private let emptyPaneBuilder: (PaneID) -> EmptyContent
    private let nativeContentBuilder: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)?

    /// Initialize with a controller, content builder, and empty pane builder
    /// - Parameters:
    ///   - controller: The WorkspaceSplitController managing the tab state
    ///   - content: A ViewBuilder closure that provides content for each tab. Receives the tab and pane ID.
    ///   - emptyPane: A ViewBuilder closure that provides content for empty panes
    init(
        controller: WorkspaceSplitController,
        nativeContent: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)? = nil,
        @ViewBuilder content: @escaping (WorkspaceSplit.Tab, PaneID) -> Content,
        @ViewBuilder emptyPane: @escaping (PaneID) -> EmptyContent
    ) {
        self.controller = controller
        self.nativeContentBuilder = nativeContent
        self.contentBuilder = content
        self.emptyPaneBuilder = emptyPane
    }

    var body: some View {
        WorkspaceSplitNativeHost(
            controller: controller,
            nativeContent: nativeContentBuilder,
            content: contentBuilder,
            emptyPane: emptyPaneBuilder,
            showSplitButtons: controller.configuration.allowSplits && controller.configuration.appearance.showSplitButtons,
            contentViewLifecycle: controller.configuration.contentViewLifecycle,
            onGeometryChange: { [weak controller] isDragging in
                controller?.notifyGeometryChange(isDragging: isDragging)
            }
        )
    }
}

// MARK: - Convenience initializer with default empty view

extension WorkspaceSplitView where EmptyContent == DefaultEmptyPaneView {
    /// Initialize with a controller and content builder, using the default empty pane view
    /// - Parameters:
    ///   - controller: The WorkspaceSplitController managing the tab state
    ///   - content: A ViewBuilder closure that provides content for each tab. Receives the tab and pane ID.
    init(
        controller: WorkspaceSplitController,
        nativeContent: ((WorkspaceSplit.Tab, PaneID) -> WorkspaceNativePaneContent?)? = nil,
        @ViewBuilder content: @escaping (WorkspaceSplit.Tab, PaneID) -> Content
    ) {
        self.controller = controller
        self.nativeContentBuilder = nativeContent
        self.contentBuilder = content
        self.emptyPaneBuilder = { _ in DefaultEmptyPaneView() }
    }
}

@MainActor
enum WorkspaceNativePaneContent {
    case terminal(WorkspaceTerminalPaneContent)
}

extension WorkspaceNativePaneContent {
    var prefersNativeDropOverlay: Bool {
        switch self {
        case .terminal:
            true
        }
    }
}

extension WorkspaceSplit.Tab {
    var prefersNativeDropOverlay: Bool {
        switch kind {
        case "browser":
            true
        default:
            false
        }
    }
}

@MainActor
struct WorkspaceTerminalPaneContent {
    let panel: TerminalPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let onFocus: () -> Void
    let onTriggerFlash: () -> Void
}

/// Default view shown when a pane has no tabs
struct DefaultEmptyPaneView: View {
    init() {}

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Open Tabs")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
