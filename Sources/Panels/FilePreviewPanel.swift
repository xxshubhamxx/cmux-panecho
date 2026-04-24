import AppKit
import AVKit
import Bonsplit
import Combine
import Foundation
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

private enum FilePreviewInteraction {
    static let zoomStep: CGFloat = 1.25

    static func hasZoomModifier(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option) || flags.contains(.command)
    }

    static func zoomFactor(forScroll event: NSEvent) -> CGFloat {
        let rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        let normalizedDelta = event.hasPreciseScrollingDeltas ? rawDelta : rawDelta * 8
        let factor = pow(1.0025, normalizedDelta)
        guard factor.isFinite else { return 1 }
        return min(max(factor, 0.2), 5.0)
    }
}

struct FilePreviewDragEntry {
    let filePath: String
    let displayTitle: String
}

final class FilePreviewDragRegistry {
    static let shared = FilePreviewDragRegistry()

    private let lock = NSLock()
    private var pending: [UUID: FilePreviewDragEntry] = [:]

    func register(_ entry: FilePreviewDragEntry) -> UUID {
        let id = UUID()
        lock.lock()
        pending[id] = entry
        lock.unlock()
        return id
    }

    func consume(id: UUID) -> FilePreviewDragEntry? {
        lock.lock()
        defer { lock.unlock() }
        return pending.removeValue(forKey: id)
    }

    func discardAll() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
    }
}

final class FilePreviewDragPasteboardWriter: NSObject, NSPasteboardWriting {
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

    private struct MirrorTabTransferData: Codable {
        let tab: MirrorTabItem
        let sourcePaneId: UUID
        let sourceProcessId: Int32
    }

    static let bonsplitTransferType = NSPasteboard.PasteboardType("com.splittabbar.tabtransfer")

    private let transferData: Data

    init(filePath: String, displayTitle: String) {
        let dragId = FilePreviewDragRegistry.shared.register(
            FilePreviewDragEntry(filePath: filePath, displayTitle: displayTitle)
        )
        let transfer = MirrorTabTransferData(
            tab: MirrorTabItem(
                id: dragId,
                title: displayTitle,
                hasCustomTitle: false,
                icon: FilePreviewKindResolver.tabIconName(for: URL(fileURLWithPath: filePath)),
                iconImageData: nil,
                kind: "filePreview",
                isDirty: false,
                showsNotificationBadge: false,
                isLoading: false,
                isPinned: false
            ),
            sourcePaneId: UUID(),
            sourceProcessId: Int32(ProcessInfo.processInfo.processIdentifier)
        )
        self.transferData = (try? JSONEncoder().encode(transfer)) ?? Data()
        super.init()
        mirrorTransferDataToDragPasteboard()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [Self.bonsplitTransferType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == Self.bonsplitTransferType {
            mirrorTransferDataToDragPasteboard()
            return transferData
        }
        return nil
    }

    private func mirrorTransferDataToDragPasteboard() {
        let write = { [transferData] in
            let pasteboard = NSPasteboard(name: .drag)
            pasteboard.addTypes([Self.bonsplitTransferType], owner: nil)
            pasteboard.setData(transferData, forType: Self.bonsplitTransferType)
        }
        if Thread.isMainThread {
            write()
        } else {
            DispatchQueue.main.async(execute: write)
        }
    }
}

enum FilePreviewMode: Equatable {
    case text
    case pdf
    case image
    case media
    case quickLook
}

enum FilePreviewKindResolver {
    private static let textFilenames: Set<String> = [
        ".env",
        ".gitignore",
        ".gitattributes",
        ".npmrc",
        ".zshrc",
        "dockerfile",
        "makefile",
        "gemfile",
        "podfile"
    ]

    private static let textExtensions: Set<String> = [
        "bash", "c", "cc", "cfg", "conf", "cpp", "cs", "css", "csv", "env",
        "fish", "go", "h", "hpp", "htm", "html", "ini", "java", "js", "json",
        "jsx", "kt", "log", "m", "markdown", "md", "mdx", "mm", "plist", "py",
        "rb", "rs", "sh", "sql", "swift", "toml", "ts", "tsx", "tsv", "txt",
        "xml", "yaml", "yml", "zsh"
    ]

    static func mode(for url: URL) -> FilePreviewMode {
        if isTextFile(url: url) {
            return .text
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) {
                return .pdf
            }
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie)
                || type.conforms(to: .audiovisualContent)
                || type.conforms(to: .audio) {
                return .media
            }
        }
        if let fallbackType = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if fallbackType.conforms(to: .pdf) {
                return .pdf
            }
            if fallbackType.conforms(to: .image) {
                return .image
            }
            if fallbackType.conforms(to: .movie)
                || fallbackType.conforms(to: .audiovisualContent)
                || fallbackType.conforms(to: .audio) {
                return .media
            }
        }
        return .quickLook
    }

    static func tabIconName(for url: URL) -> String {
        if isTextFile(url: url) {
            return "doc.text"
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) {
                return "doc.richtext"
            }
            if type.conforms(to: .image) {
                return "photo"
            }
            if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
                return "play.rectangle"
            }
            if type.conforms(to: .audio) {
                return "waveform"
            }
        }
        return "doc.viewfinder"
    }

    private static func isTextFile(url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        if textFilenames.contains(filename) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        if textExtensions.contains(ext) {
            return true
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            return true
        }
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            return true
        }
        return sniffLooksLikeText(url: url)
    }

    private static func sniffLooksLikeText(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        guard !data.isEmpty else { return true }
        if data.contains(0) {
            return false
        }
        if String(data: data, encoding: .utf8) != nil {
            return true
        }
        if String(data: data, encoding: .utf16) != nil {
            return true
        }
        return false
    }
}

@MainActor
final class FilePreviewPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .filePreview
    let filePath: String
    private(set) var workspaceId: UUID

    @Published private(set) var displayTitle: String
    @Published private(set) var isFileUnavailable = false
    @Published private(set) var textContent = ""
    @Published private(set) var isDirty = false
    @Published private(set) var focusFlashToken = 0

    let previewMode: FilePreviewMode
    private var originalTextContent = ""
    private var textEncoding: String.Encoding = .utf8
    private weak var textView: NSTextView?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var displayIcon: String? {
        FilePreviewKindResolver.tabIconName(for: fileURL)
    }

    init(workspaceId: UUID, filePath: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.filePath = filePath
        self.displayTitle = URL(fileURLWithPath: filePath).lastPathComponent
        self.previewMode = FilePreviewKindResolver.mode(for: URL(fileURLWithPath: filePath))

        if previewMode == .text {
            loadTextContent()
        } else {
            isFileUnavailable = !FileManager.default.fileExists(atPath: filePath)
        }
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func unfocus() {
        // No-op. AppKit resigns the text view when another panel becomes first responder.
    }

    func close() {
        textView = nil
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    func attachTextView(_ textView: NSTextView) {
        self.textView = textView
    }

    func updateTextContent(_ nextContent: String) {
        guard textContent != nextContent else { return }
        textContent = nextContent
        isDirty = nextContent != originalTextContent
    }

    func loadTextContent() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            isFileUnavailable = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = Self.decodeText(data)
            guard let decoded else {
                isFileUnavailable = true
                return
            }
            textContent = decoded.content
            originalTextContent = decoded.content
            textEncoding = decoded.encoding
            isDirty = false
            isFileUnavailable = false
        } catch {
            isFileUnavailable = true
        }
    }

    func saveTextContent() {
        guard previewMode == .text else { return }
        do {
            let currentContent = textView?.string ?? textContent
            textContent = currentContent
            try currentContent.write(to: fileURL, atomically: true, encoding: textEncoding)
            originalTextContent = textContent
            isDirty = false
            isFileUnavailable = false
        } catch {
            isFileUnavailable = true
        }
    }

    private static func decodeText(_ data: Data) -> (content: String, encoding: String.Encoding)? {
        if let decoded = String(data: data, encoding: .utf8) {
            return (decoded, .utf8)
        }
        if let decoded = String(data: data, encoding: .utf16) {
            return (decoded, .utf16)
        }
        if let decoded = String(data: data, encoding: .isoLatin1) {
            return (decoded, .isoLatin1)
        }
        return nil
    }
}

struct FilePreviewPanelView: View {
    @ObservedObject var panel: FilePreviewPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity = 0.0
    @State private var focusFlashAnimationGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            if panel.previewMode != .pdf {
                header
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                FilePreviewPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: panel.displayIcon ?? "doc.viewfinder")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(panel.filePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if panel.previewMode == .text {
                Button {
                    panel.loadTextContent()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!panel.isDirty)
                .help(String(localized: "filePreview.revert", defaultValue: "Revert"))
                .accessibilityLabel(String(localized: "filePreview.revert", defaultValue: "Revert"))

                Button {
                    panel.saveTextContent()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!panel.isDirty)
                .keyboardShortcut("s", modifiers: .command)
                .help(String(localized: "filePreview.save", defaultValue: "Save"))
                .accessibilityLabel(String(localized: "filePreview.save", defaultValue: "Save"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if panel.isFileUnavailable {
            fileUnavailableView
        } else {
            switch panel.previewMode {
            case .text:
                FilePreviewTextEditor(panel: panel)
            case .pdf:
                FilePreviewPDFView(url: panel.fileURL)
            case .image:
                FilePreviewImageView(url: panel.fileURL)
            case .media:
                FilePreviewMediaView(url: panel.fileURL)
            case .quickLook:
                QuickLookPreviewView(url: panel.fileURL, title: panel.displayTitle)
            }
        }
    }

    private var fileUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(String(localized: "filePreview.fileUnavailable.title", defaultValue: "File unavailable"))
                .font(.headline)
            Text(panel.filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Text(String(localized: "filePreview.fileUnavailable.message", defaultValue: "The file may have been moved or deleted."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }
}

private struct FilePreviewTextEditor: NSViewRepresentable {
    @ObservedObject var panel: FilePreviewPanel

    func makeCoordinator() -> Coordinator {
        Coordinator(panel: panel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SavingTextView()
        textView.panel = panel
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.usesFontPanel = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = panel.textContent
        panel.attachTextView(textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.panel = panel
        guard let textView = scrollView.documentView as? SavingTextView else { return }
        textView.panel = panel
        panel.attachTextView(textView)
        guard textView.string != panel.textContent else { return }
        context.coordinator.isApplyingPanelUpdate = true
        textView.string = panel.textContent
        context.coordinator.isApplyingPanelUpdate = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var panel: FilePreviewPanel
        var isApplyingPanelUpdate = false

        init(panel: FilePreviewPanel) {
            self.panel = panel
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingPanelUpdate,
                  let textView = notification.object as? NSTextView else { return }
            panel.updateTextContent(textView.string)
        }
    }
}

private final class SavingTextView: NSTextView {
    private static let defaultPreviewFontSize: CGFloat = 13
    private static let minimumPreviewFontSize: CGFloat = 8
    private static let maximumPreviewFontSize: CGFloat = 36

    weak var panel: FilePreviewPanel?
    private var previewFontSize: CGFloat = 13

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            panel?.saveTextContent()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func magnify(with event: NSEvent) {
        let factor = 1.0 + event.magnification
        guard factor.isFinite, factor > 0 else { return }
        adjustPreviewFontSize(by: factor)
    }

    override func scrollWheel(with event: NSEvent) {
        guard FilePreviewInteraction.hasZoomModifier(event) else {
            super.scrollWheel(with: event)
            return
        }
        adjustPreviewFontSize(by: FilePreviewInteraction.zoomFactor(forScroll: event))
    }

    override func smartMagnify(with event: NSEvent) {
        if previewFontSize == Self.defaultPreviewFontSize {
            setPreviewFontSize(18)
        } else {
            setPreviewFontSize(Self.defaultPreviewFontSize)
        }
    }

    private func adjustPreviewFontSize(by factor: CGFloat) {
        setPreviewFontSize(previewFontSize * factor)
    }

    private func setPreviewFontSize(_ nextFontSize: CGFloat) {
        let clamped = min(max(nextFontSize, Self.minimumPreviewFontSize), Self.maximumPreviewFontSize)
        guard clamped.isFinite else { return }
        previewFontSize = clamped
        let nextFont = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
        font = nextFont
        typingAttributes[.font] = nextFont
    }
}

private struct FilePreviewPDFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> FilePreviewPDFContainerView {
        let view = FilePreviewPDFContainerView()
        view.setURL(url)
        return view
    }

    func updateNSView(_ nsView: FilePreviewPDFContainerView, context: Context) {
        nsView.setURL(url)
    }
}

private enum FilePreviewPDFSidebarMode {
    case thumbnails
    case tableOfContents
}

private enum FilePreviewPDFDisplayMode {
    case continuousScroll
    case singlePage
    case twoPages
}

private final class FilePreviewPDFContainerView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let splitView = NSSplitView()
    private let sidebarHost = NSVisualEffectView()
    private let contentHost = NSView()
    private let pdfView = FilePreviewMagnifyingPDFView()
    private let thumbnailView = PDFThumbnailView()
    private let outlineScrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let outlinePlaceholder = NSTextField(wrappingLabelWithString: "")
    private let sidebarMenuButton = NSButton(title: "", target: nil, action: nil)
    private let leftFloatingChrome = NSVisualEffectView()
    private let rightFloatingChrome = NSVisualEffectView()
    private let zoomControl = NSSegmentedControl()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pageLabel = NSTextField(labelWithString: "")
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var currentURL: URL?
    private var outlineRoot: PDFOutline?
    private var sidebarMode: FilePreviewPDFSidebarMode = .thumbnails
    private var displayMode: FilePreviewPDFDisplayMode = .continuousScroll
    private var isSidebarVisible = true
    private var rotationAccumulator: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setURL(_ url: URL) {
        guard currentURL != url else { return }
        currentURL = url
        let document = PDFDocument(url: url)
        pdfView.document = document
        outlineRoot = document?.outlineRoot
        titleLabel.stringValue = url.lastPathComponent
        rotationAccumulator = 0
        pdfView.autoScales = true
        applyDisplayMode()
        outlineView.reloadData()
        updateSidebarContent()
        updatePageControls()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        setupSplitView()
        setupSidebar()
        setupPDFView()
        setupFloatingChrome()

        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .textBackgroundColor
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 8.0
        pdfView.onMagnify = { [weak self] event in
            let factor = 1.0 + event.magnification
            self?.zoomPDF(with: event, factor: factor)
        }
        pdfView.onScrollZoom = { [weak self] event in
            self?.zoomPDF(with: event, factor: FilePreviewInteraction.zoomFactor(forScroll: event))
        }
        pdfView.onSmartMagnify = { [weak self] in
            self?.togglePDFSmartZoom()
        }
        pdfView.onRotate = { [weak self] event in
            self?.rotatePDF(with: event)
        }
        pdfView.onSwipe = { [weak self] event in
            self?.swipePDF(with: event)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfPageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(contentHost)
        addSubview(splitView)

        sidebarWidthConstraint = sidebarHost.widthAnchor.constraint(equalToConstant: 220)
        sidebarWidthConstraint?.priority = .defaultHigh
        sidebarWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupSidebar() {
        sidebarHost.material = .sidebar
        sidebarHost.blendingMode = .withinWindow
        sidebarHost.state = .active

        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 150, height: 104)
        thumbnailView.maximumNumberOfColumns = 1
        thumbnailView.backgroundColor = .clear
        thumbnailView.labelFont = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        let outlineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filePreviewPDFOutline"))
        outlineColumn.title = String(localized: "filePreview.pdf.tableOfContents", defaultValue: "Table of Contents")
        outlineView.addTableColumn(outlineColumn)
        outlineView.outlineTableColumn = outlineColumn
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.translatesAutoresizingMaskIntoConstraints = false

        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.autohidesScrollers = true
        outlineScrollView.borderType = .noBorder
        outlineScrollView.drawsBackground = false
        outlineScrollView.documentView = outlineView
        outlineScrollView.translatesAutoresizingMaskIntoConstraints = false

        outlinePlaceholder.stringValue = String(
            localized: "filePreview.pdf.noTableOfContents",
            defaultValue: "No table of contents"
        )
        outlinePlaceholder.alignment = .center
        outlinePlaceholder.textColor = .secondaryLabelColor
        outlinePlaceholder.translatesAutoresizingMaskIntoConstraints = false

        sidebarHost.addSubview(thumbnailView)
        sidebarHost.addSubview(outlineScrollView)
        sidebarHost.addSubview(outlinePlaceholder)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: sidebarHost.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: sidebarHost.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: sidebarHost.bottomAnchor),
            outlineScrollView.topAnchor.constraint(equalTo: sidebarHost.topAnchor),
            outlineScrollView.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor),
            outlineScrollView.trailingAnchor.constraint(equalTo: sidebarHost.trailingAnchor),
            outlineScrollView.bottomAnchor.constraint(equalTo: sidebarHost.bottomAnchor),
            outlinePlaceholder.centerXAnchor.constraint(equalTo: sidebarHost.centerXAnchor),
            outlinePlaceholder.centerYAnchor.constraint(equalTo: sidebarHost.centerYAnchor),
            outlinePlaceholder.leadingAnchor.constraint(greaterThanOrEqualTo: sidebarHost.leadingAnchor, constant: 16),
            outlinePlaceholder.trailingAnchor.constraint(lessThanOrEqualTo: sidebarHost.trailingAnchor, constant: -16),
        ])
    }

    private func setupPDFView() {
        contentHost.wantsLayer = true
        contentHost.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: contentHost.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
    }

    private func setupFloatingChrome() {
        configureFloatingChrome(leftFloatingChrome)
        configureFloatingChrome(rightFloatingChrome)

        sidebarMenuButton.target = self
        sidebarMenuButton.action = #selector(showSidebarMenu)
        sidebarMenuButton.bezelStyle = .texturedRounded
        sidebarMenuButton.controlSize = .regular
        sidebarMenuButton.image = NSImage(
            systemSymbolName: "sidebar.left",
            accessibilityDescription: String(localized: "filePreview.pdf.sidebarOptions", defaultValue: "Sidebar Options")
        )
        sidebarMenuButton.imagePosition = .imageOnly
        sidebarMenuButton.toolTip = String(localized: "filePreview.pdf.sidebarOptions", defaultValue: "Sidebar Options")
        sidebarMenuButton.setAccessibilityLabel(
            String(localized: "filePreview.pdf.sidebarOptions", defaultValue: "Sidebar Options")
        )
        sidebarMenuButton.translatesAutoresizingMaskIntoConstraints = false

        leftFloatingChrome.addSubview(sidebarMenuButton)
        contentHost.addSubview(leftFloatingChrome)

        zoomControl.segmentCount = 3
        zoomControl.trackingMode = .momentary
        zoomControl.segmentStyle = .rounded
        zoomControl.target = self
        zoomControl.action = #selector(zoomSegmentChanged)
        configureZoomSegment(
            0,
            symbolName: "minus.magnifyingglass",
            label: String(localized: "filePreview.pdf.zoomOut", defaultValue: "Zoom Out")
        )
        configureZoomSegment(
            1,
            symbolName: "1.magnifyingglass",
            label: String(localized: "filePreview.pdf.actualSize", defaultValue: "Actual Size")
        )
        configureZoomSegment(
            2,
            symbolName: "plus.magnifyingglass",
            label: String(localized: "filePreview.pdf.zoomIn", defaultValue: "Zoom In")
        )
        zoomControl.translatesAutoresizingMaskIntoConstraints = false

        rightFloatingChrome.addSubview(zoomControl)
        contentHost.addSubview(rightFloatingChrome)

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pageLabel.font = .systemFont(ofSize: 12)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.lineBreakMode = .byTruncatingTail

        let titleStack = NSStackView(views: [titleLabel, pageLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(titleStack)

        NSLayoutConstraint.activate([
            leftFloatingChrome.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 8),
            leftFloatingChrome.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 8),
            leftFloatingChrome.widthAnchor.constraint(equalToConstant: 48),
            leftFloatingChrome.heightAnchor.constraint(equalToConstant: 38),
            sidebarMenuButton.topAnchor.constraint(equalTo: leftFloatingChrome.topAnchor, constant: 4),
            sidebarMenuButton.leadingAnchor.constraint(equalTo: leftFloatingChrome.leadingAnchor, constant: 4),
            sidebarMenuButton.trailingAnchor.constraint(equalTo: leftFloatingChrome.trailingAnchor, constant: -4),
            sidebarMenuButton.bottomAnchor.constraint(equalTo: leftFloatingChrome.bottomAnchor, constant: -4),

            rightFloatingChrome.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 8),
            rightFloatingChrome.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor, constant: -8),
            rightFloatingChrome.heightAnchor.constraint(equalToConstant: 38),
            zoomControl.topAnchor.constraint(equalTo: rightFloatingChrome.topAnchor, constant: 4),
            zoomControl.leadingAnchor.constraint(equalTo: rightFloatingChrome.leadingAnchor, constant: 4),
            zoomControl.trailingAnchor.constraint(equalTo: rightFloatingChrome.trailingAnchor, constant: -4),
            zoomControl.bottomAnchor.constraint(equalTo: rightFloatingChrome.bottomAnchor, constant: -4),

            titleStack.leadingAnchor.constraint(equalTo: leftFloatingChrome.trailingAnchor, constant: 12),
            titleStack.centerYAnchor.constraint(equalTo: leftFloatingChrome.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: rightFloatingChrome.leadingAnchor, constant: -12),
        ])
    }

    private func configureFloatingChrome(_ effectView: NSVisualEffectView) {
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 19
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureZoomSegment(
        _ index: Int,
        symbolName: String,
        label: String
    ) {
        zoomControl.setImage(NSImage(systemSymbolName: symbolName, accessibilityDescription: label), forSegment: index)
        zoomControl.setLabel("", forSegment: index)
        zoomControl.setToolTip(label, forSegment: index)
        zoomControl.setWidth(34, forSegment: index)
    }

    @objc private func zoomOut() {
        pdfView.autoScales = false
        setPDFScaleFactor(pdfView.scaleFactor / FilePreviewInteraction.zoomStep)
    }

    @objc private func zoomIn() {
        pdfView.autoScales = false
        setPDFScaleFactor(pdfView.scaleFactor * FilePreviewInteraction.zoomStep)
    }

    @objc private func zoomToFit() {
        pdfView.autoScales = true
    }

    @objc private func actualSize() {
        pdfView.autoScales = false
        setPDFScaleFactor(1.0)
    }

    @objc private func zoomSegmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            zoomOut()
        case 1:
            actualSize()
        case 2:
            zoomIn()
        default:
            break
        }
    }

    @objc private func showSidebarMenu(_ sender: NSButton) {
        let menu = makeSidebarMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }

    @objc private func toggleSidebar() {
        isSidebarVisible.toggle()
        updateSidebarVisibility()
    }

    @objc private func selectThumbnailSidebar() {
        sidebarMode = .thumbnails
        isSidebarVisible = true
        updateSidebarVisibility()
        updateSidebarContent()
    }

    @objc private func selectTableOfContentsSidebar() {
        sidebarMode = .tableOfContents
        isSidebarVisible = true
        updateSidebarVisibility()
        updateSidebarContent()
    }

    @objc private func selectContinuousScroll() {
        displayMode = .continuousScroll
        applyDisplayMode()
    }

    @objc private func selectSinglePage() {
        displayMode = .singlePage
        applyDisplayMode()
    }

    @objc private func selectTwoPages() {
        displayMode = .twoPages
        applyDisplayMode()
    }

    @objc private func pdfPageChanged() {
        updatePageControls()
    }

    private func updatePageControls() {
        guard let document = pdfView.document, document.pageCount > 0 else {
            pageLabel.stringValue = ""
            return
        }

        let pageIndex: Int
        if let currentPage = pdfView.currentPage {
            pageIndex = max(0, document.index(for: currentPage))
        } else {
            pageIndex = 0
        }
        let format = String(localized: "filePreview.pdf.pageCount", defaultValue: "Page %d of %d")
        pageLabel.stringValue = String(format: format, pageIndex + 1, document.pageCount)
    }

    private func makeSidebarMenu() -> NSMenu {
        let menu = NSMenu()
        let sidebarVisibilityTitle = isSidebarVisible
            ? String(localized: "filePreview.pdf.hideSidebar", defaultValue: "Hide Sidebar")
            : String(localized: "filePreview.pdf.showSidebar", defaultValue: "Show Sidebar")
        menu.addItem(makeMenuItem(
            title: sidebarVisibilityTitle,
            action: #selector(toggleSidebar)
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "filePreview.pdf.thumbnails", defaultValue: "Thumbnails"),
            action: #selector(selectThumbnailSidebar),
            state: sidebarMode == .thumbnails ? .on : .off
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "filePreview.pdf.tableOfContents", defaultValue: "Table of Contents"),
            action: #selector(selectTableOfContentsSidebar),
            state: sidebarMode == .tableOfContents ? .on : .off
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: String(localized: "filePreview.pdf.continuousScroll", defaultValue: "Continuous Scroll"),
            action: #selector(selectContinuousScroll),
            state: displayMode == .continuousScroll ? .on : .off
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "filePreview.pdf.singlePage", defaultValue: "Single Page"),
            action: #selector(selectSinglePage),
            state: displayMode == .singlePage ? .on : .off
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "filePreview.pdf.twoPages", defaultValue: "Two Pages"),
            action: #selector(selectTwoPages),
            state: displayMode == .twoPages ? .on : .off
        ))
        return menu
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        state: NSControl.StateValue = .off
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state
        return item
    }

    private func updateSidebarVisibility() {
        sidebarHost.isHidden = !isSidebarVisible
        sidebarWidthConstraint?.constant = isSidebarVisible ? 220 : 0
        splitView.adjustSubviews()
    }

    private func updateSidebarContent() {
        let showingThumbnails = sidebarMode == .thumbnails
        let showingTableOfContents = sidebarMode == .tableOfContents
        let hasOutline = (outlineRoot?.numberOfChildren ?? 0) > 0
        thumbnailView.isHidden = !showingThumbnails
        outlineScrollView.isHidden = !showingTableOfContents || !hasOutline
        outlinePlaceholder.isHidden = !showingTableOfContents || hasOutline
    }

    private func applyDisplayMode() {
        switch displayMode {
        case .continuousScroll:
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
        case .singlePage:
            pdfView.displayMode = .singlePage
            pdfView.displayDirection = .vertical
        case .twoPages:
            pdfView.displayMode = .twoUp
            pdfView.displayDirection = .horizontal
        }
        pdfView.autoScales = true
    }

    private func zoomPDF(with event: NSEvent, factor: CGFloat) {
        guard pdfView.document != nil else { return }
        guard factor.isFinite, factor > 0 else { return }
        pdfView.autoScales = false
        setPDFScaleFactor(pdfView.scaleFactor * factor)
    }

    private func togglePDFSmartZoom() {
        if pdfView.autoScales {
            actualSize()
        } else {
            zoomToFit()
        }
    }

    private func rotatePDF(with event: NSEvent) {
        rotationAccumulator += CGFloat(event.rotation)
        if rotationAccumulator >= 45 {
            rotateCurrentPDFPage(by: -90)
            rotationAccumulator = 0
        } else if rotationAccumulator <= -45 {
            rotateCurrentPDFPage(by: 90)
            rotationAccumulator = 0
        }
    }

    private func swipePDF(with event: NSEvent) {
        if event.deltaX < 0 {
            pdfView.goToNextPage(nil)
            updatePageControls()
        } else if event.deltaX > 0 {
            pdfView.goToPreviousPage(nil)
            updatePageControls()
        }
    }

    private func rotateCurrentPDFPage(by degrees: Int) {
        guard let page = pdfView.currentPage else { return }
        page.rotation = normalizedRotation(page.rotation + degrees)
        pdfView.layoutDocumentView()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func setPDFScaleFactor(_ nextScale: CGFloat) {
        let clamped = min(max(nextScale, pdfView.minScaleFactor), pdfView.maxScaleFactor)
        guard clamped.isFinite else { return }
        pdfView.scaleFactor = clamped
    }

    private func normalizedRotation(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let outline = item as? PDFOutline ?? outlineRoot
        return outline?.numberOfChildren ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let outline = item as? PDFOutline else { return false }
        return outline.numberOfChildren > 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let outline = item as? PDFOutline ?? outlineRoot
        return outline?.child(at: index) ?? NSNull()
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let outline = item as? PDFOutline else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("filePreviewPDFOutlineCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeOutlineCell(identifier: identifier)
        cell.textField?.stringValue = outline.label ?? ""
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0,
              let outline = outlineView.item(atRow: selectedRow) as? PDFOutline,
              let destination = outline.destination else { return }
        pdfView.go(to: destination)
        updatePageControls()
    }

    private func makeOutlineCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

private final class FilePreviewMagnifyingPDFView: PDFView {
    var onMagnify: ((NSEvent) -> Void)?
    var onScrollZoom: ((NSEvent) -> Void)?
    var onSmartMagnify: (() -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    var onSwipe: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if FilePreviewInteraction.hasZoomModifier(event), let onScrollZoom {
            onScrollZoom(event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        if let onSmartMagnify {
            onSmartMagnify()
        } else {
            super.smartMagnify(with: event)
        }
    }

    override func rotate(with event: NSEvent) {
        if let onRotate {
            onRotate(event)
        } else {
            super.rotate(with: event)
        }
    }

    override func swipe(with event: NSEvent) {
        if let onSwipe {
            onSwipe(event)
        } else {
            super.swipe(with: event)
        }
    }
}

private struct FilePreviewImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> FilePreviewImageContainerView {
        let view = FilePreviewImageContainerView()
        view.setURL(url)
        return view
    }

    func updateNSView(_ nsView: FilePreviewImageContainerView, context: Context) {
        nsView.setURL(url)
    }
}

private final class FilePreviewImageContainerView: NSView {
    private let scrollView = FilePreviewImageScrollView()
    private let documentView = FilePreviewImageDocumentView()
    private let zoomLabel = NSTextField(labelWithString: "")
    private var currentURL: URL?
    private var imageSize = CGSize(width: 1, height: 1)
    private var scale: CGFloat = 1
    private var isFitMode = true
    private var rotationDegrees = 0
    private var rotationAccumulator: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        if isFitMode {
            scale = fitScale()
        }
        applyScale()
    }

    func setURL(_ url: URL) {
        guard currentURL != url else { return }
        currentURL = url
        let image = NSImage(contentsOf: url)
        documentView.imageView.image = image
        imageSize = normalizedSize(image?.size ?? .zero)
        isFitMode = true
        rotationDegrees = 0
        rotationAccumulator = 0
        scale = fitScale()
        applyScale()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        let zoomOutButton = makeToolbarButton(
            systemSymbolName: "minus.magnifyingglass",
            fallbackTitle: "-",
            label: String(localized: "filePreview.image.zoomOut", defaultValue: "Zoom Out"),
            action: #selector(zoomOut)
        )
        let zoomInButton = makeToolbarButton(
            systemSymbolName: "plus.magnifyingglass",
            fallbackTitle: "+",
            label: String(localized: "filePreview.image.zoomIn", defaultValue: "Zoom In"),
            action: #selector(zoomIn)
        )
        let fitButton = makeToolbarButton(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            fallbackTitle: "Fit",
            label: String(localized: "filePreview.image.zoomToFit", defaultValue: "Zoom to Fit"),
            action: #selector(zoomToFit)
        )
        let actualSizeButton = makeToolbarButton(
            systemSymbolName: "1.magnifyingglass",
            fallbackTitle: "1x",
            label: String(localized: "filePreview.image.actualSize", defaultValue: "Actual Size"),
            action: #selector(actualSize)
        )
        let rotateLeftButton = makeToolbarButton(
            systemSymbolName: "rotate.left",
            fallbackTitle: "L",
            label: String(localized: "filePreview.image.rotateLeft", defaultValue: "Rotate Left"),
            action: #selector(rotateLeft)
        )
        let rotateRightButton = makeToolbarButton(
            systemSymbolName: "rotate.right",
            fallbackTitle: "R",
            label: String(localized: "filePreview.image.rotateRight", defaultValue: "Rotate Right"),
            action: #selector(rotateRight)
        )

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .right
        zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let toolbar = NSStackView(views: [
            zoomOutButton,
            zoomInButton,
            fitButton,
            actualSizeButton,
            rotateLeftButton,
            rotateRightButton,
            zoomLabel,
        ])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = documentView
        scrollView.onMagnify = { [weak self] event in
            let factor = 1.0 + event.magnification
            self?.zoomImage(with: event, factor: factor)
        }
        scrollView.onScrollZoom = { [weak self] event in
            self?.zoomImage(with: event, factor: FilePreviewInteraction.zoomFactor(forScroll: event))
        }
        scrollView.onSmartMagnify = { [weak self] event in
            self?.toggleImageSmartZoom(with: event)
        }
        scrollView.onRotate = { [weak self] event in
            self?.rotateImage(with: event)
        }
        documentView.onMagnify = { [weak self] event in
            let factor = 1.0 + event.magnification
            self?.zoomImage(with: event, factor: factor)
        }
        documentView.onSmartMagnify = { [weak self] event in
            self?.toggleImageSmartZoom(with: event)
        }
        documentView.onRotate = { [weak self] event in
            self?.rotateImage(with: event)
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(toolbar)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 34),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeToolbarButton(
        systemSymbolName: String,
        fallbackTitle: String,
        label: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        if let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: label) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = fallbackTitle
        }
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    @objc private func zoomOut() {
        isFitMode = false
        scale = clampedImageScale(scale / FilePreviewInteraction.zoomStep)
        applyScale()
    }

    @objc private func zoomIn() {
        isFitMode = false
        scale = clampedImageScale(scale * FilePreviewInteraction.zoomStep)
        applyScale()
    }

    @objc private func zoomToFit() {
        isFitMode = true
        scale = fitScale()
        applyScale()
    }

    @objc private func actualSize() {
        isFitMode = false
        scale = 1.0
        applyScale()
    }

    @objc private func rotateLeft() {
        rotateImage(by: -90)
    }

    @objc private func rotateRight() {
        rotateImage(by: 90)
    }

    private func fitScale() -> CGFloat {
        let clipSize = scrollView.contentView.bounds.size
        guard clipSize.width > 1, clipSize.height > 1 else { return scale }
        let imageSize = displayedImageSize()
        let widthScale = clipSize.width / max(imageSize.width, 1)
        let heightScale = clipSize.height / max(imageSize.height, 1)
        return clampedImageScale(min(widthScale, heightScale))
    }

    private func applyScale() {
        let imageSize = displayedImageSize()
        let scaledSize = CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
        let clipSize = scrollView.contentView.bounds.size
        documentView.frame = CGRect(
            origin: .zero,
            size: CGSize(
                width: max(clipSize.width, scaledSize.width),
                height: max(clipSize.height, scaledSize.height)
            )
        )
        documentView.scaledImageSize = scaledSize
        documentView.rotationDegrees = rotationDegrees
        documentView.needsLayout = true
        zoomLabel.stringValue = "\(Int((scale * 100).rounded()))%"
    }

    private func zoomImage(with event: NSEvent, factor: CGFloat) {
        guard documentView.imageView.image != nil else { return }
        guard factor.isFinite, factor > 0 else { return }

        let anchorInClip = scrollView.contentView.convert(event.locationInWindow, from: nil)
        let oldImageFrame = documentView.imageView.frame
        let anchorInDocument = documentView.convert(event.locationInWindow, from: nil)
        let anchorRatio = CGPoint(
            x: normalizedAnchorRatio(
                anchorInDocument.x - oldImageFrame.minX,
                length: oldImageFrame.width
            ),
            y: normalizedAnchorRatio(
                anchorInDocument.y - oldImageFrame.minY,
                length: oldImageFrame.height
            )
        )

        isFitMode = false
        scale = clampedImageScale(scale * factor)
        applyScale()
        documentView.layoutSubtreeIfNeeded()

        let newImageFrame = documentView.imageView.frame
        let anchoredDocumentPoint = CGPoint(
            x: newImageFrame.minX + (newImageFrame.width * anchorRatio.x),
            y: newImageFrame.minY + (newImageFrame.height * anchorRatio.y)
        )
        scrollDocumentPoint(anchoredDocumentPoint, toClipPoint: anchorInClip)
    }

    private func toggleImageSmartZoom(with event: NSEvent) {
        guard documentView.imageView.image != nil else { return }
        if isFitMode {
            isFitMode = false
            scale = 1.0
            applyScale()
            documentView.layoutSubtreeIfNeeded()
            let anchorInClip = scrollView.contentView.convert(event.locationInWindow, from: nil)
            let anchorInDocument = documentView.convert(event.locationInWindow, from: nil)
            scrollDocumentPoint(anchorInDocument, toClipPoint: anchorInClip)
        } else {
            zoomToFit()
        }
    }

    private func rotateImage(with event: NSEvent) {
        rotationAccumulator += CGFloat(event.rotation)
        if rotationAccumulator >= 45 {
            rotateImage(by: -90)
            rotationAccumulator = 0
        } else if rotationAccumulator <= -45 {
            rotateImage(by: 90)
            rotationAccumulator = 0
        }
    }

    private func rotateImage(by degrees: Int) {
        rotationDegrees = normalizedRotation(rotationDegrees + degrees)
        if isFitMode {
            scale = fitScale()
        }
        applyScale()
    }

    private func scrollDocumentPoint(_ documentPoint: CGPoint, toClipPoint clipPoint: CGPoint) {
        let clipSize = scrollView.contentView.bounds.size
        let documentSize = documentView.bounds.size
        let maxOrigin = CGPoint(
            x: max(0, documentSize.width - clipSize.width),
            y: max(0, documentSize.height - clipSize.height)
        )
        let nextOrigin = CGPoint(
            x: min(max(0, documentPoint.x - clipPoint.x), maxOrigin.x),
            y: min(max(0, documentPoint.y - clipPoint.y), maxOrigin.y)
        )
        scrollView.contentView.scroll(to: nextOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func normalizedAnchorRatio(_ value: CGFloat, length: CGFloat) -> CGFloat {
        guard length > 1 else { return 0.5 }
        return min(max(value / length, 0), 1)
    }

    private func clampedImageScale(_ nextScale: CGFloat) -> CGFloat {
        min(max(nextScale, 0.05), 16.0)
    }

    private func displayedImageSize() -> CGSize {
        if abs(rotationDegrees) % 180 == 90 {
            return CGSize(width: imageSize.height, height: imageSize.width)
        }
        return imageSize
    }

    private func normalizedRotation(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    private func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width), height: max(1, size.height))
    }
}

private final class FilePreviewImageScrollView: NSScrollView {
    var onMagnify: ((NSEvent) -> Void)?
    var onScrollZoom: ((NSEvent) -> Void)?
    var onSmartMagnify: ((NSEvent) -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    private var panStartClipPoint: CGPoint?
    private var panStartDocumentOrigin: CGPoint?
    private var hasPushedPanCursor = false

    override var acceptsFirstResponder: Bool { true }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if FilePreviewInteraction.hasZoomModifier(event), let onScrollZoom {
            onScrollZoom(event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        if let onSmartMagnify {
            onSmartMagnify(event)
        } else {
            super.smartMagnify(with: event)
        }
    }

    override func rotate(with event: NSEvent) {
        if let onRotate {
            onRotate(event)
        } else {
            super.rotate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2, let onSmartMagnify {
            onSmartMagnify(event)
            return
        }
        panStartClipPoint = contentView.convert(event.locationInWindow, from: nil)
        panStartDocumentOrigin = contentView.bounds.origin
        NSCursor.closedHand.push()
        hasPushedPanCursor = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panStartClipPoint, let panStartDocumentOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let currentClipPoint = contentView.convert(event.locationInWindow, from: nil)
        let delta = CGPoint(
            x: currentClipPoint.x - panStartClipPoint.x,
            y: currentClipPoint.y - panStartClipPoint.y
        )
        scroll(toDocumentOrigin: CGPoint(
            x: panStartDocumentOrigin.x - delta.x,
            y: panStartDocumentOrigin.y - delta.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        endPan()
    }

    override func mouseExited(with event: NSEvent) {
        endPan()
        super.mouseExited(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    private func scroll(toDocumentOrigin origin: CGPoint) {
        guard let documentView else { return }
        let clipSize = contentView.bounds.size
        let documentSize = documentView.bounds.size
        let maxOrigin = CGPoint(
            x: max(0, documentSize.width - clipSize.width),
            y: max(0, documentSize.height - clipSize.height)
        )
        let nextOrigin = CGPoint(
            x: min(max(0, origin.x), maxOrigin.x),
            y: min(max(0, origin.y), maxOrigin.y)
        )
        contentView.scroll(to: nextOrigin)
        reflectScrolledClipView(contentView)
    }

    private func endPan() {
        panStartClipPoint = nil
        panStartDocumentOrigin = nil
        if hasPushedPanCursor {
            NSCursor.pop()
            hasPushedPanCursor = false
        }
    }
}

private final class FilePreviewImageDocumentView: NSView {
    let imageView = FilePreviewMagnifyingImageView()
    var scaledImageSize = CGSize(width: 1, height: 1)
    var rotationDegrees = 0 {
        didSet {
            imageView.rotationDegrees = rotationDegrees
        }
    }
    var onMagnify: ((NSEvent) -> Void)? {
        didSet {
            imageView.onMagnify = onMagnify
        }
    }
    var onSmartMagnify: ((NSEvent) -> Void)? {
        didSet {
            imageView.onSmartMagnify = onSmartMagnify
        }
    }
    var onRotate: ((NSEvent) -> Void)? {
        didSet {
            imageView.onRotate = onRotate
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        imageView.frame = CGRect(
            x: max(0, (bounds.width - scaledImageSize.width) * 0.5),
            y: max(0, (bounds.height - scaledImageSize.height) * 0.5),
            width: scaledImageSize.width,
            height: scaledImageSize.height
        )
    }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        if let onSmartMagnify {
            onSmartMagnify(event)
        } else {
            super.smartMagnify(with: event)
        }
    }

    override func rotate(with event: NSEvent) {
        if let onRotate {
            onRotate(event)
        } else {
            super.rotate(with: event)
        }
    }
}

private final class FilePreviewMagnifyingImageView: NSImageView {
    var onMagnify: ((NSEvent) -> Void)?
    var onSmartMagnify: ((NSEvent) -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    var rotationDegrees = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        if let onSmartMagnify {
            onSmartMagnify(event)
        } else {
            super.smartMagnify(with: event)
        }
    }

    override func rotate(with event: NSEvent) {
        if let onRotate {
            onRotate(event)
        } else {
            super.rotate(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, rotationDegrees != 0 else {
            super.draw(dirtyRect)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byDegrees: CGFloat(rotationDegrees))
        transform.concat()

        let drawSize = rotatedDrawSize(for: image.size)
        let drawRect = CGRect(
            x: -drawSize.width * 0.5,
            y: -drawSize.height * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func rotatedDrawSize(for imageSize: CGSize) -> CGSize {
        let availableSize: CGSize
        if abs(rotationDegrees) % 180 == 90 {
            availableSize = CGSize(width: bounds.height, height: bounds.width)
        } else {
            availableSize = bounds.size
        }
        let scale = min(
            availableSize.width / max(imageSize.width, 1),
            availableSize.height / max(imageSize.height, 1)
        )
        return CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }
}

private struct FilePreviewMediaView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        context.coordinator.update(playerView: playerView, url: url)
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.update(playerView: nsView, url: url)
    }

    final class Coordinator {
        private var currentURL: URL?
        private var player: AVPlayer?

        deinit {
            player?.pause()
        }

        func update(playerView: AVPlayerView, url: URL) {
            guard currentURL != url else { return }
            player?.pause()
            currentURL = url
            let player = AVPlayer(url: url)
            self.player = player
            playerView.player = player
        }
    }
}

private struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL
    let title: String

    func makeNSView(context: Context) -> NSView {
        guard let previewView = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView()
        }
        previewView.autostarts = true
        previewView.previewItem = context.coordinator.item(for: url, title: title)
        return previewView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewView = nsView as? QLPreviewView else { return }
        previewView.previewItem = context.coordinator.item(for: url, title: title)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var item: FilePreviewQLItem?

        func item(for url: URL, title: String) -> FilePreviewQLItem {
            if let item, item.url == url, item.title == title {
                return item
            }
            let next = FilePreviewQLItem(url: url, title: title)
            item = next
            return next
        }
    }
}

private final class FilePreviewQLItem: NSObject, QLPreviewItem {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    var previewItemURL: URL? {
        url
    }

    var previewItemTitle: String? {
        title
    }
}

private struct FilePreviewPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> FilePreviewPointerObserverView {
        let view = FilePreviewPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: FilePreviewPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

private final class FilePreviewPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  !self.isHiddenOrHasHiddenAncestor else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                DispatchQueue.main.async { [weak self] in
                    self?.onPointerDown?()
                }
            }
            return event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
