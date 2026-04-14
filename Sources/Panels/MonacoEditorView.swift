import AppKit
import Combine
import SwiftUI
import WebKit

/// Monaco-based editor surface. Runs the bundled Vite app inside a WKWebView
/// and mirrors buffer + view-state across the JS bridge so save/restore
/// behavior matches the native `EditorPanelView` backend.
struct MonacoEditorView: View {
    @ObservedObject var panel: EditorPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if panel.isFileUnavailable {
                fileUnavailableView
            } else {
                VStack(spacing: 0) {
                    filePathHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                    Divider()
                        .padding(.horizontal, 8)
                    MonacoWebViewRepresentable(
                        panel: panel,
                        isFocused: isFocused,
                        onRequestPanelFocus: onRequestPanelFocus
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
    }

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text(panel.filePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private var fileUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "editor.fileUnavailable.title", defaultValue: "File unavailable"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(panel.filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Text(String(localized: "editor.fileUnavailable.message", defaultValue: "The file may have been moved or deleted."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
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

// MARK: - WKWebView bridge

private struct MonacoWebViewRepresentable: NSViewRepresentable {
    let panel: EditorPanel
    let isFocused: Bool
    let onRequestPanelFocus: () -> Void

    func makeCoordinator() -> MonacoEditorCoordinator {
        MonacoEditorCoordinator(panel: panel, onRequestPanelFocus: onRequestPanelFocus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let schemeHandler = MonacoSchemeHandler()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: MonacoSchemeHandler.scheme)
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "cmux")
        config.userContentController = userContentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.schemeHandler = schemeHandler

        if let url = URL(string: "\(MonacoSchemeHandler.scheme)://editor/index.html") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.panel = panel
        context.coordinator.onRequestPanelFocus = onRequestPanelFocus
        context.coordinator.syncContentIfNeeded()
        if isFocused {
            context.coordinator.focusEditor()
        }
    }
}

// MARK: - Coordinator

@MainActor
final class MonacoEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var panel: EditorPanel
    var onRequestPanelFocus: () -> Void
    weak var webView: WKWebView?
    var schemeHandler: MonacoSchemeHandler?

    private var isReady = false
    private var lastSyncedContent: String?
    private var panelSubscriptions: Set<AnyCancellable> = []

    init(panel: EditorPanel, onRequestPanelFocus: @escaping () -> Void) {
        self.panel = panel
        self.onRequestPanelFocus = onRequestPanelFocus
        super.init()
        panel.$content
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncContentIfNeeded()
            }
            .store(in: &panelSubscriptions)
    }

    // MARK: - Bridge inbound

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cmux", let dict = message.body as? [String: Any] else { return }
        guard let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            handleReady()
        case "changed":
            handleChanged(payload: dict)
        case "saveRequested":
            if panel.isDirty, !panel.save() {
                EditorSaveAlert.show(for: panel)
            }
        case "viewState":
            handleViewState(payload: dict)
        default:
            break
        }
    }

    private func handleReady() {
        isReady = true
        sendTheme()
        sendInitialState()
    }

    private func handleChanged(payload: [String: Any]) {
        guard let value = payload["value"] as? String else { return }
        if panel.content != value {
            lastSyncedContent = value
            panel.content = value
            panel.markDirty()
        }
        if let cursor = payload["cursor"] as? [String: Any] {
            if let offset = cursor["offset"] as? Int { panel.cursorLocation = offset }
            if let length = cursor["length"] as? Int { panel.cursorLength = length }
        }
    }

    private func handleViewState(payload: [String: Any]) {
        if let cursor = payload["cursor"] as? [String: Any] {
            if let offset = cursor["offset"] as? Int { panel.cursorLocation = offset }
            if let length = cursor["length"] as? Int { panel.cursorLength = length }
        }
        if let frac = payload["scrollTopFraction"] as? Double {
            panel.scrollTopFraction = frac
        }
        if let vs = payload["monacoViewState"] as? String, !vs.isEmpty {
            panel.monacoViewState = vs
        }
        panel.lastOpenedAt = Date().timeIntervalSince1970
    }

    // MARK: - Bridge outbound

    func syncContentIfNeeded() {
        guard isReady else { return }
        if lastSyncedContent == panel.content { return }
        lastSyncedContent = panel.content
        sendSetText(preserveViewState: true)
    }

    func focusEditor() {
        guard isReady else { return }
        send(command: [
            "kind": "focus",
        ])
    }

    private func sendInitialState() {
        sendSetText(preserveViewState: false)
        restoreView()
    }

    private func sendSetText(preserveViewState: Bool) {
        let lang = MonacoLanguageResolver.languageId(for: panel.filePath)
        send(command: [
            "kind": "setText",
            "value": panel.content,
            "languageId": lang,
            "preserveViewState": preserveViewState,
        ])
    }

    private func restoreView() {
        send(command: [
            "kind": "restoreViewState",
            "monacoViewState": panel.monacoViewState ?? "",
            "scrollTopFraction": panel.scrollTopFraction,
            "cursorOffset": panel.cursorLocation,
            "cursorLength": panel.cursorLength,
        ])
    }

    private func sendTheme() {
        let effective = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let isDark = effective == .darkAqua
        let background = MonacoThemeResolver.editorBackgroundHex(isDark: isDark)
        let foreground = MonacoThemeResolver.editorForegroundHex(isDark: isDark)
        send(command: [
            "kind": "setTheme",
            "isDark": isDark,
            "backgroundHex": background,
            "foregroundHex": foreground,
        ])
    }

    private func send(command: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: command),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.cmuxMonaco && window.cmuxMonaco.apply(\(json));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

// MARK: - URL scheme handler

final class MonacoSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cmux-monaco"

    private lazy var bundleRoot: URL? = {
        // `MonacoBundle` is copied into the .app's Resources/ at build time.
        Bundle.main.resourceURL?.appendingPathComponent("MonacoBundle", isDirectory: true)
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let root = bundleRoot else {
            urlSchemeTask.didFailWithError(NSError(domain: "cmux.monaco", code: 1))
            return
        }

        // Normalize path: `cmux-monaco://editor/index.html` → Resources/MonacoBundle/index.html
        var relative = url.path
        if relative.isEmpty || relative == "/" {
            relative = "/index.html"
        }
        let fileURL = root.appendingPathComponent(relative, isDirectory: false).standardizedFileURL

        // Prevent escaping the bundle root.
        guard fileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            urlSchemeTask.didFailWithError(NSError(domain: "cmux.monaco", code: 2))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "cmux.monaco",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "not found: \(fileURL.path)"]
            ))
            return
        }

        let mime = MonacoSchemeHandler.mimeType(for: fileURL.pathExtension)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Cache-Control": "no-store",
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Language + theme helpers

enum MonacoLanguageResolver {
    static func languageId(for filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "mjs", "cjs": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "typescript"
        case "jsx": return "javascript"
        case "json": return "json"
        case "md", "markdown": return "markdown"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "shell"
        case "yml", "yaml": return "yaml"
        case "toml": return "ini"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss": return "scss"
        case "less": return "less"
        case "xml": return "xml"
        case "c", "h": return "c"
        case "cc", "cpp", "hpp", "hh", "cxx": return "cpp"
        case "m", "mm": return "objective-c"
        case "sql": return "sql"
        case "kt", "kts": return "kotlin"
        case "java": return "java"
        case "php": return "php"
        case "lua": return "lua"
        case "zig": return "zig"
        case "dart": return "dart"
        case "ex", "exs": return "elixir"
        case "elm": return "elm"
        case "dockerfile": return "dockerfile"
        default:
            // Filenames with no extension: check the basename for common cases.
            let basename = (filePath as NSString).lastPathComponent.lowercased()
            if basename == "dockerfile" { return "dockerfile" }
            if basename == "makefile" { return "makefile" }
            return "plaintext"
        }
    }
}

enum MonacoThemeResolver {
    static func editorBackgroundHex(isDark: Bool) -> String {
        isDark ? "#1e1e1e" : "#fafafa"
    }
    static func editorForegroundHex(isDark: Bool) -> String {
        isDark ? "#d4d4d4" : "#1e1e1e"
    }
}
