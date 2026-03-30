import Foundation
import UIKit

@MainActor
final class GhosttyRuntime {
    enum RuntimeError: LocalizedError {
        case backendInitFailed(code: Int32)
        case appCreationFailed

        var errorDescription: String? {
            switch self {
            case .backendInitFailed(let code):
                return String(
                    format: String(
                        localized: "terminal.runtime.init_failed",
                        defaultValue: "libghostty initialization failed (%d)"
                    ),
                    Int(code)
                )
            case .appCreationFailed:
                return String(
                    localized: "terminal.runtime.app_creation_failed",
                    defaultValue: "libghostty app creation failed"
                )
            }
        }
    }

    private static var backendInitialized = false
    private static var sharedResult: Result<GhosttyRuntime, Error>?
    private static var clipboardReader: @MainActor () -> String? = { UIPasteboard.general.string }
    private static var clipboardWriter: @MainActor (String?) -> Void = { UIPasteboard.general.string = $0 }

    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?

    static func shared() throws -> GhosttyRuntime {
        if let sharedResult {
            return try sharedResult.get()
        }

        let result: Result<GhosttyRuntime, Error>
        do {
            result = .success(try GhosttyRuntime())
        } catch {
            result = .failure(error)
        }
        sharedResult = result
        return try result.get()
    }

    init() throws {
        try Self.initializeBackendIfNeeded()

        let config = ghostty_config_new()
        Self.loadConfig(config)
        ghostty_config_finalize(config)

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in
                GhosttyRuntime.handleWakeup(userdata)
            },
            action_cb: { app, target, action in
                GhosttyRuntime.handleAction(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                GhosttyRuntime.handleReadClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { _, _, _, _ in
                // iOS embed doesn't currently support clipboard confirmation prompts.
            },
            write_clipboard_cb: { userdata, location, content, len, confirm in
                GhosttyRuntime.handleWriteClipboard(
                    userdata,
                    location: location,
                    content: content,
                    len: len,
                    confirm: confirm
                )
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyRuntime.handleCloseSurface(userdata, processAlive: processAlive)
            }
        )

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            ghostty_config_free(config)
            throw RuntimeError.appCreationFailed
        }

        self.config = config
        self.app = app
    }

    deinit {
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    func tick() {
        guard let app else { return }
        liveAnchormuxLog("runtime.tick")
        ghostty_app_tick(app)
    }

    private static func initializeBackendIfNeeded() throws {
        guard !backendInitialized else { return }
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            throw RuntimeError.backendInitFailed(code: result)
        }
        backendInitialized = true
    }

    private static func loadConfig(_ config: ghostty_config_t?) {
        guard let config else { return }
        #if os(iOS)
        ensureDefaultiOSConfig()
        for url in iOSConfigURLs() {
            url.path.withCString { path in
                ghostty_config_load_file(config, path)
            }
        }
        #else
        ghostty_config_load_default_files(config)
        #endif
    }

    private static func ensureDefaultiOSConfig() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let configDir = appSupport.appendingPathComponent("ghostty", isDirectory: true)
        let configFile = configDir.appendingPathComponent("config", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: configFile.path) else { return }

        let defaultConfig = """
        theme = dark:Monokai Classic
        font-size = 14
        cursor-style = bar
        cursor-style-blink = true
        """

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? defaultConfig.write(to: configFile, atomically: true, encoding: .utf8)
    }

    nonisolated static func iOSConfigURLs(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> [URL] {
        #if os(iOS)
        var urls: [URL] = []
        if let overridePath = processInfo.environment["CMUX_GHOSTTY_CONFIG_PATH"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            if isReadableConfigFile(at: overrideURL, fileManager: fileManager) {
                urls.append(overrideURL)
            }
        }

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fallbackURLs = [
                appSupport.appendingPathComponent("ghostty/config.ghostty", isDirectory: false),
                appSupport.appendingPathComponent("ghostty/config", isDirectory: false),
            ]
            for url in fallbackURLs where isReadableConfigFile(at: url, fileManager: fileManager) {
                urls.append(url)
            }
        }
        return urls
        #else
        return []
        #endif
    }

    private nonisolated static func isReadableConfigFile(at url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }

    nonisolated private static func handleWakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
        Task { @MainActor in
            runtime.tick()
            GhosttySurfaceView.drawVisibleSurfacesForWakeup()
        }
    }

    nonisolated private static func handleAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        if action.tag == GHOSTTY_ACTION_OPEN_URL {
            let payload = action.action.open_url
            guard let urlPtr = payload.url else { return false }
            let data = Data(bytes: urlPtr, count: Int(payload.len))
            guard let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString) else { return false }

            Task { @MainActor in
                UIApplication.shared.open(url)
            }
            return true
        }

        if action.tag == GHOSTTY_ACTION_SHOW_ON_SCREEN_KEYBOARD {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            Task { @MainActor in
                GhosttySurfaceView.focusInput(for: surface)
            }
            return true
        }

        if action.tag == GHOSTTY_ACTION_SET_TITLE {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let titlePtr = action.action.set_title.title else { return false }
            let title = String(cString: titlePtr)
            Task { @MainActor in
                GhosttySurfaceView.setTitle(title, for: surface)
            }
            return true
        }

        if action.tag == GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            Task { @MainActor in
                let title = GhosttySurfaceView.title(for: surface)
                clipboardWriter(title)
            }
            return true
        }

        if action.tag == GHOSTTY_ACTION_RING_BELL {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            Task { @MainActor in
                GhosttySurfaceView.ringBell(for: surface)
            }
            return true
        }

        return false
    }

    nonisolated private static func handleReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            guard let surfaceView = surfaceView(from: userdata),
                  let surface = surfaceView.surface else { return }
            let value = clipboardReader() ?? ""

            value.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
        }
    }

    nonisolated private static func handleWriteClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content, len > 0 else { return }

        for index in 0..<len {
            let item = content[index]
            guard let mimePtr = item.mime,
                  let dataPtr = item.data else { continue }
            let mime = String(cString: mimePtr)
            guard mime == "text/plain" else { continue }
            let value = String(cString: dataPtr)
            Task { @MainActor in
                clipboardWriter(value)
            }
            return
        }
    }

    nonisolated private static func handleCloseSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        GhosttySurfaceBridge.fromOpaque(userdata)?.handleCloseSurface(processAlive: processAlive)
    }

    nonisolated private static func surfaceView(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        GhosttySurfaceBridge.fromOpaque(userdata)?.surfaceView
    }

    @MainActor
    static func simulateSurfaceActionForTesting(
        surface: ghostty_surface_t,
        tag: ghostty_action_tag_e
    ) -> Bool {
        var target = ghostty_target_s()
        target.tag = GHOSTTY_TARGET_SURFACE
        target.target.surface = surface

        var action = ghostty_action_s()
        action.tag = tag
        return handleAction(nil, target: target, action: action)
    }

    @MainActor
    static func simulateSurfaceSetTitleActionForTesting(
        surface: ghostty_surface_t,
        title: String
    ) -> Bool {
        var target = ghostty_target_s()
        target.tag = GHOSTTY_TARGET_SURFACE
        target.target.surface = surface

        var handled = false
        title.withCString { titlePtr in
            var action = ghostty_action_s()
            action.tag = GHOSTTY_ACTION_SET_TITLE
            action.action.set_title = ghostty_action_set_title_s(title: titlePtr)
            handled = handleAction(nil, target: target, action: action)
        }
        return handled
    }

    @MainActor
    static func setClipboardHandlersForTesting(
        reader: @escaping () -> String?,
        writer: @escaping (String?) -> Void
    ) {
        clipboardReader = reader
        clipboardWriter = writer
    }

    @MainActor
    static func resetClipboardHandlersForTesting() {
        clipboardReader = { UIPasteboard.general.string }
        clipboardWriter = { UIPasteboard.general.string = $0 }
    }
}

extension Optional where Wrapped == String {
    func withCString<T>(_ body: (UnsafePointer<CChar>?) throws -> T) rethrows -> T {
        if let value = self {
            return try value.withCString(body)
        }
        return try body(nil)
    }
}

extension Notification.Name {
    static let ghosttySurfaceDidRequestClose = Notification.Name("ghosttySurfaceDidRequestClose")
    static let ghosttySurfaceDidRingBell = Notification.Name("ghosttySurfaceDidRingBell")
}
