import UIKit

@MainActor
protocol GhosttySurfaceViewDelegate: AnyObject {
    func ghosttySurfaceView(_ surfaceView: GhosttySurfaceView, didProduceInput data: Data)
    func ghosttySurfaceView(_ surfaceView: GhosttySurfaceView, didResize size: TerminalGridSize)
}

@MainActor
protocol TerminalSurfaceHosting: AnyObject {
    var currentGridSize: TerminalGridSize { get }
    func processOutput(_ data: Data)
    func focusInput()
}

extension TerminalSurfaceHosting {
    func focusInput() {}
}

final class GhosttySurfaceBridge {
    weak var surfaceView: GhosttySurfaceView?

    func attach(to surfaceView: GhosttySurfaceView) {
        self.surfaceView = surfaceView
    }

    func detach() {
        surfaceView = nil
    }

    func handleWrite(_ bytes: Data) {
        Task { @MainActor [weak self] in
            guard let surfaceView = self?.surfaceView else { return }
            surfaceView.handleOutboundBytes(bytes)
        }
    }

    func handleCloseSurface(processAlive: Bool) {
        Task { @MainActor [weak self] in
            guard let surfaceView = self?.surfaceView else { return }
            NotificationCenter.default.post(
                name: .ghosttySurfaceDidRequestClose,
                object: surfaceView,
                userInfo: ["process_alive": processAlive]
            )
        }
    }

    static func fromOpaque(_ userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceBridge? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceBridge>.fromOpaque(userdata).takeUnretainedValue()
    }
}

private enum GhosttySurfaceDisposer {
    static let queue = DispatchQueue(label: "GhosttySurfaceDisposer.queue")

    static func dispose(surface: ghostty_surface_t, bridge: GhosttySurfaceBridge) {
        let retainedBridge = Unmanaged.passRetained(bridge)
        queue.async {
            ghostty_surface_free(surface)
            retainedBridge.release()
        }
    }
}

struct TerminalTextInputPipeline {
    struct Result: Equatable {
        var committedText: String?
        var nextBufferText: String
    }

    static func process(text: String, isComposing: Bool) -> Result {
        guard !isComposing else {
            return Result(committedText: nil, nextBufferText: text)
        }
        guard !text.isEmpty else {
            return Result(committedText: nil, nextBufferText: "")
        }
        return Result(committedText: text, nextBufferText: "")
    }
}

private struct TerminalHardwareKeyCommand: Sendable {
    let input: String
    let modifierFlags: UIKeyModifierFlags
}

private enum TerminalHardwareKeyResolver {
    private static let supportedModifierFlags: UIKeyModifierFlags = [.shift, .control, .alternate]
    private static let keyCommands: [TerminalHardwareKeyCommand] = {
        let navigation = [
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [.alternate]),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [.alternate]),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputHome, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputEnd, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputPageUp, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputPageDown, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputDelete, modifierFlags: []),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputDelete, modifierFlags: [.alternate]),
            TerminalHardwareKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: []),
            TerminalHardwareKeyCommand(input: "\t", modifierFlags: []),
            TerminalHardwareKeyCommand(input: "\t", modifierFlags: [.shift]),
        ]
        let controlInputs = Array("abcdefghijklmnopqrstuvwxyz[]\\ 234567/").map(String.init)
            .map { TerminalHardwareKeyCommand(input: $0, modifierFlags: [.control]) }
        let shiftedControlInputs = Array("@^_?").map(String.init)
            .map { TerminalHardwareKeyCommand(input: $0, modifierFlags: [.control, .shift]) }
        return navigation + controlInputs + shiftedControlInputs
    }()

    static func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand] {
        keyCommands.map { command in
            UIKeyCommand(
                input: command.input,
                modifierFlags: command.modifierFlags,
                action: action
            )
        }
    }

    static func data(input: String, modifierFlags: UIKeyModifierFlags) -> Data? {
        let normalizedFlags = modifierFlags.intersection(supportedModifierFlags)

        switch (input, normalizedFlags) {
        case (UIKeyCommand.inputLeftArrow, [.alternate]):
            return Data([0x1B, 0x62])
        case (UIKeyCommand.inputRightArrow, [.alternate]):
            return Data([0x1B, 0x66])
        case (UIKeyCommand.inputUpArrow, []):
            return Data([0x1B, 0x5B, 0x41])
        case (UIKeyCommand.inputDownArrow, []):
            return Data([0x1B, 0x5B, 0x42])
        case (UIKeyCommand.inputRightArrow, []):
            return Data([0x1B, 0x5B, 0x43])
        case (UIKeyCommand.inputLeftArrow, []):
            return Data([0x1B, 0x5B, 0x44])
        case (UIKeyCommand.inputHome, []):
            return Data([0x1B, 0x5B, 0x48])
        case (UIKeyCommand.inputEnd, []):
            return Data([0x1B, 0x5B, 0x46])
        case (UIKeyCommand.inputPageUp, []):
            return Data([0x1B, 0x5B, 0x35, 0x7E])
        case (UIKeyCommand.inputPageDown, []):
            return Data([0x1B, 0x5B, 0x36, 0x7E])
        case (UIKeyCommand.inputDelete, []):
            return Data([0x1B, 0x5B, 0x33, 0x7E])
        case (UIKeyCommand.inputDelete, [.alternate]):
            return Data([0x1B, 0x7F])
        case (UIKeyCommand.inputEscape, []):
            return Data([0x1B])
        case ("\t", []):
            return Data([0x09])
        case ("\t", [.shift]):
            return Data([0x1B, 0x5B, 0x5A])
        case let (input, flags) where flags == [.control] || flags == [.control, .shift]:
            return controlCharacter(for: input)
        default:
            return nil
        }
    }

    private static func controlCharacter(for input: String) -> Data? {
        switch input {
        case " ":
            return Data([0x00])
        case "2":
            return Data([0x00])
        case "3":
            return Data([0x1B])
        case "4":
            return Data([0x1C])
        case "5":
            return Data([0x1D])
        case "6":
            return Data([0x1E])
        case "7":
            return Data([0x1F])
        case "/":
            return Data([0x1F])
        case "?":
            return Data([0x7F])
        default:
            break
        }

        guard let scalar = input.uppercased().unicodeScalars.first,
              input.unicodeScalars.count == 1 else { return nil }

        guard (0x40...0x5F).contains(scalar.value) else { return nil }
        return Data([UInt8(scalar.value & 0x1F)])
    }
}

enum TerminalInputAccessoryAction: Int, CaseIterable {
    case control
    case alternate
    case escape
    case tab
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow

    var title: String {
        switch self {
        case .control:
            return String(localized: "terminal.input_accessory.control", defaultValue: "Ctrl")
        case .alternate:
            return String(localized: "terminal.input_accessory.alt", defaultValue: "Alt")
        case .escape:
            return String(localized: "terminal.input_accessory.escape", defaultValue: "Esc")
        case .tab:
            return String(localized: "terminal.input_accessory.tab", defaultValue: "Tab")
        case .upArrow:
            return String(localized: "terminal.input_accessory.up", defaultValue: "↑")
        case .downArrow:
            return String(localized: "terminal.input_accessory.down", defaultValue: "↓")
        case .leftArrow:
            return String(localized: "terminal.input_accessory.left", defaultValue: "←")
        case .rightArrow:
            return String(localized: "terminal.input_accessory.right", defaultValue: "→")
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .control:
            return "terminal.inputAccessory.control"
        case .alternate:
            return "terminal.inputAccessory.alt"
        case .escape:
            return "terminal.inputAccessory.escape"
        case .tab:
            return "terminal.inputAccessory.tab"
        case .upArrow:
            return "terminal.inputAccessory.up"
        case .downArrow:
            return "terminal.inputAccessory.down"
        case .leftArrow:
            return "terminal.inputAccessory.left"
        case .rightArrow:
            return "terminal.inputAccessory.right"
        }
    }

    var output: Data? {
        switch self {
        case .control, .alternate:
            return nil
        case .escape:
            return Data([0x1B])
        case .tab:
            return Data([0x09])
        case .upArrow:
            return Data([0x1B, 0x5B, 0x41])
        case .downArrow:
            return Data([0x1B, 0x5B, 0x42])
        case .leftArrow:
            return Data([0x1B, 0x5B, 0x44])
        case .rightArrow:
            return Data([0x1B, 0x5B, 0x43])
        }
    }
}

final class GhosttySurfaceView: UIView, TerminalSurfaceHosting {
    private weak var runtime: GhosttyRuntime?
    private weak var delegate: GhosttySurfaceViewDelegate?
    private let fontSize: Float32
    private let bridge = GhosttySurfaceBridge()
    private let prefersSnapshotFallbackRendering = true
    var onFocusInputRequestedForTesting: (() -> Void)?
    private var surfaceTitle: String?
    private let snapshotFallbackView: UITextView = {
        let view = UITextView()
        view.backgroundColor = .black
        view.textColor = .white
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.textContainer.lineFragmentPadding = 0
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.isUserInteractionEnabled = false
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.isHidden = true
        return view
    }()

    private(set) var surface: ghostty_surface_t?
    private var lastReportedSize: TerminalGridSize?
    private var lastSnapshotFallbackHTML: String?

    var currentGridSize: TerminalGridSize {
        lastReportedSize ?? TerminalGridSize(columns: 100, rows: 32, pixelWidth: 900, pixelHeight: 650)
    }

    private lazy var inputProxy: TerminalInputTextView = {
        let inputProxy = TerminalInputTextView()
        inputProxy.onText = { [weak self] text in
            self?.sendText(text)
        }
        inputProxy.onBackspace = { [weak self] in
            self?.sendText("\u{7f}")
        }
        inputProxy.onEscapeSequence = { [weak self] data in
            guard let self else { return }
            self.delegate?.ghosttySurfaceView(self, didProduceInput: data)
        }
        return inputProxy
    }()

    init(runtime: GhosttyRuntime, delegate: GhosttySurfaceViewDelegate, fontSize: Float32 = 14) {
        self.runtime = runtime
        self.delegate = delegate
        self.fontSize = fontSize
        super.init(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        bridge.attach(to: self)
        backgroundColor = .black
        isOpaque = true
        addSubview(snapshotFallbackView)
        addSubview(inputProxy)
        initializeSurface()

        let tap = UITapGestureRecognizer(target: self, action: #selector(focusInput))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        disposeSurface()
    }

    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        snapshotFallbackView.frame = bounds
        inputProxy.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        liveAnchormuxLog("surface.layout bounds=\(Int(bounds.width))x\(Int(bounds.height)) window=\(window != nil)")
        syncSurfaceGeometry()
        syncSurfaceVisibility()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        liveAnchormuxLog("surface.didMoveToWindow window=\(window != nil)")
        syncSurfaceGeometry()
        syncSurfaceVisibility()
        setFocus(window != nil)
        if window != nil {
            focusInput()
        }
    }

    func processOutput(_ data: Data) {
        guard let surface else { return }
        liveAnchormuxLog("surface.processOutput bytes=\(data.count) window=\(window != nil) bounds=\(Int(bounds.width))x\(Int(bounds.height))")
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let pointer = baseAddress.assumingMemoryBound(to: CChar.self)
            ghostty_surface_process_output(surface, pointer, UInt(buffer.count))
        }
        ghostty_surface_refresh(surface)
        runtime?.tick()
        ghostty_surface_draw(surface)
        syncSnapshotFallback()
        if window != nil {
            logLayerTree(reason: "processOutput")
            let preview = renderedTextForTesting()?
                .replacingOccurrences(of: "\n", with: "\\n")
                .prefix(160) ?? ""
            liveAnchormuxLog("surface.viewportText chars=\(preview.count) preview=\(preview)")
        }
    }

    @objc
    func focusInput() {
        onFocusInputRequestedForTesting?()
        inputProxy.becomeFirstResponder()
    }

    func simulateTextInputForTesting(_ text: String) {
        setFocus(true)
        sendText(text)
        runtime?.tick()
    }

    func simulatePasteInputForTesting(_ text: String) {
        setFocus(true)
        sendPaste(text)
        runtime?.tick()
    }

    func simulateInputProxyTextChangeForTesting(_ text: String, isComposing: Bool) {
        setFocus(true)
        inputProxy.simulateTextChangeForTesting(text, isComposing: isComposing)
        runtime?.tick()
    }

    func renderedTextForTesting(pointTag: ghostty_point_tag_e = GHOSTTY_POINT_VIEWPORT) -> String? {
        guard let surface else { return nil }

        let topLeft = ghostty_point_s(
            tag: pointTag,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: 0
        )
        let bottomRight = ghostty_point_s(
            tag: pointTag,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0,
            y: 0
        )
        let selection = ghostty_selection_s(
            top_left: topLeft,
            bottom_right: bottomRight,
            rectangle: false
        )

        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else {
            return nil
        }
        defer {
            ghostty_surface_free_text(surface, &text)
        }

        guard let ptr = text.text, text.text_len > 0 else {
            return ""
        }

        let data = Data(bytes: ptr, count: Int(text.text_len))
        return String(decoding: data, as: UTF8.self)
    }

    func renderedHTMLForTesting(pointTag: ghostty_point_tag_e = GHOSTTY_POINT_VIEWPORT) -> String? {
        guard let surface else { return nil }

        let topLeft = ghostty_point_s(
            tag: pointTag,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: 0
        )
        let bottomRight = ghostty_point_s(
            tag: pointTag,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0,
            y: 0
        )
        let selection = ghostty_selection_s(
            top_left: topLeft,
            bottom_right: bottomRight,
            rectangle: false
        )

        // ghostty_surface_read_text_html not available in this build
        return nil
    }

    func processExitedForTesting() -> Bool {
        guard let surface else { return false }
        return ghostty_surface_process_exited(surface)
    }

    func disposeSurface() {
        guard let surface else { return }
        GhosttySurfaceView.unregister(surface: surface)
        self.surface = nil
        bridge.detach()
        GhosttySurfaceDisposer.dispose(surface: surface, bridge: bridge)
    }

    private var preferredScreenScale: CGFloat {
        if let screen = window?.windowScene?.screen {
            return screen.scale
        }

        let traitScale = traitCollection.displayScale
        return traitScale > 0 ? traitScale : 2
    }

    private func sendText(_ text: String) {
        guard let surface else { return }
        let count = text.utf8CString.count
        guard count > 0 else { return }
        text.withCString { pointer in
            ghostty_surface_text_input(surface, pointer, UInt(count - 1))
        }
    }

    private func sendPaste(_ text: String) {
        guard let surface else { return }
        let count = text.utf8CString.count
        guard count > 0 else { return }
        text.withCString { pointer in
            ghostty_surface_text(surface, pointer, UInt(count - 1))
        }
    }

    private func initializeSurface() {
        guard let app = runtime?.app else { return }
        surface = makeSurface(app: app)
        if let surface {
            GhosttySurfaceView.register(surface: surface, for: self)
        }
        syncSurfaceGeometry()
    }

    private func setFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    private func syncSurfaceVisibility() {
        guard let surface else { return }
        let visible = window != nil &&
            !isHidden &&
            alpha > 0.01 &&
            bounds.width > 0 &&
            bounds.height > 0
        liveAnchormuxLog("surface.occlusion visible=\(visible) window=\(window != nil) hidden=\(isHidden) alpha=\(alpha)")
        ghostty_surface_set_occlusion(surface, visible)
    }

    private func syncSurfaceGeometry() {
        guard let surface else { return }

        let scale = preferredScreenScale
        syncRendererLayerFrame(scale: scale)
        ghostty_surface_set_content_scale(surface, scale, scale)

        let width = UInt32(max(1, Int((bounds.width * scale).rounded(.down))))
        let height = UInt32(max(1, Int((bounds.height * scale).rounded(.down))))
        ghostty_surface_set_size(surface, width, height)

        let size = ghostty_surface_size(surface)
        let nextSize = TerminalGridSize(
            columns: Int(size.columns),
            rows: Int(size.rows),
            pixelWidth: Int(size.width_px),
            pixelHeight: Int(size.height_px)
        )
        liveAnchormuxLog(
            "surface.geometry bounds=\(Int(bounds.width))x\(Int(bounds.height)) px=\(nextSize.pixelWidth)x\(nextSize.pixelHeight) cols=\(nextSize.columns) rows=\(nextSize.rows)"
        )
        ghostty_surface_refresh(surface)
        runtime?.tick()
        ghostty_surface_draw(surface)
        syncSnapshotFallback()
        if window != nil {
            logLayerTree(reason: "geometry")
        }
        guard nextSize != lastReportedSize else { return }
        lastReportedSize = nextSize
        delegate?.ghosttySurfaceView(self, didResize: nextSize)
    }

    private func syncRendererLayerFrame(scale: CGFloat) {
        layer.contentsScale = scale
        for sublayer in layer.sublayers ?? [] where isGhosttyRendererLayer(sublayer) {
            if sublayer.frame != layer.bounds {
                sublayer.frame = layer.bounds
            }
            if sublayer.bounds.size != layer.bounds.size {
                sublayer.bounds = layer.bounds
            }
            sublayer.contentsScale = scale
        }
    }

    private func isGhosttyRendererLayer(_ layer: CALayer) -> Bool {
        String(describing: type(of: layer)) == "IOSurfaceLayer"
    }

    private func logLayerTree(reason: String) {
        let hostLayer = layer
        let hostSummary = "\(type(of: hostLayer)) bounds=\(hostLayer.bounds.integral.debugDescription) frame=\(hostLayer.frame.integral.debugDescription) contentsScale=\(hostLayer.contentsScale)"
        let childSummaries = (hostLayer.sublayers ?? []).prefix(4).enumerated().map { index, sublayer in
            "\(index):\(type(of: sublayer)) bounds=\(sublayer.bounds.integral.debugDescription) frame=\(sublayer.frame.integral.debugDescription) hidden=\(sublayer.isHidden) contents=\(sublayer.contents != nil) scale=\(sublayer.contentsScale)"
        }.joined(separator: " | ")
        liveAnchormuxLog("surface.layers reason=\(reason) host=\(hostSummary) children=[\(childSummaries)] fallbackHidden=\(snapshotFallbackView.isHidden) fallbackChars=\(snapshotFallbackView.text.count)")
    }

    private func makeSurface(app: ghostty_app_t) -> ghostty_surface_t? {
        var surfaceConfig = ghostty_surface_config_new()
        let bridgePointer = Unmanaged.passUnretained(bridge).toOpaque()
        surfaceConfig.userdata = bridgePointer
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_IOS
        surfaceConfig.platform = ghostty_platform_u(
            ios: ghostty_platform_ios_s(uiview: Unmanaged.passUnretained(self).toOpaque())
        )
        surfaceConfig.scale_factor = preferredScreenScale
        surfaceConfig.font_size = fontSize
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        surfaceConfig.io_mode = GHOSTTY_SURFACE_IO_MANUAL
        surfaceConfig.io_write_cb = { userdata, data, len in
            GhosttySurfaceView.handleWrite(userdata: userdata, data: data, len: len)
        }
        surfaceConfig.io_write_userdata = bridgePointer
        return ghostty_surface_new(app, &surfaceConfig)
    }

    fileprivate func handleOutboundBytes(_ bytes: Data) {
        delegate?.ghosttySurfaceView(self, didProduceInput: bytes)
    }

    func drawForWakeup() {
        guard let surface, window != nil else { return }
        liveAnchormuxLog("surface.drawForWakeup")
        ghostty_surface_draw(surface)
        syncSnapshotFallback()
        logLayerTree(reason: "wakeup")
    }

    func visibleSnapshotTextForTesting() -> String {
        snapshotFallbackView.attributedText?.string ?? snapshotFallbackView.text
    }

    func visibleSnapshotAttributedTextForTesting() -> NSAttributedString? {
        snapshotFallbackView.attributedText
    }

    func isUsingSnapshotFallbackForTesting() -> Bool {
        !snapshotFallbackView.isHidden
    }

    private func syncSnapshotFallback() {
        let rendererHasContents = !prefersSnapshotFallbackRendering &&
            (layer.sublayers ?? []).contains(where: isGhosttyRendererLayerVisible)
        if rendererHasContents {
            snapshotFallbackView.isHidden = true
            return
        }

        let snapshot = renderedTextForTesting() ?? ""
        guard !snapshot.isEmpty else {
            lastSnapshotFallbackHTML = nil
            snapshotFallbackView.attributedText = nil
            snapshotFallbackView.text = ""
            snapshotFallbackView.isHidden = true
            return
        }

        let html = renderedHTMLForTesting()
        if let html,
           html != lastSnapshotFallbackHTML,
           let attributedSnapshot = makeSnapshotAttributedText(from: html) {
            lastSnapshotFallbackHTML = html
            snapshotFallbackView.attributedText = attributedSnapshot
            applySnapshotFallbackTheme(from: attributedSnapshot)
        } else if snapshotFallbackView.attributedText?.string != snapshot {
            lastSnapshotFallbackHTML = nil
            snapshotFallbackView.attributedText = nil
            snapshotFallbackView.text = snapshot
            snapshotFallbackView.backgroundColor = .black
        }

        if snapshotFallbackView.text != snapshot && snapshotFallbackView.attributedText == nil {
            snapshotFallbackView.text = snapshot
        }

        let visibleTextLength = snapshotFallbackView.attributedText?.string.utf16.count ?? snapshotFallbackView.text.utf16.count
        if visibleTextLength > 0 {
            snapshotFallbackView.scrollRangeToVisible(NSRange(location: max(0, visibleTextLength - 1), length: 1))
        }
        snapshotFallbackView.isHidden = false
        flushSnapshotFallbackPresentation()
    }

    private func flushSnapshotFallbackPresentation() {
        snapshotFallbackView.textContainer.size = snapshotFallbackView.bounds.size
        snapshotFallbackView.layoutManager.ensureLayout(for: snapshotFallbackView.textContainer)
        snapshotFallbackView.layoutManager.invalidateDisplay(
            forCharacterRange: NSRange(location: 0, length: snapshotFallbackView.textStorage.length)
        )
        snapshotFallbackView.setNeedsDisplay()
    }

    private func makeSnapshotAttributedText(from html: String) -> NSAttributedString? {
        let wrappedHTML = """
        <style>
        body {
            margin: 0;
            padding: 0;
            font-family: Menlo, Monaco, monospace;
            font-size: 13px;
            line-height: 1.25;
        }
        div, pre {
            white-space: pre-wrap;
        }
        </style>
        \(html)
        """
        guard let wrappedData = wrappedHTML.data(using: .utf8) else { return nil }
        return try? NSMutableAttributedString(
            data: wrappedData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
    }

    private func applySnapshotFallbackTheme(from attributedText: NSAttributedString) {
        guard attributedText.length > 0 else {
            snapshotFallbackView.backgroundColor = .black
            return
        }

        let probeIndex = firstVisibleThemeAttributeIndex(in: attributedText)
        if let background = attributedText.attribute(.backgroundColor, at: probeIndex, effectiveRange: nil) as? UIColor {
            snapshotFallbackView.backgroundColor = background
        } else {
            snapshotFallbackView.backgroundColor = .black
        }
    }

    private func firstVisibleThemeAttributeIndex(in attributedText: NSAttributedString) -> Int {
        let fullString = attributedText.string
        for (index, scalar) in fullString.unicodeScalars.enumerated() {
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return index
            }
        }
        return 0
    }

    private func isGhosttyRendererLayerVisible(_ layer: CALayer) -> Bool {
        isGhosttyRendererLayer(layer) && layer.contents != nil
    }

    nonisolated private static func handleWrite(
        userdata: UnsafeMutableRawPointer?,
        data: UnsafePointer<CChar>?,
        len: UInt
    ) {
        guard let userdata, let data, len > 0 else { return }
        let bytes = Data(bytes: data, count: Int(len))
        GhosttySurfaceBridge.fromOpaque(userdata)?.handleWrite(bytes)
    }

    @MainActor
    static func focusInput(for surface: ghostty_surface_t) {
        view(for: surface)?.focusInput()
    }

    @MainActor
    static func setTitle(_ title: String, for surface: ghostty_surface_t) {
        view(for: surface)?.surfaceTitle = title
    }

    @MainActor
    static func ringBell(for surface: ghostty_surface_t) {
        view(for: surface)?.handleBell()
    }

    @MainActor
    static func title(for surface: ghostty_surface_t) -> String? {
        view(for: surface)?.surfaceTitle
    }

    @MainActor
    static func drawVisibleSurfacesForWakeup() {
        registeredSurfaceViews = registeredSurfaceViews.filter { $0.value.value != nil }
        for view in registeredSurfaceViews.values.compactMap(\.value) {
            view.drawForWakeup()
        }
    }

    private func handleBell() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        NotificationCenter.default.post(
            name: .ghosttySurfaceDidRingBell,
            object: self
        )
    }
}

private final class WeakGhosttySurfaceViewBox {
    weak var value: GhosttySurfaceView?

    init(_ value: GhosttySurfaceView) {
        self.value = value
    }
}

private extension GhosttySurfaceView {
    @MainActor
    static var registeredSurfaceViews: [UInt: WeakGhosttySurfaceViewBox] = [:]

    @MainActor
    static func register(surface: ghostty_surface_t, for view: GhosttySurfaceView) {
        registeredSurfaceViews[surfaceIdentifier(for: surface)] = WeakGhosttySurfaceViewBox(view)
        registeredSurfaceViews = registeredSurfaceViews.filter { $0.value.value != nil }
    }

    @MainActor
    static func unregister(surface: ghostty_surface_t) {
        registeredSurfaceViews.removeValue(forKey: surfaceIdentifier(for: surface))
    }

    @MainActor
    static func view(for surface: ghostty_surface_t) -> GhosttySurfaceView? {
        let identifier = surfaceIdentifier(for: surface)
        guard let view = registeredSurfaceViews[identifier]?.value else {
            registeredSurfaceViews.removeValue(forKey: identifier)
            return nil
        }
        return view
    }

    static func surfaceIdentifier(for surface: ghostty_surface_t) -> UInt {
        UInt(bitPattern: UnsafeRawPointer(surface))
    }
}

final class TerminalInputTextView: UITextView {
    var onText: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onEscapeSequence: ((Data) -> Void)?
    private var controlAccessoryArmed = false
    private var alternateAccessoryArmed = false

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard markedTextRange == nil else { return nil }
        return TerminalHardwareKeyResolver.makeKeyCommands(
            target: self,
            action: #selector(handleHardwareKeyCommand(_:))
        )
    }

    private lazy var terminalAccessoryToolbar: UIView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center

        for action in TerminalInputAccessoryAction.allCases {
            let button = UIButton(type: .system)
            button.setTitle(action.title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.tag = action.rawValue
            button.addTarget(self, action: #selector(handleAccessoryButton(_:)), for: .touchUpInside)
            button.accessibilityIdentifier = action.accessibilityIdentifier
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            button.backgroundColor = UIColor.secondarySystemFill
            button.layer.cornerRadius = 6
            stack.addArrangedSubview(button)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        scrollView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44)
        accessoryStackView = stack
        return scrollView
    }()

    private weak var accessoryStackView: UIStackView?

    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        keyboardType = .default
        returnKeyType = .default
        textContainerInset = .zero
        inputAccessoryView = terminalAccessoryToolbar
        delegate = self
        text = ""
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func deleteBackward() {
        if alternateAccessoryArmed, markedTextRange == nil, !hasText {
            setAlternateAccessoryArmed(false)
            if let output = TerminalHardwareKeyResolver.data(
                input: UIKeyCommand.inputDelete,
                modifierFlags: [.alternate]
            ) {
                onEscapeSequence?(output)
            }
            return
        }
        if controlAccessoryArmed, markedTextRange == nil, !hasText {
            setControlAccessoryArmed(false)
            onBackspace?()
            return
        }
        if markedTextRange != nil || hasText {
            super.deleteBackward()
            return
        }
        onBackspace?()
    }

    func simulateTextChangeForTesting(_ text: String, isComposing: Bool) {
        self.text = text
        handleTextChange(currentText: text, isComposing: isComposing)
    }

    func simulateHardwareKeyCommandForTesting(input: String, modifierFlags: UIKeyModifierFlags) -> Bool {
        handleHardwareKeyInput(input: input, modifierFlags: modifierFlags)
    }

    func simulateAccessoryActionForTesting(_ action: TerminalInputAccessoryAction) {
        handleAccessoryAction(action)
    }

    @objc
    private func handleHardwareKeyCommand(_ sender: UIKeyCommand) {
        guard let input = sender.input else { return }
        _ = handleHardwareKeyInput(input: input, modifierFlags: sender.modifierFlags)
    }

    @objc
    private func handleAccessoryButton(_ sender: UIBarButtonItem) {
        guard let action = TerminalInputAccessoryAction(rawValue: sender.tag) else { return }
        handleAccessoryAction(action)
    }

    @discardableResult
    private func handleHardwareKeyInput(input: String, modifierFlags: UIKeyModifierFlags) -> Bool {
        guard let data = TerminalHardwareKeyResolver.data(input: input, modifierFlags: modifierFlags) else {
            return false
        }
        onEscapeSequence?(data)
        return true
    }

    private func handleAccessoryAction(_ action: TerminalInputAccessoryAction) {
        if controlAccessoryArmed,
           action != .control,
           action != .alternate {
            setControlAccessoryArmed(false)
            if let output = action.output {
                onEscapeSequence?(output)
            }
            return
        }

        if alternateAccessoryArmed,
           action != .alternate,
           action != .control {
            setAlternateAccessoryArmed(false)
            if let output = alternateAccessoryOutput(for: action) {
                onEscapeSequence?(output)
            }
            return
        }

        switch action {
        case .control:
            let shouldArm = !controlAccessoryArmed
            setAlternateAccessoryArmed(false)
            setControlAccessoryArmed(shouldArm)
        case .alternate:
            let shouldArm = !alternateAccessoryArmed
            setControlAccessoryArmed(false)
            setAlternateAccessoryArmed(shouldArm)
        default:
            if let output = action.output {
                onEscapeSequence?(output)
            }
        }
    }

    private func refreshAccessoryButtonStyles() {
        guard let stack = accessoryStackView else { return }
        for case let button as UIButton in stack.arrangedSubviews {
            guard let action = TerminalInputAccessoryAction(rawValue: button.tag) else { continue }
            let armed = isAccessoryActionArmed(action)
            button.backgroundColor = armed ? .systemBlue : UIColor.secondarySystemFill
            button.setTitleColor(armed ? .white : .label, for: .normal)
        }
    }

    private func handleTextChange(currentText: String, isComposing: Bool) {
        let result = TerminalTextInputPipeline.process(text: currentText, isComposing: isComposing)
        if let committedText = result.committedText {
            if controlAccessoryArmed {
                setControlAccessoryArmed(false)
                if let controlSequence = controlSequence(for: committedText) {
                    onEscapeSequence?(controlSequence)
                } else {
                    onText?(committedText)
                }
            } else if alternateAccessoryArmed {
                setAlternateAccessoryArmed(false)
                if let alternateSequence = alternateSequence(for: committedText) {
                    onEscapeSequence?(alternateSequence)
                } else {
                    onText?(committedText)
                }
            } else {
                onText?(committedText)
            }
        }
        if text != result.nextBufferText {
            text = result.nextBufferText
        }
    }

    private func controlSequence(for text: String) -> Data? {
        guard text.count == 1 else { return nil }
        return TerminalHardwareKeyResolver.data(input: text, modifierFlags: [.control])
    }

    private func alternateSequence(for text: String) -> Data? {
        guard let encoded = text.data(using: .utf8), !encoded.isEmpty else { return nil }
        var sequence = Data([0x1B])
        sequence.append(encoded)
        return sequence
    }

    private func alternateAccessoryOutput(for action: TerminalInputAccessoryAction) -> Data? {
        switch action {
        case .leftArrow:
            return TerminalHardwareKeyResolver.data(
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [.alternate]
            )
        case .rightArrow:
            return TerminalHardwareKeyResolver.data(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [.alternate]
            )
        case .control, .alternate:
            return nil
        default:
            guard let output = action.output else { return nil }
            var sequence = Data([0x1B])
            sequence.append(output)
            return sequence
        }
    }

    private func isAccessoryActionArmed(_ action: TerminalInputAccessoryAction) -> Bool {
        switch action {
        case .control:
            return controlAccessoryArmed
        case .alternate:
            return alternateAccessoryArmed
        default:
            return false
        }
    }

    private func setControlAccessoryArmed(_ armed: Bool) {
        guard controlAccessoryArmed != armed else { return }
        controlAccessoryArmed = armed
        refreshAccessoryButtonStyles()
    }

    private func setAlternateAccessoryArmed(_ armed: Bool) {
        guard alternateAccessoryArmed != armed else { return }
        alternateAccessoryArmed = armed
        refreshAccessoryButtonStyles()
    }
}

extension TerminalInputTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        true
    }

    func textViewDidChange(_ textView: UITextView) {
        handleTextChange(
            currentText: textView.text ?? "",
            isComposing: textView.markedTextRange != nil
        )
    }
}
