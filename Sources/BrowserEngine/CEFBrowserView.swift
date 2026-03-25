import AppKit
import Combine

/// An NSView that hosts a CEF (Chromium) browser instance.
///
/// This is the Chromium equivalent of CmuxWebView (which wraps WKWebView).
/// It manages the CEF browser lifecycle, delegates navigation/display
/// callbacks to the parent, and provides the NSView that can be hosted
/// in the existing BrowserPanelView slot.
///
/// Thread safety: All CEF operations must happen on the main thread.
final class CEFBrowserView: NSView {

    // MARK: - Properties

    private var browserHandle: cef_bridge_browser_t?
    private var profileHandle: cef_bridge_profile_t?
    private var cefChildView: NSView?
    private var callbacksStorage: cef_bridge_client_callbacks?

    /// Deferred creation parameters (set by createBrowser, used when view is ready).
    private var pendingURL: String?
    private var pendingCachePath: String?
    private var browserCreationAttempted = false

    @Published private(set) var currentURL: String = ""
    @Published private(set) var currentTitle: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false

    weak var delegate: CEFBrowserViewDelegate?

    // MARK: - Initialization

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CEFBrowserView does not support NSCoding")
    }

    deinit {
        destroyBrowser()
    }

    // MARK: - Browser Lifecycle

    /// Queue browser creation. The actual CEF browser is created when the
    /// view has a non-zero frame and is in a window, ensuring CEF gets
    /// valid parent geometry for rendering.
    func createBrowser(initialURL: String, cachePath: String?) {
        guard CEFRuntime.shared.isInitialized else {
            delegate?.cefBrowserView(self, didFailWithError: "CEF not initialized")
            return
        }
        guard browserHandle == nil, !browserCreationAttempted else { return }

        pendingURL = initialURL
        pendingCachePath = cachePath

        // If we already have a frame and window, create immediately
        if bounds.width > 0, bounds.height > 0, window != nil {
            createBrowserNow()
        }
        // Otherwise, deferred to viewDidMoveToWindow or layout
    }

    /// Actually create the CEF browser. Called when the view is ready.
    private func createBrowserNow() {
        guard let url = pendingURL, !browserCreationAttempted else { return }
        browserCreationAttempted = true

        // Create profile if cache path provided
        if let cachePath = pendingCachePath {
            profileHandle = cef_bridge_profile_create(cachePath)
        }

        // Set up callbacks
        var callbacks = cef_bridge_client_callbacks()
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        callbacks.user_data = pointer
        callbacks.on_title_change = { handle, title, userData in
            guard let userData, let title else { return }
            let view = Unmanaged<CEFBrowserView>.fromOpaque(userData)
                .takeUnretainedValue()
            view.currentTitle = String(cString: title)
            view.delegate?.cefBrowserView(view, didChangeTitleTo: view.currentTitle)
        }
        callbacks.on_url_change = { handle, url, userData in
            guard let userData, let url else { return }
            let view = Unmanaged<CEFBrowserView>.fromOpaque(userData)
                .takeUnretainedValue()
            view.currentURL = String(cString: url)
            view.delegate?.cefBrowserView(view, didChangeURLTo: view.currentURL)
        }
        callbacks.on_loading_state_change = { handle, loading, back, forward, userData in
            guard let userData else { return }
            let view = Unmanaged<CEFBrowserView>.fromOpaque(userData)
                .takeUnretainedValue()
            view.isLoading = loading
            view.canGoBack = back
            view.canGoForward = forward
            view.delegate?.cefBrowserView(
                view,
                didChangeLoadingState: loading,
                canGoBack: back,
                canGoForward: forward
            )
        }
        callbacks.on_navigation = { handle, url, isMain, userData in
            guard let userData, let url, isMain else { return }
            let view = Unmanaged<CEFBrowserView>.fromOpaque(userData)
                .takeUnretainedValue()
            view.delegate?.cefBrowserView(
                view,
                didStartNavigation: String(cString: url)
            )
        }
        callbacks.on_fullscreen_change = { handle, fullscreen, userData in
            guard let userData else { return }
            let view = Unmanaged<CEFBrowserView>.fromOpaque(userData)
                .takeUnretainedValue()
            view.delegate?.cefBrowserView(view, didChangeFullscreen: fullscreen)
        }
        callbacks.on_popup_request = { handle, url, userData -> Bool in
            guard let userData, let url else { return false }
            let view = Unmanaged<CEFBrowserView>.fromOpaque(userData)
                .takeUnretainedValue()
            let urlStr = String(cString: url)
            return view.delegate?.cefBrowserView(view, shouldOpenPopup: urlStr) ?? false
        }
        callbacks.on_console_message = { _, _, _, _, _, _ in }

        callbacksStorage = callbacks

        let parentPtr = Unmanaged.passUnretained(self).toOpaque()
        let w = Int32(bounds.width)
        let h = Int32(bounds.height)

        browserHandle = withUnsafePointer(to: &callbacksStorage!) { ptr in
            cef_bridge_browser_create(profileHandle, url, parentPtr, w, h, ptr)
        }

        guard browserHandle != nil else {
            delegate?.cefBrowserView(self, didFailWithError: "Failed to create CEF browser")
            return
        }

        // CEF creates a child NSView inside us (since we passed parent_view).
        // Find and track it. Give CEF a moment to set up the view hierarchy.
        DispatchQueue.main.async { [weak self] in
            self?.findAndTrackCEFChildView()
        }

        pendingURL = nil
        pendingCachePath = nil
    }

    private func findAndTrackCEFChildView() {
        // CEF adds its own child view to our view
        if let child = subviews.first(where: { $0 !== cefChildView }) {
            child.frame = bounds
            child.autoresizingMask = [.width, .height]
            cefChildView = child
            return
        }

        // Fallback: get the view handle from CEF
        guard let handle = browserHandle,
              let nsviewPtr = cef_bridge_browser_get_nsview(handle) else { return }
        let childView = Unmanaged<NSView>.fromOpaque(nsviewPtr).takeUnretainedValue()
        if childView !== self {
            if childView.superview !== self {
                childView.frame = bounds
                childView.autoresizingMask = [.width, .height]
                addSubview(childView)
            }
            cefChildView = childView
        }
    }

    func destroyBrowser() {
        if let handle = browserHandle {
            cef_bridge_browser_destroy(handle)
            browserHandle = nil
        }
        if let profile = profileHandle {
            cef_bridge_profile_destroy(profile)
            profileHandle = nil
        }
        cefChildView?.removeFromSuperview()
        cefChildView = nil
        callbacksStorage = nil
    }

    // MARK: - Navigation

    func loadURL(_ urlString: String) {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_load_url(handle, urlString)
    }

    func goBack() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_go_back(handle)
    }

    func goForward() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_go_forward(handle)
    }

    func reload() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_reload(handle)
    }

    func stopLoading() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_stop(handle)
    }

    // MARK: - Page Control

    func setZoomLevel(_ level: Double) {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_set_zoom(handle, level)
    }

    var zoomLevel: Double {
        guard let handle = browserHandle else { return 0.0 }
        return cef_bridge_browser_get_zoom(handle)
    }

    // MARK: - JavaScript

    func executeJavaScript(_ script: String) {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_execute_js(handle, script)
    }

    func addInitScript(_ script: String) {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_add_init_script(handle, script)
    }

    // MARK: - DevTools

    func showDevTools() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_show_devtools(handle)
    }

    func closeDevTools() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_close_devtools(handle)
    }

    // MARK: - Visibility (Portal Support)

    func notifyHidden(_ hidden: Bool) {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_set_hidden(handle, hidden)
    }

    func notifyResized() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_notify_resized(handle)
    }

    // MARK: - Find in Page

    func find(_ text: String, forward: Bool = true, caseSensitive: Bool = false) {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_find(handle, text, forward, caseSensitive)
    }

    func stopFinding() {
        guard let handle = browserHandle else { return }
        cef_bridge_browser_stop_finding(handle)
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Create deferred browser when we enter a window with valid geometry
        if window != nil, bounds.width > 0, bounds.height > 0, pendingURL != nil {
            createBrowserNow()
        }
    }

    override func layout() {
        super.layout()

        // Create deferred browser on first layout with valid geometry
        if pendingURL != nil, !browserCreationAttempted,
           bounds.width > 0, bounds.height > 0, window != nil {
            createBrowserNow()
        }

        // Resize the CEF child view to fill bounds
        if let child = cefChildView {
            if child.frame != bounds {
                child.frame = bounds
            }
        } else if browserHandle != nil {
            // CEF child might have been added asynchronously
            findAndTrackCEFChildView()
        }
        notifyResized()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cefChildView?.frame = bounds
        notifyResized()
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let child = cefChildView {
            window?.makeFirstResponder(child)
            return true
        }
        return super.becomeFirstResponder()
    }
}

// MARK: - Delegate Protocol

protocol CEFBrowserViewDelegate: AnyObject {
    func cefBrowserView(_ view: CEFBrowserView, didChangeTitleTo title: String)
    func cefBrowserView(_ view: CEFBrowserView, didChangeURLTo url: String)
    func cefBrowserView(_ view: CEFBrowserView, didChangeLoadingState isLoading: Bool, canGoBack: Bool, canGoForward: Bool)
    func cefBrowserView(_ view: CEFBrowserView, didStartNavigation url: String)
    func cefBrowserView(_ view: CEFBrowserView, didChangeFullscreen fullscreen: Bool)
    func cefBrowserView(_ view: CEFBrowserView, shouldOpenPopup url: String) -> Bool
    func cefBrowserView(_ view: CEFBrowserView, didFailWithError message: String)
}

extension CEFBrowserViewDelegate {
    func cefBrowserView(_ view: CEFBrowserView, didChangeTitleTo title: String) {}
    func cefBrowserView(_ view: CEFBrowserView, didChangeURLTo url: String) {}
    func cefBrowserView(_ view: CEFBrowserView, didChangeLoadingState isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {}
    func cefBrowserView(_ view: CEFBrowserView, didStartNavigation url: String) {}
    func cefBrowserView(_ view: CEFBrowserView, didChangeFullscreen fullscreen: Bool) {}
    func cefBrowserView(_ view: CEFBrowserView, shouldOpenPopup url: String) -> Bool { false }
    func cefBrowserView(_ view: CEFBrowserView, didFailWithError message: String) {}
}
