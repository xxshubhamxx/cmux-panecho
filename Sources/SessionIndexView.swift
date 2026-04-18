import AppKit
import Bonsplit
import SwiftUI
import UniformTypeIdentifiers

struct SessionIndexView: View {
    @ObservedObject var store: SessionIndexStore
    /// Lives alongside the store but is owned by this view so drag-state
    /// transitions don't invalidate data-subscribed views elsewhere in the
    /// sidebar.
    @StateObject private var dragCoordinator = SessionDragCoordinator()
    /// Sections the user has explicitly collapsed (default is expanded).
    @State private var collapsedSections: Set<SectionKey> = []
    /// Section whose "Show more" popover is currently open.
    @State private var openPopoverSection: SectionKey? = nil
    let onResume: ((SessionEntry) -> Void)?

    /// Rows shown per section before "Show more" is tapped.
    private static let collapsedRowLimit = 5

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if store.isLoading && store.entries.isEmpty {
                loadingView
            } else if store.entries.isEmpty {
                emptyView
            } else {
                sessionsList
            }
        }
        .onAppear {
            // RightSidebarPanelView's mode toggle also kicks reload() when
            // entries are empty, so guard against the double-reload that
            // would otherwise cancel and restart the in-flight scan.
            if store.entries.isEmpty && !store.isLoading {
                store.reload()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            ForEach(SessionGrouping.allCases) { mode in
                GroupingButton(
                    mode: mode,
                    isSelected: store.grouping == mode
                ) {
                    if store.grouping != mode {
                        store.grouping = mode
                    }
                }
            }

            Spacer(minLength: 4)

            Toggle(isOn: $store.scopeToCurrentDirectory) {
                Text(String(localized: "sessionIndex.scope.thisFolder", defaultValue: "This folder only"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(store.currentDirectory == nil)

            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "sessionIndex.reload.tooltip", defaultValue: "Reload sessions"))
            .disabled(store.isLoading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 29)
    }

    private var loadingView: some View {
        VStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(String(localized: "sessionIndex.loading", defaultValue: "Scanning sessions…"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Text(String(localized: "sessionIndex.empty.title", defaultValue: "No sessions found"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(String(localized: "sessionIndex.empty.subtitle",
                                   defaultValue: "Sessions from Claude Code, Codex, and OpenCode will appear here."))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionsList: some View {
        let sections = store.sectionsForCurrentGrouping()
        // Read draggedKey once per body eval so every child gets a snapshot
        // of the same value. Children are Equatable value views, so a
        // draggedKey transition only re-renders the two sections whose
        // isDragged flipped — not every section.
        let draggedKey = dragCoordinator.draggedKey
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.key) { index, section in
                    // Drop above this row → insert dragged section BEFORE this section's key.
                    SectionReorderGap(
                        beforeKey: section.key,
                        isValidDrop: draggedKey == nil || draggedKey != section.key,
                        store: store,
                        dragCoordinator: dragCoordinator
                    ).equatable()
                    IndexSectionView(
                        section: section,
                        rowLimit: Self.collapsedRowLimit,
                        isDragged: draggedKey == section.key,
                        isCollapsed: Binding(
                            get: { collapsedSections.contains(section.key) },
                            set: { newValue in
                                if newValue {
                                    collapsedSections.insert(section.key)
                                } else {
                                    collapsedSections.remove(section.key)
                                }
                            }
                        ),
                        isPopoverOpen: Binding(
                            get: { openPopoverSection == section.key },
                            set: { newValue in
                                openPopoverSection = newValue ? section.key : nil
                            }
                        ),
                        store: store,
                        dragCoordinator: dragCoordinator,
                        onResume: onResume
                    ).equatable()
                    let _ = index
                }
                // Trailing gap → append.
                SectionReorderGap(
                    beforeKey: nil,
                    isValidDrop: true,
                    store: store,
                    dragCoordinator: dragCoordinator
                ).equatable()
            }
            .padding(.bottom, 8)
        }
        .background(
            DragCancelMonitor(dragCoordinator: dragCoordinator)
        )
    }
}

private struct GroupingButton: View {
    let mode: SessionGrouping
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 10, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.10)
                          : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(mode.label)
    }
}

private struct IndexSectionView: View, Equatable {
    let section: IndexSection
    let rowLimit: Int
    /// True iff this section is the one currently being dragged. Precomputed
    /// in the parent from a single `draggedKey` snapshot so the section's
    /// opacity fade doesn't require observing the drag coordinator here.
    let isDragged: Bool
    @Binding var isCollapsed: Bool
    @Binding var isPopoverOpen: Bool
    /// Plain (non-observing) reference used only for passing through to the
    /// popover host and for the section drag's `onDrag` callback writing the
    /// dragged key into `dragCoordinator`. Reads that would trigger view
    /// invalidation are intentionally absent.
    let store: SessionIndexStore
    let dragCoordinator: SessionDragCoordinator
    let onResume: ((SessionEntry) -> Void)?

    /// Skip body re-eval when this view's inputs are unchanged. `store` and
    /// `dragCoordinator` identities are stable per-panel so they aren't part
    /// of `==`; `onResume` is not comparable but is stable from the parent
    /// chain. This is the core optimization that keeps LazyVStack's layout
    /// cache from thrashing when unrelated store fields change.
    static func == (lhs: IndexSectionView, rhs: IndexSectionView) -> Bool {
        lhs.section == rhs.section
            && lhs.rowLimit == rhs.rowLimit
            && lhs.isDragged == rhs.isDragged
            && lhs.isCollapsed == rhs.isCollapsed
            && lhs.isPopoverOpen == rhs.isPopoverOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if !isCollapsed {
                if section.entries.isEmpty {
                    Text(String(localized: "sessionIndex.section.noChats", defaultValue: "No chats"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.leading, 32)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(section.entries.prefix(rowLimit))) { entry in
                        SessionRow(entry: entry, onResume: onResume)
                            .equatable()
                    }
                    if section.entries.count > rowLimit {
                        showMoreButton
                    }
                }
                Spacer(minLength: 2)
            }
        }
        .opacity(isDragged ? 0.45 : 1.0)
    }

    private var showMoreButton: some View {
        Button {
            isPopoverOpen = true
        } label: {
            Text(String(localized: "sessionIndex.section.showMore", defaultValue: "Show more"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.leading, 32)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            SectionPopoverHost(
                isPresented: $isPopoverOpen,
                section: section,
                store: store,
                onResume: onResume
            )
        )
    }

    private var sectionHeader: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            HStack(spacing: 8) {
                sectionIconView
                Text(section.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            DispatchQueue.main.async { [dragCoordinator, section] in
                dragCoordinator.draggedKey = section.key
            }
            return NSItemProvider(object: section.key.raw as NSString)
        } preview: {
            HStack(spacing: 8) {
                sectionIconView
                Text(section.title)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private var sectionIconView: some View {
        switch section.icon {
        case .agent(let agent):
            Image(agent.assetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        case .folder:
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 14, height: 14)
        }
    }
}

private struct SectionReorderGap: View, Equatable {
    /// Section the dragged item should land BEFORE if dropped here. `nil` for
    /// the trailing gap (drop appends to the end of persisted order).
    let beforeKey: SectionKey?
    /// Precomputed in the parent from the single draggedKey snapshot. Keeps
    /// the gap from reading drag state itself.
    let isValidDrop: Bool
    /// Plain references. `store` for `moveSection`; `dragCoordinator` so the
    /// drop delegate can clear the dragged key when the drop completes.
    let store: SessionIndexStore
    let dragCoordinator: SessionDragCoordinator
    @State private var isDropTarget: Bool = false

    static func == (lhs: SectionReorderGap, rhs: SectionReorderGap) -> Bool {
        lhs.beforeKey == rhs.beforeKey && lhs.isValidDrop == rhs.isValidDrop
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 4)
            .overlay(alignment: .center) {
                if isDropTarget && isValidDrop {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 3)
                        .padding(.horizontal, 10)
                }
            }
            .onDrop(
                of: [.text],
                delegate: SectionGapDropDelegate(
                    beforeKey: beforeKey,
                    store: store,
                    dragCoordinator: dragCoordinator,
                    isDropTarget: $isDropTarget
                )
            )
    }
}

private struct SectionGapDropDelegate: DropDelegate {
    let beforeKey: SectionKey?
    let store: SessionIndexStore
    let dragCoordinator: SessionDragCoordinator
    @Binding var isDropTarget: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.text]) else { return false }
        guard let dragged = dragCoordinator.draggedKey else { return true }
        return dragged != beforeKey
    }

    func dropEntered(info: DropInfo) { isDropTarget = true }
    func dropExited(info: DropInfo) { isDropTarget = false }

    func performDrop(info: DropInfo) -> Bool {
        isDropTarget = false
        guard let provider = info.itemProviders(for: [.text]).first else {
            dragCoordinator.draggedKey = nil
            return false
        }
        let beforeKey = self.beforeKey
        let store = self.store
        let dragCoordinator = self.dragCoordinator
        provider.loadObject(ofClass: NSString.self) { object, _ in
            DispatchQueue.main.async {
                defer { dragCoordinator.draggedKey = nil }
                guard let raw = object as? String else { return }
                let key = SectionKey(raw: raw)
                store.moveSection(key, before: beforeKey)
            }
        }
        return true
    }
}

private struct SessionRow: View, Equatable {
    let entry: SessionEntry
    let onResume: ((SessionEntry) -> Void)?
    @State private var isHovered: Bool = false

    static func == (lhs: SessionRow, rhs: SessionRow) -> Bool {
        // Skip body re-eval during scroll when the entry is unchanged.
        // The closure isn't compared (it comes from stable parent state).
        lhs.entry == rhs.entry
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(entry.agent.assetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
            Text(entry.displayTitle)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(relativeTime(entry.modified))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.secondary.opacity(0.65))
                .fixedSize()
        }
        .padding(.leading, 32)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 6)
        )
        .onHover { isHovered = $0 }
        .help(helpText)
        .onTapGesture(count: 2) {
            if let onResume { onResume(entry) }
        }
        .onDrag {
            sessionDragItemProvider(for: entry)
        } preview: {
            HStack(spacing: 6) {
                Image(entry.agent.assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                Text(entry.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .contextMenu {
            sessionRowMenuItems(entry: entry, onResume: onResume)
        }
    }

    private var helpText: String {
        var lines: [String] = [entry.displayTitle]
        if let cwd = entry.cwdLabel {
            lines.append(cwd)
        }
        lines.append(absoluteTime(entry.modified))
        return lines.joined(separator: "\n")
    }

    private func relativeTime(_ date: Date) -> String {
        SessionIndexView.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func absoluteTime(_ date: Date) -> String {
        SessionIndexView.absoluteFormatter.string(from: date)
    }
}

// MARK: - Shared row actions

/// Right-click menu items for any session row (full or popover). Built as a
/// free `@ViewBuilder` so SessionRow and PopoverRow both attach the same set
/// without duplicating the button list or the action helpers.
@ViewBuilder
private func sessionRowMenuItems(entry: SessionEntry, onResume: ((SessionEntry) -> Void)?) -> some View {
    if let onResume {
        Button {
            onResume(entry)
        } label: {
            Text(String(localized: "sessionIndex.row.resume", defaultValue: "Resume in New Tab"))
        }
        Divider()
    }
    if let url = entry.fileURL {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text(String(localized: "sessionIndex.row.open", defaultValue: "Open"))
        }
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Text(String(localized: "sessionIndex.row.reveal", defaultValue: "Reveal in Finder"))
        }
        Divider()
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(url.path, forType: .string)
        } label: {
            Text(String(localized: "sessionIndex.row.copyPath", defaultValue: "Copy File Path"))
        }
    }
    Button {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.resumeCommand, forType: .string)
    } label: {
        Text(String(localized: "sessionIndex.row.copyResume", defaultValue: "Copy Resume Command"))
    }
    if let cwd = entry.cwd, !cwd.isEmpty {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
        } label: {
            Text(String(localized: "sessionIndex.row.openCwd", defaultValue: "Open Working Directory"))
        }
    }
    if let pr = entry.pullRequest, let url = URL(string: pr.url) {
        Divider()
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text(String(localized: "sessionIndex.row.openPR", defaultValue: "Open Pull Request"))
        }
    }
}


// MARK: - Drag payload

/// Mirrors `Bonsplit.TabItem`'s Codable shape so we can produce a JSON payload
/// that bonsplit's external-drop path will decode and accept.
private struct MirrorTabItem: Codable {
    let id: UUID
    let title: String
    let hasCustomTitle: Bool
    let icon: String?
    let iconImageData: Data?
    let kind: String?
    let isDirty: Bool
    let showsNotificationBadge: Bool
    let isLoading: Bool
    let isPinned: Bool
}

/// Mirrors `Bonsplit.TabTransferData` exactly.
private struct MirrorTabTransferData: Codable {
    let tab: MirrorTabItem
    let sourcePaneId: UUID
    let sourceProcessId: Int32
}

/// Build the encoded payload bonsplit's external-drop decoder accepts.
private func sessionTabTransferData(for entry: SessionEntry, dragId: UUID) -> Data? {
    let mirror = MirrorTabTransferData(
        tab: MirrorTabItem(
            id: dragId,
            title: entry.displayTitle,
            hasCustomTitle: false,
            icon: "terminal.fill",
            iconImageData: nil,
            kind: "terminal",
            isDirty: false,
            showsNotificationBadge: false,
            isLoading: false,
            isPinned: false
        ),
        sourcePaneId: UUID(),
        sourceProcessId: Int32(ProcessInfo.processInfo.processIdentifier)
    )
    return try? JSONEncoder().encode(mirror)
}

/// NSItemProvider used by `.onDrag {}`. Registers ONLY
/// `com.splittabbar.tabtransfer` so the terminal's NSDraggingDestination
/// (which accepts `.string` / `public.utf8-plain-text`) is not hit-tested
/// for our drag. With the terminal out of the way, bonsplit's SwiftUI
/// `.onDrop(of: [.tabTransfer])` overlay can render the blue insert/split
/// zones across the entire pane (including its center).
///
/// Also mirrors the encoded blob onto NSPasteboard(name: .drag) since
/// bonsplit's external-drop decoder reads from that pasteboard directly
/// and SwiftUI's NSItemProvider bridge doesn't always surface custom
/// UTTypes there reliably.
private func sessionDragItemProvider(for entry: SessionEntry) -> NSItemProvider {
    let dragId = SessionDragRegistry.shared.register(entry)
    let provider = NSItemProvider()

    if let data = sessionTabTransferData(for: entry, dragId: dragId) {
        provider.registerDataRepresentation(
            forTypeIdentifier: "com.splittabbar.tabtransfer",
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        DispatchQueue.main.async {
            let pb = NSPasteboard(name: .drag)
            let type = NSPasteboard.PasteboardType("com.splittabbar.tabtransfer")
            pb.addTypes([type], owner: nil)
            pb.setData(data, forType: type)
        }
    }

    provider.suggestedName = entry.displayTitle
    return provider
}

// MARK: - Show-more popover (AppKit)

/// Anchors an NSPopover hosting `SessionSearchPopoverController`. The popover
/// is pure AppKit — NSSearchField + NSScrollView + NSTableView — so we get
/// honest virtualization, native scroll-based pagination triggers, and
/// AppKit's own size propagation into NSPopover instead of SwiftUI's
/// LazyVStack layout-cache heuristics.
private struct SectionPopoverHost: NSViewRepresentable {
    @Binding var isPresented: Bool
    let section: IndexSection
    let store: SessionIndexStore
    let onResume: ((SessionEntry) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.anchorView = nsView
        coordinator.section = section
        coordinator.store = store
        coordinator.onResume = onResume
        if isPresented {
            coordinator.present()
        } else {
            coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        @Binding var isPresented: Bool
        weak var anchorView: NSView?
        var section: IndexSection?
        var store: SessionIndexStore?
        var onResume: ((SessionEntry) -> Void)?

        private var popover: NSPopover?

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func present() {
            guard let anchorView, anchorView.window != nil,
                  let section, let store else {
                isPresented = false
                return
            }
            if let existing = popover, existing.isShown { return }
            let controller = SessionSearchPopoverController(section: section, store: store)
            controller.onResume = onResume
            controller.onDismiss = { [weak self] in
                guard let self else { return }
                self.isPresented = false
                self.popover?.performClose(nil)
            }
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true
            p.contentViewController = controller
            p.delegate = self
            self.popover = p
            p.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
        }

        func dismiss() {
            popover?.performClose(nil)
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            if isPresented {
                isPresented = false
            }
        }
    }
}

/// NSViewController hosted in the Show-more NSPopover.
///
/// Behaviour parity with the previous SwiftUI implementation:
/// - Empty query: instantly shows `section.entries` (no spinner flash).
/// - Non-empty query: 150 ms debounce then hits `store.searchSessions`.
/// - Pagination: next page fetched when the visible rect nears the end of
///   the table. NSTableView handles virtualization natively — the row views
///   are cached and reused regardless of how far the list grows.
/// - Escape dismisses via `cancelOperation(_:)` on the container view.
/// - Rows support double-click to resume, drag-out to a terminal pane
///   (`com.splittabbar.tabtransfer`), and a right-click context menu.
private final class SessionSearchPopoverController: NSViewController, NSMenuDelegate {
    var onResume: ((SessionEntry) -> Void)?
    var onDismiss: (() -> Void)?

    private let store: SessionIndexStore
    private let section: IndexSection

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerIcon = NSImageView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")

    private var loaded: [SessionEntry] = []
    private var hasMore: Bool = false
    private var isLoading: Bool = false
    private var activeQuery: String = ""
    private var loadGeneration: Int = 0
    private var currentTask: Task<Void, Never>?
    private var debounceWorkItem: DispatchWorkItem?
    /// The scroll view's dynamic height. Updated each time the result list
    /// changes so the popover shrinks to fit short lists and caps at
    /// `maxScrollHeight` for long ones.
    private var scrollHeightConstraint: NSLayoutConstraint!

    private static let pageSize = 30
    private static let rowHeight: CGFloat = 28
    private static let maxScrollHeight: CGFloat = 420

    init(section: IndexSection, store: SessionIndexStore) {
        self.section = section
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let root = EscapeDismissView()
        root.onEscape = { [weak self] in self?.onDismiss?() }
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHeader()
        configureSearch()
        configureTable()
        configureErrorLabel()
        configureEmptyLabel()
        layoutSubviews()
        resetAndLoad(query: "")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    private func configureHeader() {
        switch section.icon {
        case .agent(let agent):
            headerIcon.image = NSImage(named: agent.assetName)
        case .folder:
            headerIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            headerIcon.contentTintColor = .secondaryLabelColor
        }
        headerIcon.imageScaling = .scaleProportionallyUpOrDown

        headerLabel.stringValue = section.title
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.lineBreakMode = .byTruncatingMiddle
        headerLabel.maximumNumberOfLines = 1
    }

    private func configureSearch() {
        searchField.placeholderString = String(localized: "sessionIndex.popover.searchPlaceholder",
                                               defaultValue: "Search sessions")
        searchField.font = .systemFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(searchQueryChanged(_:))
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = false
    }

    private func configureTable() {
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = Self.rowHeight
        tableView.rowSizeStyle = .custom
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.target = self

        let rowMenu = NSMenu()
        rowMenu.delegate = self
        tableView.menu = rowMenu

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        col.resizingMask = [.autoresizingMask]
        tableView.addTableColumn(col)

        tableView.dataSource = self
        tableView.delegate = self

        tableView.setDraggingSourceOperationMask([.copy, .generic], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollContentDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    private func configureErrorLabel() {
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .labelColor
        errorLabel.isHidden = true
    }

    private func configureEmptyLabel() {
        emptyLabel.stringValue = String(localized: "sessionIndex.popover.noMatches",
                                        defaultValue: "No matches")
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true
    }

    private func layoutSubviews() {
        let headerStack = NSStackView(views: [headerIcon, headerLabel])
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .centerY
        headerStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 6, right: 12)

        let searchContainer = NSView()
        searchContainer.addSubview(searchField)

        let divider = NSBox()
        divider.boxType = .separator

        let vstack = NSStackView(views: [headerStack, searchContainer, divider, errorLabel, emptyLabel, scrollView])
        vstack.orientation = .vertical
        vstack.spacing = 0
        vstack.alignment = .leading
        vstack.distribution = .fill
        vstack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vstack)

        for subview in [headerIcon, headerLabel, searchField, errorLabel, emptyLabel, scrollView, searchContainer] {
            (subview as NSView).translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            vstack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vstack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vstack.topAnchor.constraint(equalTo: view.topAnchor),
            vstack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerIcon.widthAnchor.constraint(equalToConstant: 14),
            headerIcon.heightAnchor.constraint(equalToConstant: 14),

            headerStack.leadingAnchor.constraint(equalTo: vstack.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: vstack.trailingAnchor),

            searchContainer.leadingAnchor.constraint(equalTo: vstack.leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: vstack.trailingAnchor),

            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor, constant: 0),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: -8),

            divider.leadingAnchor.constraint(equalTo: vstack.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: vstack.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            errorLabel.leadingAnchor.constraint(equalTo: vstack.leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: vstack.trailingAnchor, constant: -12),

            emptyLabel.leadingAnchor.constraint(equalTo: vstack.leadingAnchor, constant: 12),
            emptyLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),

            scrollView.leadingAnchor.constraint(equalTo: vstack.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: vstack.trailingAnchor),

            view.widthAnchor.constraint(equalToConstant: 360),
        ])

        // Mutable height: starts tall enough for one row so the initial
        // `fittingSize` is sane even before the first reload. The real
        // value is recomputed in `updatePopoverSize()` after every content
        // state change.
        scrollHeightConstraint = scrollView.heightAnchor.constraint(
            equalToConstant: Self.rowHeight
        )
        scrollHeightConstraint.isActive = true
    }

    // MARK: Search / pagination

    @objc private func searchQueryChanged(_ sender: NSSearchField) {
        let q = sender.stringValue
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resetAndLoad(query: q) }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func resetAndLoad(query: String) {
        currentTask?.cancel()
        loadGeneration += 1
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeQuery = trimmed
        errorLabel.isHidden = true

        if trimmed.isEmpty {
            loaded = section.entries
            // Assume there may be more on disk; loadMore flips hasMore off
            // once a fetch returns fewer than pageSize rows.
            hasMore = !section.entries.isEmpty
            isLoading = false
            reloadAndRefresh()
            return
        }

        loaded = []
        hasMore = true
        isLoading = true
        reloadAndRefresh()
        let scope = sectionSearchScope
        let store = self.store
        let generation = loadGeneration
        currentTask = Task { @MainActor [weak self] in
            let outcome = await store.searchSessions(
                query: trimmed, scope: scope,
                offset: 0, limit: Self.pageSize
            )
            guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
            self.applyOutcome(outcome, append: false)
        }
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        let generation = loadGeneration
        let scope = sectionSearchScope
        let store = self.store
        let query = activeQuery
        let offset = loaded.count
        currentTask = Task { @MainActor [weak self] in
            let outcome = await store.searchSessions(
                query: query, scope: scope,
                offset: offset, limit: Self.pageSize
            )
            guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
            self.applyOutcome(outcome, append: true)
        }
    }

    @MainActor
    private func applyOutcome(_ outcome: SessionIndexStore.SearchOutcome, append: Bool) {
        if append {
            loaded.append(contentsOf: outcome.entries)
        } else {
            loaded = outcome.entries
        }
        hasMore = outcome.entries.count >= Self.pageSize
        isLoading = false
        if outcome.errors.isEmpty {
            errorLabel.isHidden = true
        } else {
            errorLabel.stringValue = outcome.errors.joined(separator: "\n")
            errorLabel.isHidden = false
        }
        reloadAndRefresh()
    }

    private func reloadAndRefresh() {
        // Show "No matches" only once a fetch finished and returned nothing.
        emptyLabel.isHidden = isLoading || !loaded.isEmpty
        tableView.reloadData()
        updatePopoverSize()
    }

    /// Single owner of popover vertical size. NSScrollView will not propagate
    /// its document view's content height upward, so the controller has to
    /// drive it — derive the desired scroll height from the row count,
    /// clamp to `maxScrollHeight`, then publish via `preferredContentSize`
    /// so NSPopover animates to the new size.
    private func updatePopoverSize() {
        let rows = max(1, loaded.count)
        let desired = CGFloat(rows) * Self.rowHeight
        scrollHeightConstraint.constant = min(desired, Self.maxScrollHeight)
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    private var sectionSearchScope: SessionIndexStore.SearchScope {
        let raw = section.key.raw
        if raw.hasPrefix("agent:"),
           let agent = SessionAgent(rawValue: String(raw.dropFirst("agent:".count))) {
            return .agent(agent)
        }
        if raw.hasPrefix("dir:") {
            let path = String(raw.dropFirst("dir:".count))
            return .directory(path.isEmpty ? nil : path)
        }
        return .directory(nil)
    }

    // MARK: Scroll-driven pagination

    @objc private func scrollContentDidChange(_ note: Notification) {
        guard hasMore, !isLoading else { return }
        let visible = scrollView.contentView.bounds
        let contentHeight = tableView.bounds.height
        // Trigger when within two row-heights of the bottom.
        if visible.maxY >= contentHeight - Self.rowHeight * 2 {
            loadMore()
        }
    }

    // MARK: Row actions

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < loaded.count else { return }
        let entry = loaded[row]
        onResume?(entry)
        onDismiss?()
    }

    // MARK: NSMenuDelegate (right-click context menu)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < loaded.count else { return }
        let entry = loaded[row]

        menu.addItem(makeMenuItem(
            title: String(localized: "sessionIndex.row.resume", defaultValue: "Resume in New Tab")
        ) { [weak self] in
            self?.onResume?(entry)
            self?.onDismiss?()
        })
        menu.addItem(.separator())
        if let url = entry.fileURL {
            menu.addItem(makeMenuItem(
                title: String(localized: "sessionIndex.row.open", defaultValue: "Open")
            ) {
                NSWorkspace.shared.open(url)
            })
            menu.addItem(makeMenuItem(
                title: String(localized: "sessionIndex.row.reveal", defaultValue: "Reveal in Finder")
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(
                title: String(localized: "sessionIndex.row.copyPath", defaultValue: "Copy File Path")
            ) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(url.path, forType: .string)
            })
        }
        menu.addItem(makeMenuItem(
            title: String(localized: "sessionIndex.row.copyResume", defaultValue: "Copy Resume Command")
        ) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(entry.resumeCommand, forType: .string)
        })
        if let cwd = entry.cwd, !cwd.isEmpty {
            menu.addItem(makeMenuItem(
                title: String(localized: "sessionIndex.row.openCwd", defaultValue: "Open Working Directory")
            ) {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
            })
        }
        if let pr = entry.pullRequest, let url = URL(string: pr.url) {
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(
                title: String(localized: "sessionIndex.row.openPR", defaultValue: "Open Pull Request")
            ) {
                NSWorkspace.shared.open(url)
            })
        }
    }

    private func makeMenuItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(
            title: title,
            action: #selector(ClosureMenuItem.invoke(_:)),
            keyEquivalent: ""
        )
        item.closure = action
        item.target = item
        return item
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        currentTask?.cancel()
        debounceWorkItem?.cancel()
    }
}

extension SessionSearchPopoverController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        loaded.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // Use a transparent row view so NSTableView's default selection/
        // separator drawing doesn't bleed through the clear-background popover.
        PlainSessionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("SessionRow")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? SessionPopoverRowView)
            ?? SessionPopoverRowView()
        cell.identifier = id
        cell.configure(with: loaded[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < loaded.count else { return nil }
        let entry = loaded[row]
        let dragId = SessionDragRegistry.shared.register(entry)
        let item = NSPasteboardItem()
        if let data = sessionTabTransferData(for: entry, dragId: dragId) {
            let type = NSPasteboard.PasteboardType("com.splittabbar.tabtransfer")
            item.setData(data, forType: type)
            // Mirror onto the drag pasteboard. Bonsplit's external-drop
            // decoder reads from the drag pasteboard directly — same
            // behavior as the SwiftUI `.onDrag` path.
            DispatchQueue.main.async {
                let pb = NSPasteboard(name: .drag)
                pb.addTypes([type], owner: nil)
                pb.setData(data, forType: type)
            }
        }
        return item
    }
}

/// Transparent row view for the popover's NSTableView. Skips the default
/// selection/separator drawing so the popover's dark material background
/// shows cleanly and nothing paints behind the cell's manual layout.
private final class PlainSessionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set { /* no-op */ }
    }
    override func drawBackground(in dirtyRect: NSRect) { /* no-op */ }
    override func drawSelection(in dirtyRect: NSRect) { /* no-op */ }
    override func drawSeparator(in dirtyRect: NSRect) { /* no-op */ }
}

/// Row cell for the popover's NSTableView. Manual layout (not autolayout) so
/// the cell is bulletproof against NSTableView's frame-driven sizing — row
/// views get reused as the table scrolls, and autolayout in a row cell kept
/// producing overlapping text on reuse.
private final class SessionPopoverRowView: NSView {
    private let hoverBackground = NSView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let dateField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        hoverBackground.wantsLayer = true
        hoverBackground.layer?.backgroundColor = NSColor.clear.cgColor
        hoverBackground.layer?.cornerRadius = 4
        addSubview(hoverBackground)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleField.font = .systemFont(ofSize: 12)
        titleField.textColor = NSColor.labelColor.withAlphaComponent(0.92)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.usesSingleLineMode = true
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        addSubview(titleField)

        dateField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dateField.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.7)
        dateField.isEditable = false
        dateField.isSelectable = false
        dateField.isBordered = false
        dateField.drawsBackground = false
        addSubview(dateField)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        hoverBackground.frame = NSRect(x: 4, y: 1, width: max(0, w - 8), height: max(0, h - 2))

        let iconSize: CGFloat = 12
        let iconX: CGFloat = 12
        iconView.frame = NSRect(x: iconX, y: (h - iconSize) / 2, width: iconSize, height: iconSize)

        // Use each field's font line height rather than intrinsicContentSize.
        // intrinsicContentSize reports the full MULTI-LINE height when the
        // string has embedded newlines (session titles often wrap because
        // they include `<command-message>...\n\n...` envelopes), even with
        // usesSingleLineMode = true. That inflated height drove the frame
        // off the top of the cell and into the row above.
        let dateLineHeight = lineHeight(for: dateField.font)
        let dateContentWidth = dateField.intrinsicContentSize.width
        let datePaddingRight: CGFloat = 12
        let dateX = max(0, w - datePaddingRight - dateContentWidth)
        dateField.frame = NSRect(
            x: dateX,
            y: (h - dateLineHeight) / 2,
            width: dateContentWidth,
            height: dateLineHeight
        )

        let titleX = iconX + iconSize + 6
        let titleWidth = max(0, dateX - 8 - titleX)
        let titleLineHeight = lineHeight(for: titleField.font)
        titleField.frame = NSRect(
            x: titleX,
            y: (h - titleLineHeight) / 2,
            width: titleWidth,
            height: titleLineHeight
        )
    }

    private func lineHeight(for font: NSFont?) -> CGFloat {
        guard let font else { return 16 }
        return ceil(font.ascender - font.descender + font.leading)
    }

    func configure(with entry: SessionEntry) {
        iconView.image = NSImage(named: entry.agent.assetName)
        // Flatten newlines / tabs so the single-line truncation lines up
        // with the cell's line-height. Session titles routinely include
        // embedded newlines in structured command envelopes.
        titleField.stringValue = Self.flatten(entry.displayTitle)
        dateField.stringValue = SessionIndexView.relativeFormatter.localizedString(
            for: entry.modified, relativeTo: Date()
        )
        toolTip = entry.cwdLabel ?? entry.displayTitle
        needsLayout = true
    }

    private static func flatten(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\r\n", with: " ")
        out = out.replacingOccurrences(of: "\n", with: " ")
        out = out.replacingOccurrences(of: "\r", with: " ")
        out = out.replacingOccurrences(of: "\t", with: " ")
        return out
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hoverBackground.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hoverBackground.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// NSView subclass that dismisses the popover on Escape via the standard
/// responder-chain `cancelOperation(_:)` hook. Lives in the popover's view
/// tree so it inherits the popover window's responder chain.
private final class EscapeDismissView: NSView {
    var onEscape: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// NSMenuItem subclass that invokes an arbitrary closure on selection so
/// each row's context-menu items can carry per-row state without a shared
/// dispatch table.
private final class ClosureMenuItem: NSMenuItem {
    var closure: (() -> Void)?
    @objc func invoke(_ sender: Any?) { closure?() }
}

// MARK: - Drag cancel monitor

/// Clears `dragCoordinator.draggedKey` after any mouseUp, so a cancelled drag
/// (user releases outside any valid drop target, or presses Esc mid-drag)
/// doesn't leave the section stuck at 0.45 opacity. Successful drops clear
/// the key themselves via `SectionGapDropDelegate.performDrop` and that clear
/// happens under `DispatchQueue.main.async`, so the drop path always wins the
/// race against this fallback.
private struct DragCancelMonitor: NSViewRepresentable {
    let dragCoordinator: SessionDragCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = DragCancelMonitorView()
        view.dragCoordinator = dragCoordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragCancelMonitorView)?.dragCoordinator = dragCoordinator
    }

    private final class DragCancelMonitorView: NSView {
        weak var dragCoordinator: SessionDragCoordinator?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .otherMouseUp]) { [weak self] event in
                guard let coordinator = self?.dragCoordinator,
                      coordinator.draggedKey != nil else { return event }
                // Defer the clear so any `performDrop` already queued on the
                // main actor wins first; this path only matters when no drop
                // fires, i.e. the drag was cancelled.
                DispatchQueue.main.async {
                    coordinator.draggedKey = nil
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
