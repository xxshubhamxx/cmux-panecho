import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import QuartzCore

private struct Options {
    var chromiumHost: String
    var bridgePath: String
    var outputDirectory: URL
    var timeout: TimeInterval
    var includeCanvas: Bool
    var includeExample: Bool
    var includeInput: Bool
    var inputDiagnosticCapture: Bool
}

private struct RenderTarget {
    let name: String
    let url: String
    let screenshotName: String
    let expected: Set<ExpectedPixel>
    let preInputScreenshotName: String?
    let preInputExpected: Set<ExpectedPixel>?
    let inputClick: MouseClick?
}

private struct MouseClick {
    let x: Float
    let y: Float
}

private struct PixelStats: Codable {
    let width: Int
    let height: Int
    let redPixels: Int
    let greenPixels: Int
    let bluePixels: Int
    let yellowPixels: Int
    let darkPixels: Int
    let lightPixels: Int
    let nonWhitePixels: Int
}

private struct CaptureResult: Codable {
    let name: String
    let url: String
    let hostPID: Int32
    let hostCommand: String
    let contextID: UInt32
    let swiftWindowID: UInt32
    let screenshotPath: String
    let preInputScreenshotPath: String?
    let stats: PixelStats
    let profileHadDevToolsActivePort: Bool
    let sessionEvents: SessionEventSnapshot
}

private struct MojoSurfaceCapture {
    let path: String
    let mode: String
    let width: UInt32
    let height: UInt32
}

private struct Summary: Codable {
    let chromiumHost: String
    let bridgePath: String
    let outputDirectory: String
    let displayPath: String
    let contextSource: String
    let controlTransport: String
    let devToolsActivePortFound: Bool
    let remoteDebuggingArgumentFound: Bool
    let captures: [CaptureResult]
}

private struct CaptureFailureSnapshot: Codable {
    let name: String
    let contextID: UInt32?
    let lastWindowID: UInt32?
    let lastError: String
    let lastStats: PixelStats?
    let sessionEvents: SessionEventSnapshot
}

private enum VerifierError: Error, CustomStringConvertible {
    case usage(String)
    case bridge(String)
    case launch(String)
    case timeout(String)
    case capture(String)
    case pixelCheck(String)
    case forbiddenPath(String)
    case pngWrite(String)
    case layerHost(String)

    var description: String {
        switch self {
        case .usage(let message),
             .bridge(let message),
             .launch(let message),
             .timeout(let message),
             .capture(let message),
             .pixelCheck(let message),
             .forbiddenPath(let message),
             .pngWrite(let message),
             .layerHost(let message):
            return message
        }
    }
}

private struct SessionEventSnapshot: Codable {
    let ready: Bool
    let disconnected: Bool
    let contextID: UInt32
    let contextGeneration: UInt64
    let hostPID: Int32
    let loading: Bool
    let url: String
    let title: String
    let logs: [String]
}

private struct OwlFreshEvent {
    let kind: Int32
    let contextID: UInt32
    let hostPID: Int32
    let loading: Bool
    let url: UnsafePointer<CChar>?
    let title: UnsafePointer<CChar>?
    let message: UnsafePointer<CChar>?
}

private typealias OwlFreshEventCallback = @convention(c) (
    UnsafeRawPointer?,
    UnsafeMutableRawPointer?
) -> Void

private final class SessionEvents {
    private let lock = NSLock()
    private var ready = false
    private var disconnected = false
    private var contextID: UInt32 = 0
    private var contextGeneration: UInt64 = 0
    private var hostPID: Int32 = -1
    private var loading = true
    private var url = ""
    private var title = ""
    private var logs: [String] = []

    func record(_ event: OwlFreshEvent) {
        lock.lock()
        defer { lock.unlock() }

        switch event.kind {
        case 1:
            if let message = event.message {
                logs.append(String(cString: message))
                if logs.count > 30 {
                    logs.removeFirst(logs.count - 30)
                }
            }
        case 2:
            ready = true
            hostPID = event.hostPID
            updateContextID(event.contextID)
        case 3:
            updateContextID(event.contextID)
        case 4:
            loading = event.loading
            if let eventURL = event.url {
                url = String(cString: eventURL)
            }
            if let eventTitle = event.title {
                title = String(cString: eventTitle)
            }
        case 5:
            disconnected = true
        default:
            break
        }
    }

    private func updateContextID(_ id: UInt32) {
        guard id != 0 else {
            return
        }
        contextID = id
        contextGeneration += 1
    }

    func snapshot() -> SessionEventSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return SessionEventSnapshot(
            ready: ready,
            disconnected: disconnected,
            contextID: contextID,
            contextGeneration: contextGeneration,
            hostPID: hostPID,
            loading: loading,
            url: url,
            title: title,
            logs: logs
        )
    }
}

private let owlFreshEventCallback: OwlFreshEventCallback = { eventPointer, userData in
    guard let eventPointer, let userData else {
        return
    }
    let events = Unmanaged<SessionEvents>.fromOpaque(userData).takeUnretainedValue()
    events.record(eventPointer.assumingMemoryBound(to: OwlFreshEvent.self).pointee)
}

@main
struct OwlLayerHostVerifier {
    static func main() {
        do {
            let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            try LayerHostRunner(options: options).run()
        } catch let error as VerifierError {
            fputs("error: \(error.description)\n", stderr)
            exit(1)
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions(arguments: [String]) throws -> Options {
        var chromiumHost = ProcessInfo.processInfo.environment["OWL_CHROMIUM_HOST"] ?? ""
        var bridgePath = ProcessInfo.processInfo.environment["OWL_BRIDGE_PATH"] ?? ""
        var outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("artifacts/layer-host-latest", isDirectory: true)
        var timeout: TimeInterval = 30
        var includeCanvas = true
        var includeExample = true
        var includeInput = false
        var inputDiagnosticCapture = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--chromium-host":
                index += 1
                guard index < arguments.count else {
                    throw VerifierError.usage("missing value for --chromium-host")
                }
                chromiumHost = arguments[index]
            case "--bridge":
                index += 1
                guard index < arguments.count else {
                    throw VerifierError.usage("missing value for --bridge")
                }
                bridgePath = arguments[index]
            case "--output-dir":
                index += 1
                guard index < arguments.count else {
                    throw VerifierError.usage("missing value for --output-dir")
                }
                outputDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--timeout":
                index += 1
                guard index < arguments.count, let parsed = TimeInterval(arguments[index]) else {
                    throw VerifierError.usage("invalid value for --timeout")
                }
                timeout = parsed
            case "--skip-example":
                includeExample = false
            case "--skip-canvas":
                includeCanvas = false
            case "--input-check":
                includeInput = true
            case "--input-diagnostic-capture":
                inputDiagnosticCapture = true
            case "--help":
                print("""
                Usage: OwlLayerHostVerifier --chromium-host <path> --bridge <path> [--output-dir <dir>] [--timeout <seconds>] [--skip-canvas] [--skip-example] [--input-check] [--input-diagnostic-capture]
                """)
                exit(0)
            default:
                throw VerifierError.usage("unknown argument: \(argument)")
            }
            index += 1
        }

        guard !chromiumHost.isEmpty else {
            throw VerifierError.usage("missing --chromium-host or OWL_CHROMIUM_HOST")
        }
        guard !bridgePath.isEmpty else {
            throw VerifierError.usage("missing --bridge or OWL_BRIDGE_PATH")
        }

        return Options(
            chromiumHost: chromiumHost,
            bridgePath: bridgePath,
            outputDirectory: outputDirectory,
            timeout: timeout,
            includeCanvas: includeCanvas,
            includeExample: includeExample,
            includeInput: includeInput,
            inputDiagnosticCapture: inputDiagnosticCapture
        )
    }
}

private final class LayerHostRunner {
    private let options: Options
    private let fileManager = FileManager.default
    private let contentSize = CGSize(width: 960, height: 640)

    init(options: Options) {
        self.options = options
    }

    func run() throws {
        guard fileManager.isExecutableFile(atPath: options.chromiumHost) else {
            throw VerifierError.usage("Chromium host is not executable: \(options.chromiumHost)")
        }
        guard fileManager.fileExists(atPath: options.bridgePath) else {
            throw VerifierError.usage("OWL bridge dylib does not exist: \(options.bridgePath)")
        }

        try fileManager.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        let fixtureDirectory = options.outputDirectory.appendingPathComponent("fixtures", isDirectory: true)
        try fileManager.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        let canvasFixture = try writeFixture(
            name: "canvas-fixture",
            html: Fixtures.canvasFixture,
            directory: fixtureDirectory
        )
        let inputFixture = try writeFixture(
            name: "input-fixture",
            html: Fixtures.inputFixture,
            directory: fixtureDirectory
        )
        var targets: [RenderTarget] = []
        if options.includeCanvas {
            targets.append(RenderTarget(
                name: "canvas-fixture",
                url: canvasFixture.absoluteString,
                screenshotName: "canvas-fixture-layer-host.png",
                expected: [.red, .green, .blue, .dark],
                preInputScreenshotName: nil,
                preInputExpected: nil,
                inputClick: nil
            ))
        }
        if options.includeExample {
            targets.append(
                RenderTarget(
                    name: "example-com",
                    url: "https://example.com/",
                    screenshotName: "example-com-layer-host.png",
                    expected: [.dark, .light, .nonWhite],
                    preInputScreenshotName: nil,
                    preInputExpected: nil,
                    inputClick: nil
                )
            )
        }
        if options.includeInput {
            targets.append(
                RenderTarget(
                    name: "input-fixture",
                    url: inputFixture.absoluteString,
                    screenshotName: "input-fixture-after-click.png",
                    expected: [.yellow, .dark],
                    preInputScreenshotName: "input-fixture-before-click.png",
                    preInputExpected: [.red, .dark],
                    inputClick: MouseClick(x: 170, y: 180)
                )
            )
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        let bridge = try OwlFreshBridge(path: options.bridgePath)
        try bridge.initialize()

        var captures: [CaptureResult] = []
        for target in targets {
            captures.append(try runCapture(target: target, bridge: bridge, app: app))
        }

        let summary = Summary(
            chromiumHost: options.chromiumHost,
            bridgePath: options.bridgePath,
            outputDirectory: options.outputDirectory.path,
            displayPath: "Mojo-published CAContext id hosted by Swift CALayerHost",
            contextSource: ProcessInfo.processInfo.environment["OWL_FRESH_LAYER_FIXTURE"] == nil
                ? "chromium-compositor-ca-context"
                : "chromium-layer-fixture-ca-context",
            controlTransport: "mojo",
            devToolsActivePortFound: captures.contains(where: \.profileHadDevToolsActivePort),
            remoteDebuggingArgumentFound: captures.contains { containsRemoteDebuggingArgument($0.hostCommand) },
            captures: captures
        )

        guard !summary.devToolsActivePortFound else {
            throw VerifierError.forbiddenPath("DevToolsActivePort was created during layer host verification")
        }
        guard !summary.remoteDebuggingArgumentFound else {
            throw VerifierError.forbiddenPath("host process used a remote debugging argument")
        }

        let summaryURL = options.outputDirectory.appendingPathComponent("summary.json")
        try JSONEncoder.pretty.encode(summary).write(to: summaryURL)

        print("OWL LayerHost verification passed")
        print("Artifacts: \(options.outputDirectory.path)")
        print("Control transport: \(summary.controlTransport)")
        print("Display path: \(summary.displayPath)")
        print("Context source: \(summary.contextSource)")
        print("DevToolsActivePort found: \(summary.devToolsActivePortFound)")
        print("Remote debugging args found: \(summary.remoteDebuggingArgumentFound)")
        for capture in captures {
            print("- \(capture.name): \(capture.screenshotPath) contextID=\(capture.contextID) windowID=\(capture.swiftWindowID) size=\(capture.stats.width)x\(capture.stats.height)")
        }
    }

    private func writeFixture(name: String, html: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("\(name).html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runCapture(
        target: RenderTarget,
        bridge: OwlFreshBridge,
        app: NSApplication
    ) throws -> CaptureResult {
        let profileDirectory = options.outputDirectory
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent("\(target.name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let useLayerFixture = ProcessInfo.processInfo.environment["OWL_FRESH_LAYER_FIXTURE"] != nil
        let initialURL = useLayerFixture ? target.url : "about:blank"
        let sessionEvents = SessionEvents()
        let session = try bridge.createSession(
            chromiumHost: options.chromiumHost,
            initialURL: initialURL,
            userDataDirectory: profileDirectory.path,
            events: sessionEvents
        )
        defer {
            bridge.destroy(session)
        }

        bridge.resize(session, width: UInt32(contentSize.width), height: UInt32(contentSize.height), scale: 1.0)
        bridge.setFocus(session, focused: true)

        let hostPID = bridge.hostPID(session)
        guard hostPID > 0 else {
            throw VerifierError.launch("bridge did not report a valid host PID for \(target.name)")
        }

        try waitForReady(name: target.name, events: sessionEvents, bridge: bridge, app: app)
        let baseline = sessionEvents.snapshot()
        var contextID: UInt32
        if useLayerFixture, baseline.contextID != 0 {
            contextID = baseline.contextID
        } else {
            bridge.navigate(session, url: target.url)
            contextID = try waitForContextID(
                name: target.name,
                events: sessionEvents,
                bridge: bridge,
                app: app,
                afterGeneration: baseline.contextGeneration,
                rejectingContextID: nil
            )
        }
        let window = try LayerHostWindow(
            title: "OWL LayerHost \(target.name)",
            contextID: contextID,
            size: contentSize
        )
        defer {
            window.close()
            pumpApp(app, for: 0.1)
        }

        app.activate(ignoringOtherApps: true)
        window.show()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        pumpApp(app, for: 0.2)

        let screenshotURL = options.outputDirectory.appendingPathComponent(target.screenshotName)
        let preInputScreenshotURL = target.preInputScreenshotName.map {
            options.outputDirectory.appendingPathComponent($0)
        }
        let deadline = Date().addingTimeInterval(options.timeout)
        var lastError = "no capture attempted"
        var lastWindowID: UInt32?
        var lastStats: PixelStats?
        var inputSent = target.inputClick == nil
        var currentExpected = target.preInputExpected ?? target.expected
        var capturedPreInputPath: String?

        while Date() < deadline {
            bridge.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.05)
            window.flushHostedLayer()

            let snapshot = sessionEvents.snapshot()
            if snapshot.contextID != 0, snapshot.contextID != contextID {
                contextID = snapshot.contextID
                window.update(contextID: contextID)
                pumpApp(app, for: 0.05)
            }

            guard let windowID = swiftHostWindowID(title: window.title, minimumSize: contentSize) else {
                lastError = "Swift LayerHost window was not visible in CGWindowList"
                continue
            }
            lastWindowID = windowID

            do {
                let captureURL = inputSent ? screenshotURL : (preInputScreenshotURL ?? screenshotURL)
                let capture = try captureWindow(windowID: windowID, to: captureURL)
                let stats = analyze(image: capture.image)
                lastStats = stats
                if currentExpected.isSatisfied(by: stats) {
                    if !inputSent, let click = target.inputClick {
                        capturedPreInputPath = captureURL.path
                        bridge.setFocus(session, focused: true)
                        if ProcessInfo.processInfo.environment["OWL_LAYER_HOST_KEY_ONLY"] != "1" {
                            bridge.sendMouse(session, kind: 2, x: click.x, y: click.y, button: 0, clickCount: 0)
                            bridge.pollEvents(milliseconds: 10)
                            bridge.sendMouse(session, kind: 0, x: click.x, y: click.y, button: 0, clickCount: 1)
                            bridge.pollEvents(milliseconds: 10)
                            bridge.sendMouse(session, kind: 1, x: click.x, y: click.y, button: 0, clickCount: 1)
                            bridge.pollEvents(milliseconds: 10)
                        }
                        bridge.sendKey(session, keyDown: true, keyCode: 88, text: "x")
                        bridge.pollEvents(milliseconds: 10)
                        bridge.sendKey(session, keyDown: false, keyCode: 88, text: "")
                        bridge.pollEvents(milliseconds: 10)
                        pumpApp(app, for: 0.05)
                        if options.inputDiagnosticCapture {
                            let stateURL = options.outputDirectory.appendingPathComponent(
                                "\(target.name)-mojo-dom-state.json"
                            )
                            do {
                                let domState = try bridge.executeJavaScript(
                                    session,
                                    script: "({className: document.body.className, status: document.getElementById('status')?.textContent || ''})"
                                )
                                try domState.write(to: stateURL, atomically: true, encoding: .utf8)
                            } catch {
                                try? String(describing: error).write(
                                    to: stateURL,
                                    atomically: true,
                                    encoding: .utf8
                                )
                            }
                            let diagnosticURL = options.outputDirectory.appendingPathComponent(
                                "\(target.name)-mojo-after-click.png"
                            )
                            do {
                                let diagnostic = try bridge.captureSurfacePNG(session, to: diagnosticURL)
                                let infoURL = options.outputDirectory.appendingPathComponent(
                                    "\(target.name)-mojo-after-click.json"
                                )
                                let payload = [
                                    "path": diagnostic.path,
                                    "mode": diagnostic.mode,
                                    "width": String(diagnostic.width),
                                    "height": String(diagnostic.height),
                                ]
                                try JSONEncoder.pretty.encode(payload).write(to: infoURL)
                            } catch {
                                let errorURL = options.outputDirectory.appendingPathComponent(
                                    "\(target.name)-mojo-after-click-error.txt"
                                )
                                try? String(describing: error).write(to: errorURL, atomically: true, encoding: .utf8)
                            }
                        }
                        inputSent = true
                        currentExpected = target.expected
                        lastError = "input sent through Mojo; waiting for post-input pixels"
                        continue
                    }
                    let hostCommand = processCommandLine(pid: hostPID)
                    try rejectForbiddenRuntimePaths(
                        processCommand: hostCommand,
                        profileDirectory: profileDirectory,
                        name: target.name
                    )
                    return CaptureResult(
                        name: target.name,
                        url: target.url,
                        hostPID: hostPID,
                        hostCommand: hostCommand,
                        contextID: contextID,
                        swiftWindowID: windowID,
                        screenshotPath: screenshotURL.path,
                        preInputScreenshotPath: capturedPreInputPath,
                        stats: stats,
                        profileHadDevToolsActivePort: hasDevToolsActivePort(profileDirectory: profileDirectory),
                        sessionEvents: sessionEvents.snapshot()
                    )
                }
                lastError = "pixel stats did not match expected set \(currentExpected): \(stats)"
            } catch let error as VerifierError {
                lastError = error.description
            } catch {
                lastError = String(describing: error)
            }
        }

        let failure = CaptureFailureSnapshot(
            name: target.name,
            contextID: contextID,
            lastWindowID: lastWindowID,
            lastError: lastError,
            lastStats: lastStats,
            sessionEvents: sessionEvents.snapshot()
        )
        try? JSONEncoder.pretty.encode(failure).write(
            to: options.outputDirectory.appendingPathComponent("\(target.name)-failure.json")
        )
        throw VerifierError.timeout("timed out waiting for \(target.name) through Swift LayerHost: \(lastError); lastWindowID=\(lastWindowID.map(String.init) ?? "none"); events=\(sessionEvents.snapshot())")
    }

    private func waitForContextID(
        name: String,
        events: SessionEvents,
        bridge: OwlFreshBridge,
        app: NSApplication,
        afterGeneration: UInt64,
        rejectingContextID: UInt32?
    ) throws -> UInt32 {
        let deadline = Date().addingTimeInterval(min(15, options.timeout))
        while Date() < deadline {
            bridge.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.01)
            let snapshot = events.snapshot()
            if snapshot.ready,
               snapshot.contextID != 0,
               snapshot.contextGeneration > afterGeneration,
               snapshot.contextID != rejectingContextID {
                return snapshot.contextID
            }
            if snapshot.disconnected {
                throw VerifierError.launch("\(name) disconnected before Mojo published a CAContext id")
            }
        }
        throw VerifierError.timeout("timed out waiting for \(name) Mojo context id: \(events.snapshot())")
    }

    private func waitForReady(
        name: String,
        events: SessionEvents,
        bridge: OwlFreshBridge,
        app: NSApplication
    ) throws {
        let deadline = Date().addingTimeInterval(min(10, options.timeout))
        while Date() < deadline {
            bridge.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.01)
            let snapshot = events.snapshot()
            if snapshot.ready {
                return
            }
            if snapshot.disconnected {
                throw VerifierError.launch("\(name) disconnected before Mojo ready")
            }
        }
        throw VerifierError.timeout("timed out waiting for \(name) Mojo ready event: \(events.snapshot())")
    }

    private func rejectForbiddenRuntimePaths(
        processCommand: String,
        profileDirectory: URL,
        name: String
    ) throws {
        if containsRemoteDebuggingArgument(processCommand) {
            throw VerifierError.forbiddenPath("\(name) host command contains remote debugging: \(processCommand)")
        }
        if hasDevToolsActivePort(profileDirectory: profileDirectory) {
            throw VerifierError.forbiddenPath("\(name) profile created DevToolsActivePort")
        }
    }
}

private final class LayerHostWindow {
    let title: String
    private let window: NSWindow
    private let hostLayer: CALayer

    init(title: String, contextID: UInt32, size: CGSize) throws {
        self.title = title

        let frame = NSRect(origin: .zero, size: size)
        let contentView = NSView(frame: frame)
        contentView.wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.isGeometryFlipped = true
        rootLayer.backgroundColor = NSColor.white.cgColor
        rootLayer.frame = CGRect(origin: .zero, size: size)
        contentView.layer = rootLayer

        let hostLayer = try makeCALayerHost(contextID: contextID)
        hostLayer.anchorPoint = CGPoint.zero
        hostLayer.bounds = rootLayer.bounds
        hostLayer.position = CGPoint.zero
        hostLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        rootLayer.addSublayer(hostLayer)
        self.hostLayer = hostLayer

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = contentView
        window.backgroundColor = .white
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.sharingType = .readOnly
    }

    func close() {
        window.close()
    }

    func update(contextID: UInt32) {
        hostLayer.setValue(NSNumber(value: contextID), forKey: "contextId")
        flushHostedLayer()
    }

    func flushHostedLayer() {
        hostLayer.setNeedsDisplay()
        hostLayer.displayIfNeeded()
        CATransaction.flush()
    }

}

private struct CapturedWindow {
    let image: CGImage
}

private func makeCALayerHost(contextID: UInt32) throws -> CALayer {
    guard let layerClass = NSClassFromString("CALayerHost") as? NSObject.Type else {
        throw VerifierError.layerHost("CALayerHost is not available")
    }
    guard let layer = layerClass.init() as? CALayer else {
        throw VerifierError.layerHost("CALayerHost did not instantiate as CALayer")
    }
    layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
    layer.setValue(NSNumber(value: contextID), forKey: "contextId")
    layer.setValue(true, forKey: "inheritsSecurity")
    return layer
}

private final class OwlFreshBridge {
    private typealias GlobalInit = @convention(c) () -> Int32
    private typealias SessionCreate = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        OwlFreshEventCallback?,
        UnsafeMutableRawPointer?
    ) -> OpaquePointer?
    private typealias SessionDestroy = @convention(c) (OpaquePointer?) -> Void
    private typealias HostPID = @convention(c) (OpaquePointer?) -> Int32
    private typealias Navigate = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Void
    private typealias Resize = @convention(c) (OpaquePointer?, UInt32, UInt32, Float) -> Void
    private typealias SetFocus = @convention(c) (OpaquePointer?, Bool) -> Void
    private typealias SendMouse = @convention(c) (
        OpaquePointer?,
        UInt32,
        Float,
        Float,
        UInt32,
        UInt32,
        Float,
        Float,
        UInt32
    ) -> Void
    private typealias SendKey = @convention(c) (
        OpaquePointer?,
        Bool,
        UInt32,
        UnsafePointer<CChar>?,
        UInt32
    ) -> Void
    private typealias CaptureSurfacePNG = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<UInt>?,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias ExecuteJavaScript = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias PollEvents = @convention(c) (UInt32) -> Void
    private typealias FreeBuffer = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let globalInit: GlobalInit
    private let sessionCreate: SessionCreate
    private let sessionDestroy: SessionDestroy
    private let sessionHostPID: HostPID
    private let sessionNavigate: Navigate
    private let sessionResize: Resize
    private let sessionSetFocus: SetFocus
    private let sessionSendMouse: SendMouse
    private let sessionSendKey: SendKey
    private let sessionCaptureSurfacePNG: CaptureSurfacePNG
    private let sessionExecuteJavaScript: ExecuteJavaScript
    private let eventPoll: PollEvents
    private let freeBuffer: FreeBuffer

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw VerifierError.bridge("dlopen failed for \(path): \(dlerrorString())")
        }
        self.handle = handle
        self.globalInit = try loadSymbol(handle, "owl_fresh_global_init", as: GlobalInit.self)
        self.sessionCreate = try loadSymbol(handle, "owl_fresh_session_create", as: SessionCreate.self)
        self.sessionDestroy = try loadSymbol(handle, "owl_fresh_session_destroy", as: SessionDestroy.self)
        self.sessionHostPID = try loadSymbol(handle, "owl_fresh_session_host_pid", as: HostPID.self)
        self.sessionNavigate = try loadSymbol(handle, "owl_fresh_navigate", as: Navigate.self)
        self.sessionResize = try loadSymbol(handle, "owl_fresh_resize", as: Resize.self)
        self.sessionSetFocus = try loadSymbol(handle, "owl_fresh_set_focus", as: SetFocus.self)
        self.sessionSendMouse = try loadSymbol(handle, "owl_fresh_send_mouse", as: SendMouse.self)
        self.sessionSendKey = try loadSymbol(handle, "owl_fresh_send_key", as: SendKey.self)
        self.sessionCaptureSurfacePNG = try loadSymbol(
            handle,
            "owl_fresh_capture_surface_png",
            as: CaptureSurfacePNG.self
        )
        self.sessionExecuteJavaScript = try loadSymbol(
            handle,
            "owl_fresh_execute_javascript",
            as: ExecuteJavaScript.self
        )
        self.eventPoll = try loadSymbol(handle, "owl_fresh_poll_events", as: PollEvents.self)
        self.freeBuffer = try loadSymbol(handle, "owl_fresh_free_buffer", as: FreeBuffer.self)
    }

    deinit {
        dlclose(handle)
    }

    func initialize() throws {
        let status = globalInit()
        guard status == 0 else {
            throw VerifierError.bridge("owl_fresh_global_init failed with status \(status)")
        }
    }

    func createSession(
        chromiumHost: String,
        initialURL: String,
        userDataDirectory: String,
        events: SessionEvents
    ) throws -> OpaquePointer {
        let userData = Unmanaged.passUnretained(events).toOpaque()
        let session = chromiumHost.withCString { hostPointer in
            initialURL.withCString { urlPointer in
                userDataDirectory.withCString { profilePointer in
                    sessionCreate(hostPointer, urlPointer, profilePointer, owlFreshEventCallback, userData)
                }
            }
        }
        guard let session else {
            throw VerifierError.launch("owl_fresh_session_create returned null")
        }
        return session
    }

    func destroy(_ session: OpaquePointer?) {
        sessionDestroy(session)
    }

    func hostPID(_ session: OpaquePointer?) -> Int32 {
        sessionHostPID(session)
    }

    func navigate(_ session: OpaquePointer?, url: String) {
        url.withCString { urlPointer in
            sessionNavigate(session, urlPointer)
        }
    }

    func resize(_ session: OpaquePointer?, width: UInt32, height: UInt32, scale: Float) {
        sessionResize(session, width, height, scale)
    }

    func setFocus(_ session: OpaquePointer?, focused: Bool) {
        sessionSetFocus(session, focused)
    }

    func sendMouse(
        _ session: OpaquePointer?,
        kind: UInt32,
        x: Float,
        y: Float,
        button: UInt32,
        clickCount: UInt32
    ) {
        sessionSendMouse(session, kind, x, y, button, clickCount, 0, 0, 0)
    }

    func sendKey(_ session: OpaquePointer?, keyDown: Bool, keyCode: UInt32, text: String) {
        text.withCString { textPointer in
            sessionSendKey(session, keyDown, keyCode, textPointer, 0)
        }
    }

    func pollEvents(milliseconds: UInt32) {
        eventPoll(milliseconds)
    }

    func captureSurfacePNG(_ session: OpaquePointer?, to url: URL) throws -> MojoSurfaceCapture {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length: UInt = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        var modePointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sessionCaptureSurfacePNG(
            session,
            &bytes,
            &length,
            &width,
            &height,
            &modePointer,
            &errorPointer
        )
        defer {
            if let bytes {
                freeBuffer(UnsafeMutableRawPointer(bytes))
            }
            if let modePointer {
                freeBuffer(UnsafeMutableRawPointer(modePointer))
            }
            if let errorPointer {
                freeBuffer(UnsafeMutableRawPointer(errorPointer))
            }
        }

        let mode = modePointer.map { String(cString: $0) } ?? ""
        if status != 0 {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown CaptureSurface error"
            throw VerifierError.capture("CaptureSurface failed: \(message)")
        }
        guard let bytes, length > 0 else {
            throw VerifierError.capture("CaptureSurface returned no PNG bytes")
        }
        let data = Data(bytes: bytes, count: Int(length))
        try data.write(to: url)
        return MojoSurfaceCapture(path: url.path, mode: mode, width: width, height: height)
    }

    func executeJavaScript(_ session: OpaquePointer?, script: String) throws -> String {
        var resultPointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = script.withCString { scriptPointer in
            sessionExecuteJavaScript(session, scriptPointer, &resultPointer, &errorPointer)
        }
        defer {
            if let resultPointer {
                freeBuffer(UnsafeMutableRawPointer(resultPointer))
            }
            if let errorPointer {
                freeBuffer(UnsafeMutableRawPointer(errorPointer))
            }
        }
        if status != 0 {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown ExecuteJavaScript error"
            throw VerifierError.bridge("ExecuteJavaScript failed: \(message)")
        }
        return resultPointer.map { String(cString: $0) } ?? "null"
    }
}

private func pumpApp(_ app: NSApplication, for duration: TimeInterval) {
    let end = Date().addingTimeInterval(duration)
    repeat {
        if let event = app.nextEvent(
            matching: .any,
            until: Date().addingTimeInterval(0.01),
            inMode: .default,
            dequeue: true
        ) {
            app.sendEvent(event)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    } while Date() < end
}

private func swiftHostWindowID(title: String, minimumSize: CGSize) -> UInt32? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }

    var fallback: (id: UInt32, area: Double)?
    for window in windows {
        guard (window[kCGWindowOwnerPID as String] as? Int32) == getpid(),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber,
              width.doubleValue >= minimumSize.width,
              height.doubleValue >= minimumSize.height else {
            continue
        }
        let id = windowNumber(from: window)
        guard let id else {
            continue
        }
        if (window[kCGWindowName as String] as? String) == title {
            return id
        }
        let area = width.doubleValue * height.doubleValue
        if fallback == nil || area > fallback!.area {
            fallback = (id, area)
        }
    }

    return fallback?.id
}

private func windowNumber(from window: [String: Any]) -> UInt32? {
    if let number = window[kCGWindowNumber as String] as? UInt32 {
        return number
    }
    if let number = window[kCGWindowNumber as String] as? Int {
        return UInt32(number)
    }
    return nil
}

private func captureWindow(windowID: UInt32, to url: URL) throws -> CapturedWindow {
    do {
        return try captureWindowWithScreencapture(windowID: windowID, to: url)
    } catch {
        guard let image = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            CGWindowID(windowID),
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw error
        }
        try pngData(from: image).write(to: url)
        return CapturedWindow(image: image)
    }
}

private func captureWindowWithScreencapture(windowID: UInt32, to url: URL) throws -> CapturedWindow {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l\(windowID)", url.path]
    process.standardOutput = Pipe()
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw VerifierError.capture("screencapture failed with status \(process.terminationStatus) windowID=\(windowID) \(errorText)")
    }

    let data = try Data(contentsOf: url)
    guard let image = loadImage(from: data) else {
        throw VerifierError.capture("screencapture returned invalid PNG data")
    }
    return CapturedWindow(image: image)
}

private func pngData(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
        throw VerifierError.pngWrite("could not create PNG destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw VerifierError.pngWrite("could not finalize PNG data")
    }
    return data as Data
}

private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as _: T.Type) throws -> T {
    guard let symbol = dlsym(handle, name) else {
        throw VerifierError.bridge("missing symbol \(name): \(dlerrorString())")
    }
    return unsafeBitCast(symbol, to: T.self)
}

private enum ExpectedPixel: Hashable {
    case red
    case green
    case blue
    case yellow
    case dark
    case light
    case nonWhite
}

private extension Set where Element == ExpectedPixel {
    func isSatisfied(by stats: PixelStats) -> Bool {
        allSatisfy { expected in
            switch expected {
            case .red:
                stats.redPixels > 12_000
            case .green:
                stats.greenPixels > 12_000
            case .blue:
                stats.bluePixels > 8_000
            case .yellow:
                stats.yellowPixels > 20_000
            case .dark:
                stats.darkPixels > 1_000
            case .light:
                stats.lightPixels > 20_000
            case .nonWhite:
                stats.nonWhitePixels > 10_000
            }
        }
    }
}

private func analyze(image: CGImage) -> PixelStats {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
        CGImageAlphaInfo.premultipliedLast.rawValue

    pixels.withUnsafeMutableBytes { buffer in
        if let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    var red = 0
    var green = 0
    var blue = 0
    var yellow = 0
    var dark = 0
    var light = 0
    var nonWhite = 0

    for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])

        if r >= 220, g <= 70, b <= 70 {
            red += 1
        }
        if r <= 90, g >= 150, b <= 120 {
            green += 1
        }
        if r <= 90, g <= 130, b >= 180 {
            blue += 1
        }
        if r >= 220, g >= 180, b <= 90 {
            yellow += 1
        }
        if r < 70, g < 70, b < 70 {
            dark += 1
        }
        if r > 230, g > 230, b > 230 {
            light += 1
        }
        if r < 245 || g < 245 || b < 245 {
            nonWhite += 1
        }
    }

    return PixelStats(
        width: width,
        height: height,
        redPixels: red,
        greenPixels: green,
        bluePixels: blue,
        yellowPixels: yellow,
        darkPixels: dark,
        lightPixels: light,
        nonWhitePixels: nonWhite
    )
}

private func loadImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func processCommandLine(pid: Int32) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", "\(pid)", "-ww", "-o", "command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ""
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func containsRemoteDebuggingArgument(_ command: String) -> Bool {
    command.contains("--remote-debugging-port") ||
        command.contains("--remote-debugging-pipe") ||
        command.contains("--remote-allow-origins")
}

private func hasDevToolsActivePort(profileDirectory: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: profileDirectory.appendingPathComponent("DevToolsActivePort").path
    )
}

private func dlerrorString() -> String {
    guard let error = dlerror() else {
        return "unknown dynamic loader error"
    }
    return String(cString: error)
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private enum Fixtures {
    static let canvasFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost canvas fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        canvas { display: block; width: 960px; height: 640px; }
      </style>
    </head>
    <body>
      <canvas id="fixture" width="960" height="640"></canvas>
      <script>
        const canvas = document.getElementById("fixture");
        const context = canvas.getContext("2d");
        context.fillStyle = "rgb(248,248,248)";
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.fillStyle = "rgb(255,0,0)";
        context.fillRect(48, 56, 180, 140);
        context.fillStyle = "rgb(0,204,68)";
        context.fillRect(288, 56, 180, 140);
        context.fillStyle = "rgb(0,89,255)";
        context.fillRect(528, 56, 180, 140);
        context.fillStyle = "rgb(20,20,20)";
        context.font = "40px -apple-system, BlinkMacSystemFont, sans-serif";
        context.fillText("OWL_LAYER_HOST_SENTINEL", 48, 292);
      </script>
    </body>
    </html>
    """

    static let inputFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost input fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        #target {
          position: absolute;
          left: 48px;
          top: 56px;
          width: 244px;
          height: 148px;
          background: rgb(180, 180, 180);
        }
        #status {
          position: absolute;
          left: 48px;
          top: 260px;
          font: 42px -apple-system, BlinkMacSystemFont, sans-serif;
          color: rgb(20,20,20);
        }
        body.ready #target {
          background: rgb(255, 0, 0);
        }
        body.ready.clicked #target {
          background: rgb(255, 210, 0);
        }
      </style>
    </head>
    <body>
      <button id="target" aria-label="OWL input target"></button>
      <div id="status">OWL_INPUT_BOOTING</div>
      <script>
        const status = document.getElementById("status");
        const markInput = () => {
          document.body.classList.add("clicked");
          status.textContent = "OWL_INPUT_CLICKED";
        };
        for (const eventName of ["pointermove", "pointerdown", "pointerup", "mousemove", "mousedown", "mouseup", "click"]) {
          document.addEventListener(eventName, markInput);
        }
        document.addEventListener("keydown", markInput);
        document.body.classList.add("ready");
        status.textContent = "OWL_INPUT_READY";
      </script>
    </body>
    </html>
    """
}
