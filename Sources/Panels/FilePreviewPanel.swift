import AppKit
import AVKit
import Bonsplit
import Combine
import Foundation
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

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
            textContent = decoded
            originalTextContent = decoded
            isDirty = false
            isFileUnavailable = false
        } catch {
            isFileUnavailable = true
        }
    }

    func saveTextContent() {
        guard previewMode == .text else { return }
        do {
            try textContent.write(to: fileURL, atomically: true, encoding: .utf8)
            originalTextContent = textContent
            isDirty = false
            isFileUnavailable = false
        } catch {
            isFileUnavailable = true
        }
    }

    private static func decodeText(_ data: Data) -> String? {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        if let decoded = String(data: data, encoding: .utf16) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1)
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
            header
            Divider()
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
    weak var panel: FilePreviewPanel?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            panel?.saveTextContent()
            return true
        }
        return super.performKeyEquivalent(with: event)
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

private final class FilePreviewPDFContainerView: NSView {
    private let pdfView = FilePreviewMagnifyingPDFView()
    private let pageLabel = NSTextField(labelWithString: "")
    private var currentURL: URL?
    private var previousButton: NSButton!
    private var nextButton: NSButton!

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
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        updatePageControls()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        previousButton = makeToolbarButton(
            systemSymbolName: "chevron.left",
            fallbackTitle: "<",
            label: String(localized: "filePreview.pdf.previousPage", defaultValue: "Previous Page"),
            action: #selector(previousPage)
        )
        nextButton = makeToolbarButton(
            systemSymbolName: "chevron.right",
            fallbackTitle: ">",
            label: String(localized: "filePreview.pdf.nextPage", defaultValue: "Next Page"),
            action: #selector(nextPage)
        )
        let zoomOutButton = makeToolbarButton(
            systemSymbolName: "minus.magnifyingglass",
            fallbackTitle: "-",
            label: String(localized: "filePreview.pdf.zoomOut", defaultValue: "Zoom Out"),
            action: #selector(zoomOut)
        )
        let zoomInButton = makeToolbarButton(
            systemSymbolName: "plus.magnifyingglass",
            fallbackTitle: "+",
            label: String(localized: "filePreview.pdf.zoomIn", defaultValue: "Zoom In"),
            action: #selector(zoomIn)
        )
        let fitButton = makeToolbarButton(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            fallbackTitle: "Fit",
            label: String(localized: "filePreview.pdf.zoomToFit", defaultValue: "Zoom to Fit"),
            action: #selector(zoomToFit)
        )
        let actualSizeButton = makeToolbarButton(
            systemSymbolName: "1.magnifyingglass",
            fallbackTitle: "1x",
            label: String(localized: "filePreview.pdf.actualSize", defaultValue: "Actual Size"),
            action: #selector(actualSize)
        )

        pageLabel.font = .systemFont(ofSize: 11)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center
        pageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolbar = NSStackView(views: [
            previousButton,
            nextButton,
            pageLabel,
            zoomOutButton,
            zoomInButton,
            fitButton,
            actualSizeButton,
        ])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .textBackgroundColor
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 8.0
        pdfView.onMagnify = { [weak self] event in
            self?.magnifyPDF(with: event)
        }
        pdfView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(toolbar)
        addSubview(pdfView)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 34),
            pdfView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfPageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
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

    @objc private func previousPage() {
        pdfView.goToPreviousPage(nil)
        updatePageControls()
    }

    @objc private func nextPage() {
        pdfView.goToNextPage(nil)
        updatePageControls()
    }

    @objc private func zoomOut() {
        pdfView.autoScales = false
        setPDFScaleFactor(pdfView.scaleFactor / 1.25)
    }

    @objc private func zoomIn() {
        pdfView.autoScales = false
        setPDFScaleFactor(pdfView.scaleFactor * 1.25)
    }

    @objc private func zoomToFit() {
        pdfView.autoScales = true
    }

    @objc private func actualSize() {
        pdfView.autoScales = false
        setPDFScaleFactor(1.0)
    }

    @objc private func pdfPageChanged() {
        updatePageControls()
    }

    private func updatePageControls() {
        guard let document = pdfView.document, document.pageCount > 0 else {
            pageLabel.stringValue = ""
            previousButton.isEnabled = false
            nextButton.isEnabled = false
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
        previousButton.isEnabled = pageIndex > 0
        nextButton.isEnabled = pageIndex < document.pageCount - 1
    }

    private func magnifyPDF(with event: NSEvent) {
        guard pdfView.document != nil else { return }
        let factor = 1.0 + event.magnification
        guard factor.isFinite, factor > 0 else { return }
        pdfView.autoScales = false
        setPDFScaleFactor(pdfView.scaleFactor * factor)
    }

    private func setPDFScaleFactor(_ nextScale: CGFloat) {
        let clamped = min(max(nextScale, pdfView.minScaleFactor), pdfView.maxScaleFactor)
        guard clamped.isFinite else { return }
        pdfView.scaleFactor = clamped
    }
}

private final class FilePreviewMagnifyingPDFView: PDFView {
    var onMagnify: ((NSEvent) -> Void)?

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
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

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .right
        zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let toolbar = NSStackView(views: [
            zoomOutButton,
            zoomInButton,
            fitButton,
            actualSizeButton,
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
            self?.magnifyImage(with: event)
        }
        documentView.onMagnify = { [weak self] event in
            self?.magnifyImage(with: event)
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
        scale = clampedImageScale(scale / 1.25)
        applyScale()
    }

    @objc private func zoomIn() {
        isFitMode = false
        scale = clampedImageScale(scale * 1.25)
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

    private func fitScale() -> CGFloat {
        let clipSize = scrollView.contentView.bounds.size
        guard clipSize.width > 1, clipSize.height > 1 else { return scale }
        let widthScale = clipSize.width / max(imageSize.width, 1)
        let heightScale = clipSize.height / max(imageSize.height, 1)
        return clampedImageScale(min(widthScale, heightScale))
    }

    private func applyScale() {
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
        documentView.needsLayout = true
        zoomLabel.stringValue = "\(Int((scale * 100).rounded()))%"
    }

    private func magnifyImage(with event: NSEvent) {
        guard documentView.imageView.image != nil else { return }
        let factor = 1.0 + event.magnification
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

    private func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width), height: max(1, size.height))
    }
}

private final class FilePreviewImageScrollView: NSScrollView {
    var onMagnify: ((NSEvent) -> Void)?

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }
}

private final class FilePreviewImageDocumentView: NSView {
    let imageView = FilePreviewMagnifyingImageView()
    var scaledImageSize = CGSize(width: 1, height: 1)
    var onMagnify: ((NSEvent) -> Void)? {
        didSet {
            imageView.onMagnify = onMagnify
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
}

private final class FilePreviewMagnifyingImageView: NSImageView {
    var onMagnify: ((NSEvent) -> Void)?

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
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
