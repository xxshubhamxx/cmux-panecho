import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import OwlMojoBindingsGenerated
import QuartzCore

private struct Options {
    var chromiumHost: String
    var mojoRuntimePath: String
    var outputDirectory: URL
    var timeout: TimeInterval
    var includeCanvas: Bool
    var includeExample: Bool
    var includeInput: Bool
    var includeResize: Bool
    var includeGoogle: Bool
    var includeWidgets: Bool
    var inputDiagnosticCapture: Bool
    var onlyTargets: Set<String>
}

private struct RenderTarget {
    let name: String
    let url: String
    let screenshotName: String
    let expected: Set<ExpectedPixel>
    let preInputScreenshotName: String?
    let preInputExpected: Set<ExpectedPixel>?
    let inputActions: [InputAction]
    let postInputDiagnosticScript: String?
    let postInputExpectations: [JavaScriptExpectation]
}

private struct MouseClick {
    let x: Float
    let y: Float
    let button: UInt32
    let clickCount: UInt32

    init(x: Float, y: Float, button: UInt32 = 0, clickCount: UInt32 = 1) {
        self.x = x
        self.y = y
        self.button = button
        self.clickCount = clickCount
    }
}

private enum InputAction {
    case mouseClick(MouseClick)
    case mouseWheel(OwlFreshMouseEvent)
    case key(OwlFreshKeyEvent)
    case resize(OwlFreshHostResizeRequest, waitForMode: String)
    case text(String)
    case waitForJavaScript(label: String, script: String, expectations: [JavaScriptExpectation])
    case waitForSurfaceTree(label: String, expectations: [SurfaceTreeExpectation])
    case captureWindow(name: String, expected: Set<ExpectedPixel>)
    case captureNativeMenu(label: String, name: String, expected: Set<ExpectedPixel>, response: NativeMenuResponse)
    case acceptActivePopupMenuItem(UInt32)
    case cancelActivePopup
}

private enum NativeMenuResponse {
    case accept(UInt32)
    case cancel
}

private struct JavaScriptExpectation {
    let key: String
    let value: ExpectedJavaScriptValue
}

private struct SurfaceTreeExpectation {
    let kind: OwlFreshSurfaceKind
    let label: String?
    let menuItem: String?

    init(kind: OwlFreshSurfaceKind, label: String? = nil, menuItem: String? = nil) {
        self.kind = kind
        self.label = label
        self.menuItem = menuItem
    }
}

private enum ExpectedJavaScriptValue {
    case string(String)
    case bool(Bool)
}

private enum KeyModifiers {
    static let command = UInt32(truncatingIfNeeded: NSEvent.ModifierFlags.command.rawValue)
    static let control = UInt32(truncatingIfNeeded: NSEvent.ModifierFlags.control.rawValue)
    static let option = UInt32(truncatingIfNeeded: NSEvent.ModifierFlags.option.rawValue)
    static let shift = UInt32(truncatingIfNeeded: NSEvent.ModifierFlags.shift.rawValue)
}

private enum KeyCodes {
    static let backspace: UInt32 = 8
    static let delete: UInt32 = 46
    static let downArrow: UInt32 = 40
    static let escape: UInt32 = 27
    static let leftArrow: UInt32 = 37
    static let returnKey: UInt32 = 13
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
    let surfaceTree: OwlFreshSurfaceTree?
    let generatedTransportTracePath: String
    let generatedTransportCallCount: Int
}

private struct MojoSurfaceCapture {
    let path: String
    let mode: String
    let width: UInt32
    let height: UInt32
}

private struct Summary: Codable {
    let chromiumHost: String
    let mojoRuntimePath: String
    let outputDirectory: String
    let displayPath: String
    let contextSource: String
    let controlTransport: String
    let swiftHostTransport: String
    let mojoRuntime: String
    let mojoBindingSourceChecksum: String
    let mojoBindingDeclarationCount: Int
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
    case input(String)

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
             .layerHost(let message),
             .input(let message):
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
    let surfaceTree: OwlFreshSurfaceTree?
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
    private var surfaceTree: OwlFreshSurfaceTree?
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
        case 6:
            if let message = event.message,
               let data = String(cString: message).data(using: .utf8),
               let tree = try? JSONDecoder().decode(OwlFreshSurfaceTree.self, from: data) {
                surfaceTree = tree
            }
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
            surfaceTree: surfaceTree,
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

struct OwlLayerHostVerifier {
    static func main() {
        var outputDirectory: URL?
        do {
            let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            outputDirectory = options.outputDirectory
            try LayerHostRunner(options: options).run()
        } catch let error as VerifierError {
            writeFatalError(error.description, outputDirectory: outputDirectory)
            fputs("error: \(error.description)\n", stderr)
            exit(1)
        } catch {
            let message = String(describing: error)
            writeFatalError(message, outputDirectory: outputDirectory)
            fputs("error: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions(arguments: [String]) throws -> Options {
        var chromiumHost = ProcessInfo.processInfo.environment["OWL_CHROMIUM_HOST"] ?? ""
        var mojoRuntimePath = ProcessInfo.processInfo.environment["OWL_MOJO_RUNTIME_PATH"] ?? ""
        var outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("artifacts/layer-host-latest", isDirectory: true)
        var timeout: TimeInterval = 30
        var includeCanvas = true
        var includeExample = true
        var includeInput = false
        var includeResize = ProcessInfo.processInfo.environment["OWL_LAYER_HOST_RESIZE_CHECK"] == "1"
        var includeGoogle = ProcessInfo.processInfo.environment["OWL_LAYER_HOST_GOOGLE_CHECK"] == "1"
        var includeWidgets = ProcessInfo.processInfo.environment["OWL_LAYER_HOST_WIDGET_CHECK"] == "1"
        var inputDiagnosticCapture = false
        var onlyTargets = Set(
            (ProcessInfo.processInfo.environment["OWL_LAYER_HOST_ONLY_TARGETS"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

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
            case "--mojo-runtime":
                index += 1
                guard index < arguments.count else {
                    throw VerifierError.usage("missing value for \(argument)")
                }
                mojoRuntimePath = arguments[index]
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
            case "--resize-check":
                includeResize = true
            case "--google-check":
                includeGoogle = true
            case "--widget-check":
                includeWidgets = true
            case "--input-diagnostic-capture":
                inputDiagnosticCapture = true
            case "--only-target":
                index += 1
                guard index < arguments.count else {
                    throw VerifierError.usage("missing value for --only-target")
                }
                onlyTargets.insert(arguments[index])
            case "--help":
                print("""
                Usage: OwlLayerHostVerifier --chromium-host <path> --mojo-runtime <path> [--output-dir <dir>] [--timeout <seconds>] [--skip-canvas] [--skip-example] [--input-check] [--resize-check] [--google-check] [--widget-check] [--input-diagnostic-capture] [--only-target <name>]
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
        guard !mojoRuntimePath.isEmpty else {
            throw VerifierError.usage("missing --mojo-runtime or OWL_MOJO_RUNTIME_PATH")
        }

        return Options(
            chromiumHost: chromiumHost,
            mojoRuntimePath: mojoRuntimePath,
            outputDirectory: outputDirectory,
            timeout: timeout,
            includeCanvas: includeCanvas,
            includeExample: includeExample,
            includeInput: includeInput,
            includeResize: includeResize,
            includeGoogle: includeGoogle,
            includeWidgets: includeWidgets,
            inputDiagnosticCapture: inputDiagnosticCapture,
            onlyTargets: onlyTargets
        )
    }
}

private func writeFatalError(_ message: String, outputDirectory: URL?) {
    guard let outputDirectory else {
        return
    }
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try? "error: \(message)\n".write(
        to: outputDirectory.appendingPathComponent("fatal-error.txt"),
        atomically: true,
        encoding: .utf8
    )
}

OwlLayerHostVerifier.main()

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
        guard fileManager.fileExists(atPath: options.mojoRuntimePath) else {
            throw VerifierError.usage("OWL Mojo runtime dylib does not exist: \(options.mojoRuntimePath)")
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
        let formFixture = try writeFixture(
            name: "form-fixture",
            html: Fixtures.formFixture,
            directory: fixtureDirectory
        )
        let modifierFixture = try writeFixture(
            name: "modifier-fixture",
            html: Fixtures.modifierFixture,
            directory: fixtureDirectory
        )
        let resizeFixture = try writeFixture(
            name: "resize-fixture",
            html: Fixtures.resizeFixture,
            directory: fixtureDirectory
        )
        let scrollFixture = try writeFixture(
            name: "scroll-fixture",
            html: Fixtures.scrollFixture,
            directory: fixtureDirectory
        )
        let textEditingFixture = try writeFixture(
            name: "text-edit-fixture",
            html: Fixtures.textEditingFixture,
            directory: fixtureDirectory
        )
        let widgetFixture = try writeFixture(
            name: "widget-fixture",
            html: Fixtures.widgetFixture,
            directory: fixtureDirectory
        )
        let nativePopupFixture = try writeFixture(
            name: "native-popup-fixture",
            html: Fixtures.nativePopupFixture,
            directory: fixtureDirectory
        )
        let plainNativeSelectFixture = try writeFixture(
            name: "plain-native-select-fixture",
            html: Fixtures.plainNativeSelectFixture,
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
                inputActions: [],
                postInputDiagnosticScript: nil,
                postInputExpectations: []
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
                    inputActions: [],
                    postInputDiagnosticScript: nil,
                    postInputExpectations: []
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
                    inputActions: [
                        .mouseClick(MouseClick(x: 170, y: 180)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: 88, text: "x", modifiers: 0)),
                    ],
                    postInputDiagnosticScript: "({className: document.body.className, status: document.getElementById('status')?.textContent || ''})",
                    postInputExpectations: [
                        JavaScriptExpectation(key: "status", value: .string("OWL_INPUT_CLICKED")),
                    ]
                )
            )
            targets.append(
                RenderTarget(
                    name: "form-fixture",
                    url: formFixture.absoluteString,
                    screenshotName: "form-fixture-after-submit.png",
                    expected: [.green, .yellow, .dark],
                    preInputScreenshotName: "form-fixture-before-input.png",
                    preInputExpected: [.blue, .dark, .light],
                    inputActions: [
                        .mouseClick(MouseClick(x: 170, y: 152)),
                        .text("hello owl"),
                        .mouseClick(MouseClick(x: 68, y: 244)),
                        .mouseClick(MouseClick(x: 151, y: 333)),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      activeId: document.activeElement?.id || "",
                      checked: document.getElementById("agree")?.checked === true,
                      status: document.getElementById("status")?.textContent || "",
                      submitted: document.body.classList.contains("submitted"),
                      typed: document.getElementById("nameInput")?.value || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "checked", value: .bool(true)),
                        JavaScriptExpectation(key: "status", value: .string("HELLO_OWL_SUBMITTED")),
                        JavaScriptExpectation(key: "submitted", value: .bool(true)),
                        JavaScriptExpectation(key: "typed", value: .string("hello owl")),
                    ]
                )
            )
            targets.append(
                RenderTarget(
                    name: "modifier-fixture",
                    url: modifierFixture.absoluteString,
                    screenshotName: "modifier-fixture-after-input.png",
                    expected: [.green, .yellow, .dark],
                    preInputScreenshotName: "modifier-fixture-before-input.png",
                    preInputExpected: [.blue, .dark, .light],
                    inputActions: [
                        .mouseClick(MouseClick(x: 180, y: 152)),
                        .text("plain"),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: 77, text: "", modifiers: KeyModifiers.command)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: 79, text: "", modifiers: KeyModifiers.option)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: 67, text: "", modifiers: KeyModifiers.control)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: 83, text: "S", modifiers: KeyModifiers.shift)),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      commandSeen: window.owlModifierState?.commandSeen === true,
                      controlSeen: window.owlModifierState?.controlSeen === true,
                      optionSeen: window.owlModifierState?.optionSeen === true,
                      shiftSeen: window.owlModifierState?.shiftSeen === true,
                      status: document.getElementById("status")?.textContent || "",
                      typed: document.getElementById("modInput")?.value || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "commandSeen", value: .bool(true)),
                        JavaScriptExpectation(key: "controlSeen", value: .bool(true)),
                        JavaScriptExpectation(key: "optionSeen", value: .bool(true)),
                        JavaScriptExpectation(key: "shiftSeen", value: .bool(true)),
                        JavaScriptExpectation(key: "status", value: .string("OWL_MODIFIERS_OK")),
                        JavaScriptExpectation(key: "typed", value: .string("plainS")),
                    ]
                )
            )
            let requestedResizeTargets = !options.onlyTargets.isDisjoint(with: [
                "resize-small-fixture",
                "resize-roundtrip-fixture",
            ])
            if options.includeResize || requestedResizeTargets {
                targets.append(
                    RenderTarget(
                        name: "resize-small-fixture",
                        url: resizeFixture.absoluteString,
                        screenshotName: "resize-small-after.png",
                        expected: [.green, .yellow, .dark],
                        preInputScreenshotName: "resize-small-before.png",
                        preInputExpected: [.blue, .dark, .light],
                        inputActions: [
                            .resize(OwlFreshHostResizeRequest(width: 720, height: 480, scale: 1.0), waitForMode: "small"),
                        ],
                        postInputDiagnosticScript: """
                        ({
                          mode: window.owlResizeState?.mode || "",
                          status: document.getElementById("status")?.textContent || ""
                        })
                        """,
                        postInputExpectations: [
                            JavaScriptExpectation(key: "mode", value: .string("small")),
                            JavaScriptExpectation(key: "status", value: .string("OWL_RESIZE_SMALL_OK")),
                        ]
                    )
                )
                targets.append(
                    RenderTarget(
                        name: "resize-roundtrip-fixture",
                        url: resizeFixture.absoluteString,
                        screenshotName: "resize-roundtrip-after.png",
                        expected: [.green, .yellow, .dark],
                        preInputScreenshotName: "resize-roundtrip-before.png",
                        preInputExpected: [.blue, .dark, .light],
                        inputActions: [
                            .resize(OwlFreshHostResizeRequest(width: 720, height: 480, scale: 1.0), waitForMode: "small"),
                            .resize(OwlFreshHostResizeRequest(width: 960, height: 640, scale: 1.0), waitForMode: "restored"),
                        ],
                        postInputDiagnosticScript: """
                        ({
                          mode: window.owlResizeState?.mode || "",
                          status: document.getElementById("status")?.textContent || ""
                        })
                        """,
                        postInputExpectations: [
                            JavaScriptExpectation(key: "mode", value: .string("restored")),
                            JavaScriptExpectation(key: "status", value: .string("OWL_RESIZE_ROUNDTRIP_OK")),
                        ]
                    )
                )
            }
            targets.append(
                RenderTarget(
                    name: "scroll-fixture",
                    url: scrollFixture.absoluteString,
                    screenshotName: "scroll-fixture-after.png",
                    expected: [.green, .yellow, .dark],
                    preInputScreenshotName: "scroll-fixture-before.png",
                    preInputExpected: [.blue, .dark, .light],
                    inputActions: [
                        .mouseWheel(OwlFreshMouseEvent(
                            kind: .wheel,
                            x: 520,
                            y: 520,
                            button: 0,
                            clickCount: 0,
                            deltaX: 0,
                            deltaY: -900,
                            modifiers: 0
                        )),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      ok: window.owlScrollState?.ok === true,
                      firstVisibleLine: window.owlScrollState?.firstVisibleLine || "",
                      status: document.getElementById("status")?.textContent || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "ok", value: .bool(true)),
                        JavaScriptExpectation(key: "firstVisibleLine", value: .string("LINE_06")),
                        JavaScriptExpectation(key: "status", value: .string("OWL_SCROLL_LINE_OK")),
                    ]
                )
            )
            targets.append(
                RenderTarget(
                    name: "text-edit-fixture",
                    url: textEditingFixture.absoluteString,
                    screenshotName: "text-edit-fixture-after.png",
                    expected: [.green, .yellow, .dark],
                    preInputScreenshotName: "text-edit-fixture-before.png",
                    preInputExpected: [.blue, .dark, .light],
                    inputActions: [
                        .mouseClick(MouseClick(x: 170, y: 152)),
                        .text("abcdef"),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.leftArrow, text: "", modifiers: 0)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.leftArrow, text: "", modifiers: 0)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.backspace, text: "", modifiers: 0)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.delete, text: "", modifiers: 0)),
                        .text("Z"),
                        .text("final"),
                        .mouseClick(MouseClick(x: 170, y: 356)),
                        .text("selection"),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.leftArrow, text: "", modifiers: KeyModifiers.shift)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.leftArrow, text: "", modifiers: KeyModifiers.shift)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.leftArrow, text: "", modifiers: KeyModifiers.shift)),
                        .text("XYZ"),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      editTyped: document.getElementById("editInput")?.value || "",
                      sawEditIntermediate: window.owlTextEditState?.sawIntermediate === true,
                      sawSelection: window.owlTextEditState?.sawSelection === true,
                      sawSelectionReplacement: window.owlTextEditState?.sawSelectionReplacement === true,
                      selectionTyped: document.getElementById("selectionInput")?.value || "",
                      sawIntermediate: window.owlTextEditState?.sawIntermediate === true,
                      status: document.getElementById("status")?.textContent || "",
                      typed: document.getElementById("editInput")?.value || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "editTyped", value: .string("abcZfinalf")),
                        JavaScriptExpectation(key: "sawEditIntermediate", value: .bool(true)),
                        JavaScriptExpectation(key: "sawIntermediate", value: .bool(true)),
                        JavaScriptExpectation(key: "sawSelection", value: .bool(true)),
                        JavaScriptExpectation(key: "sawSelectionReplacement", value: .bool(true)),
                        JavaScriptExpectation(key: "selectionTyped", value: .string("selectXYZ")),
                        JavaScriptExpectation(key: "status", value: .string("OWL_TEXT_SELECTION_OK")),
                        JavaScriptExpectation(key: "typed", value: .string("abcZfinalf")),
                    ]
                )
            )
        }
        let requestedGoogleTargets = options.onlyTargets.contains("google-search")
        if options.includeGoogle || requestedGoogleTargets {
            targets.append(
                RenderTarget(
                    name: "google-search",
                    url: "https://www.google.com/?hl=en&igu=1",
                    screenshotName: "google-search-after-type.png",
                    expected: [.dark, .light, .nonWhite],
                    preInputScreenshotName: "google-search-before-type.png",
                    preInputExpected: [.dark, .light, .nonWhite],
                    inputActions: [
                        .waitForJavaScript(
                            label: "google search box",
                            script: """
                            (() => {
                              const input = document.querySelector('textarea[name="q"], input[name="q"]');
                              if (!input) {
                                return { ready: false };
                              }
                              input.focus();
                              return {
                                activeName: document.activeElement?.getAttribute("name") || "",
                                ready: document.activeElement === input,
                                tag: input.tagName
                              };
                            })()
                            """,
                            expectations: [
                                JavaScriptExpectation(key: "ready", value: .bool(true)),
                            ]
                        ),
                        .text("owl mojo layer host"),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      activeName: document.activeElement?.getAttribute("name") || "",
                      query: document.querySelector('textarea[name="q"], input[name="q"]')?.value || "",
                      title: document.title || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "query", value: .string("owl mojo layer host")),
                    ]
                )
            )
        }
        let requestedWidgetTargets = options.onlyTargets.contains("widget-fixture")
            || options.onlyTargets.contains("native-popup-fixture")
            || options.onlyTargets.contains("plain-native-select-fixture")
        if options.includeWidgets || requestedWidgetTargets {
            targets.append(
                RenderTarget(
                    name: "widget-fixture",
                    url: widgetFixture.absoluteString,
                    screenshotName: "widget-fixture-after-input.png",
                    expected: [.green, .yellow, .dark],
                    preInputScreenshotName: "widget-fixture-before-input.png",
                    preInputExpected: [.blue, .dark, .light],
                    inputActions: [
                        .waitForJavaScript(
                            label: "widget fixture ready",
                            script: """
                            ({
                              ready: window.owlWidgetState?.ready === true
                            })
                            """,
                            expectations: [
                                JavaScriptExpectation(key: "ready", value: .bool(true)),
                            ]
                        ),
                        .mouseClick(MouseClick(x: 188, y: 190)),
                        .mouseClick(MouseClick(x: 330, y: 312, button: 2)),
                        .cancelActivePopup,
                        .mouseClick(MouseClick(x: 192, y: 470)),
                        .key(OwlFreshKeyEvent(keyDown: true, keyCode: KeyCodes.escape, text: "", modifiers: 0)),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      colorClicked: window.owlWidgetState?.colorClicked === true,
                      colorFocused: window.owlWidgetState?.colorFocused === true,
                      contextSeen: window.owlWidgetState?.contextSeen === true,
                      selectValue: document.getElementById("nativeSelect")?.value || "",
                      status: document.getElementById("status")?.textContent || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "colorClicked", value: .bool(true)),
                        JavaScriptExpectation(key: "colorFocused", value: .bool(true)),
                        JavaScriptExpectation(key: "contextSeen", value: .bool(true)),
                        JavaScriptExpectation(key: "selectValue", value: .string("beta")),
                        JavaScriptExpectation(key: "status", value: .string("OWL_WIDGETS_OK")),
                    ]
                )
            )
            targets.append(
                RenderTarget(
                    name: "plain-native-select-fixture",
                    url: plainNativeSelectFixture.absoluteString,
                    screenshotName: "plain-native-select-after-input.png",
                    expected: [.dark, .light, .nonWhite, .green],
                    preInputScreenshotName: "plain-native-select-before-input.png",
                    preInputExpected: [.dark, .light, .nonWhite, .blue],
                    inputActions: [
                        .waitForJavaScript(
                            label: "plain native select ready",
                            script: """
                            ({
                              hit: document.elementFromPoint(158, 159)?.id || "",
                              ready: window.owlPlainNativeSelectState?.ready === true &&
                                document.readyState === "complete" &&
                                document.getElementById("plainSelect") instanceof HTMLSelectElement
                            })
                            """,
                            expectations: [
                                JavaScriptExpectation(key: "hit", value: .string("plainSelect")),
                                JavaScriptExpectation(key: "ready", value: .bool(true)),
                            ]
                        ),
                        .mouseClick(MouseClick(x: 158, y: 159)),
                        .waitForSurfaceTree(
                            label: "plain native select popup surface",
                            expectations: [
                                SurfaceTreeExpectation(
                                    kind: .nativeMenu,
                                    label: "select-menu",
                                    menuItem: "Beta"
                                ),
                            ]
                        ),
                        .captureNativeMenu(
                            label: "select-menu",
                            name: "plain-native-select-popup-open.png",
                            expected: [.dark, .light, .nonWhite],
                            response: .accept(1)
                        ),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      selectValue: document.getElementById("plainSelect")?.value || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "selectValue", value: .string("beta")),
                    ]
                )
            )
            targets.append(
                RenderTarget(
                    name: "native-popup-fixture",
                    url: nativePopupFixture.absoluteString,
                    screenshotName: "native-popup-after-input.png",
                    expected: [.green, .yellow, .dark],
                    preInputScreenshotName: "native-popup-before-input.png",
                    preInputExpected: [.blue, .dark, .light],
                    inputActions: [
                        .waitForJavaScript(
                            label: "native popup fixture ready",
                            script: """
                            ({
                              ready: window.owlNativePopupState?.ready === true
                            })
                            """,
                            expectations: [
                                JavaScriptExpectation(key: "ready", value: .bool(true)),
                            ]
                        ),
                        .mouseClick(MouseClick(x: 190, y: 172)),
                        .waitForSurfaceTree(
                            label: "select popup surface",
                            expectations: [
                                SurfaceTreeExpectation(
                                    kind: .nativeMenu,
                                    label: "select-menu",
                                    menuItem: "BETA_NATIVE_OPTION"
                                ),
                            ]
                        ),
                        .captureNativeMenu(
                            label: "select-menu",
                            name: "native-select-popup-open.png",
                            expected: [.dark, .light, .nonWhite],
                            response: .accept(1)
                        ),
                        .waitForJavaScript(
                            label: "native select accepted",
                            script: """
                            ({
                              selectValue: document.getElementById("nativeSelect")?.value || ""
                            })
                            """,
                            expectations: [
                                JavaScriptExpectation(key: "selectValue", value: .string("beta")),
                            ]
                        ),
                        .mouseClick(MouseClick(x: 330, y: 338, button: 2)),
                        .waitForSurfaceTree(
                            label: "context menu surface",
                            expectations: [
                                SurfaceTreeExpectation(
                                    kind: .nativeMenu,
                                    label: "context-menu",
                                    menuItem: "Inspect"
                                ),
                            ]
                        ),
                        .captureNativeMenu(
                            label: "context-menu",
                            name: "native-context-menu-open.png",
                            expected: [.dark, .light, .nonWhite],
                            response: .cancel
                        ),
                    ],
                    postInputDiagnosticScript: """
                    ({
                      contextSeen: window.owlNativePopupState?.contextSeen === true,
                      selectValue: document.getElementById("nativeSelect")?.value || "",
                      status: document.getElementById("status")?.textContent || ""
                    })
                    """,
                    postInputExpectations: [
                        JavaScriptExpectation(key: "contextSeen", value: .bool(true)),
                        JavaScriptExpectation(key: "selectValue", value: .string("beta")),
                        JavaScriptExpectation(key: "status", value: .string("OWL_NATIVE_POPUPS_OK")),
                    ]
                )
            )
        }
        if !options.onlyTargets.isEmpty {
            let availableTargetNames = Set(targets.map(\.name))
            let missingTargets = options.onlyTargets.subtracting(availableTargetNames)
            guard missingTargets.isEmpty else {
                throw VerifierError.usage(
                    "unknown or disabled --only-target value(s): \(missingTargets.sorted().joined(separator: ", "))"
                )
            }
            targets = targets.filter { options.onlyTargets.contains($0.name) }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        let runtime = try OwlFreshMojoRuntime(path: options.mojoRuntimePath)
        try runtime.initialize()

        var captures: [CaptureResult] = []
        for target in targets {
            captures.append(try runCapture(target: target, runtime: runtime, app: app))
        }

        let summary = Summary(
            chromiumHost: options.chromiumHost,
            mojoRuntimePath: options.mojoRuntimePath,
            outputDirectory: options.outputDirectory.path,
            displayPath: "Mojo-published CAContext id hosted by Swift CALayerHost",
            contextSource: ProcessInfo.processInfo.environment["OWL_FRESH_LAYER_FIXTURE"] == nil
                ? "chromium-compositor-ca-context"
                : "chromium-layer-fixture-ca-context",
            controlTransport: "mojo",
            swiftHostTransport: OwlFreshGeneratedMojoTransport.name,
            mojoRuntime: "owl_fresh generic Mojo invoke runtime",
            mojoBindingSourceChecksum: OwlFreshMojoSchema.sourceChecksum,
            mojoBindingDeclarationCount: OwlFreshMojoSchema.declarations.count,
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
        let transportReportURL = options.outputDirectory.appendingPathComponent(
            "generated-transport-report.html"
        )
        try renderGeneratedTransportReport(summary: summary).write(
            to: transportReportURL,
            atomically: true,
            encoding: .utf8
        )

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
        runtime: OwlFreshMojoRuntime,
        app: NSApplication
    ) throws -> CaptureResult {
        let profileDirectory = options.outputDirectory
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent("\(target.name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let useLayerFixture = ProcessInfo.processInfo.environment["OWL_FRESH_LAYER_FIXTURE"] != nil
        let initialURL = useLayerFixture ? target.url : "about:blank"
        let sessionEvents = SessionEvents()
        let session = try runtime.createSession(
            chromiumHost: options.chromiumHost,
            initialURL: initialURL,
            userDataDirectory: profileDirectory.path,
            events: sessionEvents
        )
        var hostPID: Int32 = -1
        defer {
            runtime.destroy(session)
            terminateHostProcessIfNeeded(pid: hostPID)
            pumpApp(app, for: 0.2)
        }
        let hostController = OwlFreshMojoHostController(
            runtime: runtime,
            session: session
        )

        try hostController.resize(
            OwlFreshHostResizeRequest(
                width: UInt32(contentSize.width),
                height: UInt32(contentSize.height),
                scale: 1.0
            )
        )
        try hostController.setFocus(true)

        hostPID = runtime.hostPID(session)
        guard hostPID > 0 else {
            throw VerifierError.launch("Mojo runtime did not report a valid host PID for \(target.name)")
        }

        try waitForReady(name: target.name, events: sessionEvents, runtime: runtime, app: app)
        let baseline = sessionEvents.snapshot()
        var contextID: UInt32
        if useLayerFixture, baseline.contextID != 0 {
            contextID = baseline.contextID
        } else {
            try hostController.navigate(target.url)
            try waitForInitialReadinessIfPresent(
                target: target,
                runtime: runtime,
                session: session,
                events: sessionEvents,
                app: app
            )
            try waitForHostFlush(runtime: runtime, session: session, app: app)
            contextID = try waitForInitialWebViewContextID(
                name: target.name,
                events: sessionEvents,
                runtime: runtime,
                hostController: hostController,
                app: app
            )
        }
        let window = try LayerHostWindow(
            title: "OWL LayerHost \(target.name)",
            contextID: contextID,
            size: contentSize
        )
        defer {
            window.close()
            pumpApp(app, for: 0.2)
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
        var inputSent = target.inputActions.isEmpty
        var currentExpected = target.preInputExpected ?? target.expected
        var currentSize = contentSize
        var capturedPreInputPath: String?
        var postInputStateVerified = false
        var postInputDiagnosticsWritten = false

        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.05)
            window.flushHostedLayer()

            let snapshot = sessionEvents.snapshot()
            if useLayerFixture, snapshot.contextID != 0, snapshot.contextID != contextID {
                contextID = snapshot.contextID
                window.update(contextID: contextID)
                pumpApp(app, for: 0.05)
            }
            if let surfaceTree = snapshot.surfaceTree {
                window.update(surfaceTree: surfaceTree)
            }

            if !target.inputActions.isEmpty, inputSent, !postInputStateVerified {
                do {
                    try verifyPostInputStateIfNeeded(target: target, runtime: runtime, session: session)
                    postInputStateVerified = true
                    try hostController.setFocus(true)
                    runtime.pollEvents(milliseconds: 10)
                } catch let error as VerifierError {
                    lastError = error.description
                    continue
                } catch {
                    lastError = String(describing: error)
                    continue
                }
            }

            if inputSent {
                app.activate(ignoringOtherApps: true)
                window.show()
                pumpApp(app, for: 0.02)
            }

            guard let windowID = swiftHostWindowID(title: window.title, minimumSize: currentSize) else {
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
                    if !inputSent {
                        capturedPreInputPath = captureURL.path
                        try hostController.setFocus(true)
                        try performInputActions(
                            target.inputActions,
                            target: target,
                            runtime: runtime,
                            hostController: hostController,
                            session: session,
                            events: sessionEvents,
                            window: window,
                            app: app,
                            currentSize: &currentSize
                        )
                        pumpApp(app, for: 0.05)
                        if options.inputDiagnosticCapture {
                            writePostInputDOMState(target: target, runtime: runtime, session: session)
                        }
                        inputSent = true
                        currentExpected = target.expected
                        lastError = "input actions sent through Mojo; waiting for post-input pixels"
                        continue
                    }
                    if !target.inputActions.isEmpty,
                       inputSent,
                       options.inputDiagnosticCapture,
                       !postInputDiagnosticsWritten {
                        writePostInputDiagnostics(target: target, runtime: runtime, session: session)
                        postInputDiagnosticsWritten = true
                    }
                    let hostCommand = processCommandLine(pid: hostPID)
                    try rejectForbiddenRuntimePaths(
                        processCommand: hostCommand,
                        profileDirectory: profileDirectory,
                        name: target.name
                    )
                    let traceURL = options.outputDirectory.appendingPathComponent(
                        "\(target.name)-generated-transport-trace.json"
                    )
                    try JSONEncoder.pretty.encode(hostController.recordedCalls).write(to: traceURL)
                    let finalEventSnapshot = sessionEvents.snapshot()
                    let finalSurfaceTree = (try? hostController.getSurfaceTree())
                        ?? finalEventSnapshot.surfaceTree
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
                        sessionEvents: finalEventSnapshot,
                        surfaceTree: finalSurfaceTree,
                        generatedTransportTracePath: traceURL.path,
                        generatedTransportCallCount: hostController.recordedCalls.count
                    )
                }
                lastError = "pixel stats did not match expected set \(currentExpected): \(stats)"
            } catch let error as VerifierError {
                if case .input(let message) = error,
                   message.hasPrefix("expected resize mode ") {
                    throw error
                }
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
        runtime: OwlFreshMojoRuntime,
        app: NSApplication,
        afterGeneration: UInt64,
        rejectingContextID: UInt32?
    ) throws -> UInt32 {
        let deadline = Date().addingTimeInterval(min(15, options.timeout))
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
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

    private func waitForInitialReadinessIfPresent(
        target: RenderTarget,
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer,
        events: SessionEvents,
        app: NSApplication
    ) throws {
        guard case .waitForJavaScript(let label, let script, let expectations) = target.inputActions.first else {
            return
        }
        try waitForJavaScriptExpectations(
            label: "initial \(label)",
            script: script,
            expectations: expectations,
            runtime: runtime,
            session: session,
            events: events,
            app: app
        )
    }

    private func waitForInitialWebViewContextID(
        name: String,
        events: SessionEvents,
        runtime: OwlFreshMojoRuntime,
        hostController: OwlFreshMojoHostController,
        app: NSApplication
    ) throws -> UInt32 {
        let deadline = Date().addingTimeInterval(min(10, options.timeout))
        var lastTree: OwlFreshSurfaceTree?
        var lastError = ""
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.02)
            do {
                let tree = try hostController.getSurfaceTree()
                lastTree = tree
                if let surface = tree.surfaces.first(where: {
                    $0.visible && $0.kind == .webView && $0.contextId != 0
                }) {
                    return surface.contextId
                }
            } catch {
                lastError = String(describing: error)
            }
        }
        throw VerifierError.timeout(
            "timed out waiting for \(name) initial web-view surface; lastTree=\(String(describing: lastTree)); lastError=\(lastError); events=\(events.snapshot())"
        )
    }

    private func waitForReady(
        name: String,
        events: SessionEvents,
        runtime: OwlFreshMojoRuntime,
        app: NSApplication
    ) throws {
        let deadline = Date().addingTimeInterval(min(10, options.timeout))
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
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

    private func performInputActions(
        _ actions: [InputAction],
        target: RenderTarget,
        runtime: OwlFreshMojoRuntime,
        hostController: OwlFreshMojoHostController,
        session: OpaquePointer,
        events: SessionEvents,
        window: LayerHostWindow,
        app: NSApplication,
        currentSize: inout CGSize
    ) throws {
        for action in actions {
            switch action {
            case .mouseClick(let click):
                if ProcessInfo.processInfo.environment["OWL_LAYER_HOST_KEY_ONLY"] == "1" {
                    continue
                }
                try hostController.sendMouse(OwlFreshMouseEvent(
                    kind: .move,
                    x: click.x,
                    y: click.y,
                    button: 0,
                    clickCount: 0,
                    deltaX: 0,
                    deltaY: 0,
                    modifiers: 0
                ))
                runtime.pollEvents(milliseconds: 10)
                try hostController.sendMouse(OwlFreshMouseEvent(
                    kind: .down,
                    x: click.x,
                    y: click.y,
                    button: click.button,
                    clickCount: click.clickCount,
                    deltaX: 0,
                    deltaY: 0,
                    modifiers: 0
                ))
                runtime.pollEvents(milliseconds: 10)
                try hostController.sendMouse(OwlFreshMouseEvent(
                    kind: .up,
                    x: click.x,
                    y: click.y,
                    button: click.button,
                    clickCount: click.clickCount,
                    deltaX: 0,
                    deltaY: 0,
                    modifiers: 0
                ))
                runtime.pollEvents(milliseconds: 10)
            case .mouseWheel(let wheel):
                try hostController.sendMouse(wheel)
                runtime.pollEvents(milliseconds: 20)
                try waitForHostFlush(runtime: runtime, session: session, app: app)
            case .key(let stroke):
                try sendKeyStroke(stroke, runtime: runtime, hostController: hostController)
            case .resize(let resize, let expectedMode):
                try hostController.resize(resize)
                currentSize = CGSize(
                    width: CGFloat(Int(resize.width)),
                    height: CGFloat(Int(resize.height))
                )
                window.resize(to: currentSize)
                pumpApp(app, for: 0.2)
                runtime.pollEvents(milliseconds: 50)
                window.flushHostedLayer()
                try waitForHostFlush(runtime: runtime, session: session, app: app)
                try waitForResizeMode(
                    expectedMode,
                    runtime: runtime,
                    session: session,
                    events: events,
                    app: app
                )
            case .text(let text):
                for character in text {
                    guard let stroke = OwlFreshKeyEvent.typing(character) else {
                        throw VerifierError.input("unsupported typed character for \(character)")
                    }
                    try sendKeyStroke(stroke, runtime: runtime, hostController: hostController)
                }
            case .waitForJavaScript(let label, let script, let expectations):
                try waitForJavaScriptExpectations(
                    label: label,
                    script: script,
                    expectations: expectations,
                    runtime: runtime,
                    session: session,
                    events: events,
                    app: app
                )
            case .waitForSurfaceTree(let label, let expectations):
                let tree = try waitForSurfaceTreeExpectations(
                    label: label,
                    expectations: expectations,
                    runtime: runtime,
                    hostController: hostController,
                    session: session,
                    events: events,
                    window: window,
                    app: app
                )
                window.update(surfaceTree: tree)
            case .captureWindow(let name, let expected):
                window.update(surfaceTree: try hostController.getSurfaceTree())
                window.flushHostedLayer()
                pumpApp(app, for: 0.05)
                guard let windowID = swiftHostWindowID(title: window.title, minimumSize: currentSize) else {
                    throw VerifierError.capture("Swift LayerHost window was not visible for \(name)")
                }
                let captureURL = options.outputDirectory.appendingPathComponent(name)
                let capture = try captureWindow(windowID: windowID, to: captureURL)
                let stats = analyze(image: capture.image)
                guard expected.isSatisfied(by: stats) else {
                    throw VerifierError.pixelCheck("\(target.name) \(name) pixels did not match \(expected): \(stats)")
                }
            case .captureNativeMenu(let label, let name, let expected, let response):
                let tree = try hostController.getSurfaceTree()
                window.update(surfaceTree: tree)
                window.flushHostedLayer()
                guard let surface = tree.surfaces.first(where: {
                    $0.visible && $0.kind == .nativeMenu && $0.label == label
                }) else {
                    throw VerifierError.input("\(target.name) missing native menu surface \(label): \(tree)")
                }
                try validateNativeMenuSurface(surface, targetName: target.name)
                try writeNativeMenuSurface(surface, screenshotName: name, outputDirectory: options.outputDirectory)
                guard let windowID = swiftHostWindowID(title: window.title, minimumSize: currentSize) else {
                    throw VerifierError.capture("Swift LayerHost window was not visible for \(name)")
                }
                let captureURL = options.outputDirectory.appendingPathComponent(name)
                let capture = try window.presentNativeMenuAndCapture(
                    surface: surface,
                    windowID: windowID,
                    to: captureURL
                )
                let stats = analyze(image: capture.image)
                guard expected.isSatisfied(by: stats) else {
                    throw VerifierError.pixelCheck("\(target.name) \(name) native menu pixels did not match \(expected): \(stats)")
                }
                switch response {
                case .accept(let index):
                    guard try hostController.acceptActivePopupMenuItem(index) else {
                        throw VerifierError.input("host did not accept active popup menu item \(index)")
                    }
                case .cancel:
                    _ = try hostController.cancelActivePopup()
                }
                runtime.pollEvents(milliseconds: 50)
                window.update(surfaceTree: try hostController.getSurfaceTree())
                window.flushHostedLayer()
                try waitForHostFlush(runtime: runtime, session: session, app: app)
            case .acceptActivePopupMenuItem(let index):
                guard try hostController.acceptActivePopupMenuItem(index) else {
                    throw VerifierError.input("host did not accept active popup menu item \(index)")
                }
                runtime.pollEvents(milliseconds: 50)
                window.update(surfaceTree: try hostController.getSurfaceTree())
                window.flushHostedLayer()
                try waitForHostFlush(runtime: runtime, session: session, app: app)
            case .cancelActivePopup:
                _ = try hostController.cancelActivePopup()
                runtime.pollEvents(milliseconds: 50)
                window.update(surfaceTree: try hostController.getSurfaceTree())
                window.flushHostedLayer()
                try waitForHostFlush(runtime: runtime, session: session, app: app)
            }
        }
    }

    private func waitForJavaScriptExpectations(
        label: String,
        script: String,
        expectations: [JavaScriptExpectation],
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer,
        events: SessionEvents,
        app: NSApplication
    ) throws {
        let deadline = Date().addingTimeInterval(10)
        var lastResult = ""
        var lastError = ""
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.02)
            do {
                let result = try runtime.executeJavaScript(session, script: script)
                lastResult = result
                try verifyJavaScriptExpectations(
                    result: result,
                    expectations: expectations,
                    targetName: label
                )
                return
            } catch {
                lastError = String(describing: error)
            }
        }
        throw VerifierError.input(
            "timed out waiting for \(label); lastResult=\(lastResult); lastError=\(lastError); logs=\(events.snapshot().logs)"
        )
    }

    private func waitForSurfaceTreeExpectations(
        label: String,
        expectations: [SurfaceTreeExpectation],
        runtime: OwlFreshMojoRuntime,
        hostController: OwlFreshMojoHostController,
        session: OpaquePointer,
        events: SessionEvents,
        window: LayerHostWindow,
        app: NSApplication
    ) throws -> OwlFreshSurfaceTree {
        let deadline = Date().addingTimeInterval(10)
        var lastTree: OwlFreshSurfaceTree?
        var lastError = ""
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.02)
            do {
                let tree = try hostController.getSurfaceTree()
                lastTree = tree
                window.update(surfaceTree: tree)
                if surfaceTree(tree, satisfies: expectations) {
                    return tree
                }
            } catch {
                lastError = String(describing: error)
            }
        }
        throw VerifierError.input(
            "timed out waiting for \(label); lastTree=\(String(describing: lastTree)); lastError=\(lastError); logs=\(events.snapshot().logs)"
        )
    }

    private func surfaceTree(
        _ tree: OwlFreshSurfaceTree,
        satisfies expectations: [SurfaceTreeExpectation]
    ) -> Bool {
        expectations.allSatisfy { expectation in
            tree.surfaces.contains { surface in
                guard surface.visible, surface.kind == expectation.kind else {
                    return false
                }
                if let label = expectation.label, surface.label != label {
                    return false
                }
                if let menuItem = expectation.menuItem,
                   !surface.menuItems.contains(where: { $0.contains(menuItem) }) {
                    return false
                }
                return true
            }
        }
    }

    private func waitForHostFlush(
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer,
        app: NSApplication
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        var lastError = "host flush was not requested"
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 20)
            pumpApp(app, for: 0.02)
            do {
                try runtime.flushHost(session)
                return
            } catch {
                lastError = String(describing: error)
            }
        }
        throw VerifierError.bridge("timed out waiting for host Mojo flush: \(lastError)")
    }

    private func waitForResizeMode(
        _ expectedMode: String,
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer,
        events: SessionEvents,
        app: NSApplication
    ) throws {
        let script = """
        ({
          height: window.innerHeight,
          mode: window.owlResizeState?.mode || "",
          sawSmall: window.owlResizeState?.sawSmall === true,
          status: document.getElementById("status")?.textContent || "",
          width: window.innerWidth
        })
        """
        let deadline = Date().addingTimeInterval(5)
        var lastMode = ""
        var lastResult = ""
        var lastError = ""
        while Date() < deadline {
            runtime.pollEvents(milliseconds: 50)
            pumpApp(app, for: 0.02)
            do {
                let result = try runtime.executeJavaScript(session, script: script)
                lastResult = result
                let mode = try result.jsonObjectStringValue(for: "mode")
                lastMode = mode
                if mode == expectedMode {
                    return
                }
            } catch {
                lastError = String(describing: error)
            }
        }
        throw VerifierError.input(
            "expected resize mode \(expectedMode), got \(lastMode); lastResult=\(lastResult); lastError=\(lastError); logs=\(events.snapshot().logs)"
        )
    }

    private func sendKeyStroke(
        _ stroke: OwlFreshKeyEvent,
        runtime: OwlFreshMojoRuntime,
        hostController: OwlFreshMojoHostController
    ) throws {
        try hostController.sendKey(stroke)
        runtime.pollEvents(milliseconds: 10)
        try hostController.sendKey(OwlFreshKeyEvent(
            keyDown: false,
            keyCode: stroke.keyCode,
            text: "",
            modifiers: stroke.modifiers
        ))
        runtime.pollEvents(milliseconds: 10)
    }

    private func verifyPostInputStateIfNeeded(
        target: RenderTarget,
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer
    ) throws {
        guard !target.postInputExpectations.isEmpty else {
            return
        }
        guard let script = target.postInputDiagnosticScript else {
            throw VerifierError.input("\(target.name) has post-input expectations but no diagnostic script")
        }
        let result = try runtime.executeJavaScript(session, script: script)
        try verifyJavaScriptExpectations(
            result: result,
            expectations: target.postInputExpectations,
            targetName: target.name
        )
    }

    private func writePostInputDiagnostics(
        target: RenderTarget,
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer
    ) {
        writePostInputDOMState(target: target, runtime: runtime, session: session)

        let diagnosticURL = options.outputDirectory.appendingPathComponent(
            "\(target.name)-mojo-after-input.png"
        )
        do {
            let diagnostic = try runtime.captureSurfacePNG(session, to: diagnosticURL)
            let infoURL = options.outputDirectory.appendingPathComponent(
                "\(target.name)-mojo-after-input.json"
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
                "\(target.name)-mojo-after-input-error.txt"
            )
            try? String(describing: error).write(to: errorURL, atomically: true, encoding: .utf8)
        }
    }

    private func writePostInputDOMState(
        target: RenderTarget,
        runtime: OwlFreshMojoRuntime,
        session: OpaquePointer
    ) {
        if let script = target.postInputDiagnosticScript {
            let stateURL = options.outputDirectory.appendingPathComponent(
                "\(target.name)-mojo-dom-state.json"
            )
            do {
                let domState = try runtime.executeJavaScript(session, script: script)
                try domState.write(to: stateURL, atomically: true, encoding: .utf8)
            } catch {
                try? String(describing: error).write(
                    to: stateURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
    }
}

private extension OwlFreshKeyEvent {
    static func typing(_ character: Character) -> OwlFreshKeyEvent? {
        let scalars = String(character).unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else {
            return nil
        }
        switch scalar.value {
        case 32:
            return OwlFreshKeyEvent(keyDown: true, keyCode: 32, text: " ", modifiers: 0)
        case 48...57, 65...90:
            return OwlFreshKeyEvent(keyDown: true, keyCode: scalar.value, text: String(character), modifiers: 0)
        case 97...122:
            return OwlFreshKeyEvent(keyDown: true, keyCode: scalar.value - 32, text: String(character), modifiers: 0)
        default:
            return OwlFreshKeyEvent(keyDown: true, keyCode: scalar.value, text: String(character), modifiers: 0)
        }
    }
}

private func verifyJavaScriptExpectations(
    result: String,
    expectations: [JavaScriptExpectation],
    targetName: String
) throws {
    guard let data = result.data(using: .utf8) else {
        throw VerifierError.input("\(targetName) post-input JavaScript returned non-UTF8 data")
    }
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw VerifierError.input("\(targetName) post-input JavaScript returned invalid JSON: \(result)")
    }
    guard let dictionary = object as? [String: Any] else {
        throw VerifierError.input("\(targetName) post-input JavaScript did not return an object: \(result)")
    }

    for expectation in expectations {
        guard let actual = dictionary[expectation.key] else {
            throw VerifierError.input("\(targetName) missing post-input field \(expectation.key): \(result)")
        }
        switch expectation.value {
        case .string(let expected):
            guard let actualString = actual as? String, actualString == expected else {
                throw VerifierError.input("\(targetName) expected \(expectation.key)=\(expected), got \(actual)")
            }
        case .bool(let expected):
            guard let actualBool = actual as? Bool, actualBool == expected else {
                throw VerifierError.input("\(targetName) expected \(expectation.key)=\(expected), got \(actual)")
            }
        }
    }
}

private final class LayerHostWindow {
    let title: String
    private let window: NSWindow
    private let contentView: NSView
    private let rootLayer: CALayer
    private let hostLayer: CALayer
    private var popupHostLayers: [UInt64: CALayer] = [:]

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
        self.contentView = contentView
        self.rootLayer = rootLayer

        let hostLayer = try makeCALayerHost(contextID: contextID)
        hostLayer.anchorPoint = CGPoint.zero
        hostLayer.bounds = rootLayer.bounds
        hostLayer.position = CGPoint.zero
        hostLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostLayer.zPosition = 0
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

    func resize(to size: CGSize) {
        window.setContentSize(size)
        contentView.setFrameSize(size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.frame = CGRect(origin: .zero, size: size)
        rootLayer.bounds = CGRect(origin: .zero, size: size)
        hostLayer.bounds = rootLayer.bounds
        hostLayer.position = CGPoint.zero
        for layer in popupHostLayers.values {
            layer.setNeedsLayout()
        }
        CATransaction.commit()
        flushHostedLayer()
    }

    func update(contextID: UInt32) {
        hostLayer.setValue(NSNumber(value: contextID), forKey: "contextId")
        flushHostedLayer()
    }

    func update(surfaceTree: OwlFreshSurfaceTree) {
        let visibleSurfaces = surfaceTree.surfaces
            .filter(\.visible)
            .sorted { lhs, rhs in
                if lhs.zIndex != rhs.zIndex {
                    return lhs.zIndex < rhs.zIndex
                }
                return lhs.surfaceId < rhs.surfaceId
            }
        guard let primary = visibleSurfaces.first(where: { $0.kind == .webView && $0.contextId != 0 }) ??
            visibleSurfaces.first(where: { $0.contextId != 0 }) else {
            flushHostedLayer()
            return
        }

        let origin = CGPoint(x: CGFloat(primary.x), y: CGFloat(primary.y))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer.isHidden = false
        hostLayer.setValue(NSNumber(value: primary.contextId), forKey: "contextId")
        hostLayer.frame = CGRect(origin: .zero, size: rootLayer.bounds.size)
        hostLayer.bounds = rootLayer.bounds
        hostLayer.position = CGPoint.zero
        hostLayer.zPosition = CGFloat(primary.zIndex)

        let renderPopupSurfaces = visibleSurfaces.filter { surface in
            surface.contextId != 0 && surface.surfaceId != primary.surfaceId
        }
        let activePopupIDs = Set(renderPopupSurfaces.map(\.surfaceId))
        for staleID in popupHostLayers.keys where !activePopupIDs.contains(staleID) {
            popupHostLayers[staleID]?.removeFromSuperlayer()
            popupHostLayers[staleID] = nil
        }
        for surface in renderPopupSurfaces {
            let layer: CALayer
            if let existing = popupHostLayers[surface.surfaceId] {
                layer = existing
                layer.setValue(NSNumber(value: surface.contextId), forKey: "contextId")
            } else {
                do {
                    layer = try makeCALayerHost(contextID: surface.contextId)
                    layer.anchorPoint = CGPoint.zero
                    rootLayer.addSublayer(layer)
                    popupHostLayers[surface.surfaceId] = layer
                } catch {
                    continue
                }
            }
            layer.frame = frame(for: surface, origin: origin)
            layer.bounds = CGRect(origin: .zero, size: layer.frame.size)
            layer.position = layer.frame.origin
            layer.zPosition = CGFloat(surface.zIndex)
            layer.isHidden = false
        }
        CATransaction.commit()

        flushHostedLayer()
    }

    func presentNativeMenuAndCapture(
        surface: OwlFreshSurfaceInfo,
        windowID: UInt32,
        to url: URL
    ) throws -> CapturedWindow {
        guard !surface.menuItems.isEmpty else {
            throw VerifierError.input("native menu surface \(surface.label) has no menu items")
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        let runner = NativeMenuRunner(surface: surface)

        guard runner.menu.numberOfItems > 0 else {
            throw VerifierError.input("native menu surface \(surface.label) produced an empty NSMenu")
        }

        let surfaceFrame = frame(for: surface, origin: .zero)
        let controlFrame = NSRect(
            x: max(0, min(contentView.bounds.width, surfaceFrame.minX)),
            y: max(0, min(contentView.bounds.height, contentView.bounds.height - surfaceFrame.maxY)),
            width: surfaceFrame.width,
            height: surfaceFrame.height
        )
        let box = NativeMenuCaptureBox()
        let captureTimer = Timer(timeInterval: 0.2, repeats: false) { _ in
            box.result = Result {
                try captureScreenRegion(
                    aroundWindowID: windowID,
                    nativeSurfaceFrame: surfaceFrame,
                    to: url
                )
            }
            runner.cancel()
        }
        RunLoop.current.add(captureTimer, forMode: .eventTracking)
        runner.run(in: contentView, bounds: controlFrame)

        if let result = box.result {
            return try result.get()
        }

        return try captureScreenRegion(
            aroundWindowID: windowID,
            nativeSurfaceFrame: surfaceFrame,
            to: url
        )
    }

    private func frame(for surface: OwlFreshSurfaceInfo, origin: CGPoint) -> CGRect {
        CGRect(
            x: CGFloat(surface.x) - origin.x,
            y: CGFloat(surface.y) - origin.y,
            width: CGFloat(surface.width),
            height: CGFloat(surface.height)
        )
    }

    func flushHostedLayer() {
        hostLayer.setNeedsDisplay()
        hostLayer.displayIfNeeded()
        for layer in popupHostLayers.values {
            layer.setNeedsDisplay()
            layer.displayIfNeeded()
        }
        CATransaction.flush()
    }

}

private func validateNativeMenuSurface(_ surface: OwlFreshSurfaceInfo, targetName: String) throws {
    guard surface.width > 0, surface.height > 0 else {
        throw VerifierError.input("\(targetName) native menu surface has empty control bounds: \(surface)")
    }

    guard surface.label == "select-menu" else {
        return
    }

    guard !surface.nativeMenuItems.isEmpty else {
        throw VerifierError.input("\(targetName) select menu missing Chrome native menu item metadata: \(surface)")
    }
    guard surface.itemFontSize > 0 else {
        throw VerifierError.input("\(targetName) select menu missing Chrome item font size: \(surface)")
    }
    guard surface.height <= 80 else {
        throw VerifierError.input("\(targetName) select menu still looks like synthesized popup bounds: \(surface)")
    }
}

private func writeNativeMenuSurface(
    _ surface: OwlFreshSurfaceInfo,
    screenshotName: String,
    outputDirectory: URL
) throws {
    let baseName = screenshotName.hasSuffix(".png")
        ? String(screenshotName.dropLast(4))
        : screenshotName
    let url = outputDirectory.appendingPathComponent("\(baseName)-surface.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(surface).write(to: url)
}

private final class NativeMenuRunner: NSObject {
    let menu: NSMenu
    private let selectedIndex: Int32
    private let itemFontSize: CGFloat
    private let rightAligned: Bool
    private var selectedMenuItemIndex: Int?

    init(surface: OwlFreshSurfaceInfo) {
        menu = NSMenu(title: surface.label)
        menu.autoenablesItems = false
        selectedIndex = surface.selectedIndex
        itemFontSize = CGFloat(
            surface.itemFontSize > 0 ? surface.itemFontSize : Float(NSFont.systemFontSize)
        )
        rightAligned = surface.rightAligned
        super.init()

        let items = surface.nativeMenuItems.isEmpty
            ? surface.menuItems.map { label in
                OwlFreshNativeMenuItem(
                    label: label,
                    toolTip: "",
                    enabled: true,
                    separator: label == "---",
                    group: false,
                    textDirection: 2,
                    hasTextDirectionOverride: false
                )
            }
            : surface.nativeMenuItems
        for item in items {
            addItem(item)
        }
    }

    func run(in view: NSView, bounds: NSRect) {
        let cell = NSPopUpButtonCell(textCell: "", pullsDown: false)
        cell.menu = menu
        if selectedIndex > -1 {
            cell.selectItem(withTag: Int(selectedIndex))
        } else {
            cell.selectItem(at: -1)
        }

        if rightAligned {
            cell.userInterfaceLayoutDirection = .rightToLeft
            menu.userInterfaceLayoutDirection = .rightToLeft
        }

        let fakeControlView = NSView(frame: bounds)
        view.addSubview(fakeControlView)
        cell.attachPopUp(withFrame: fakeControlView.bounds, in: fakeControlView)
        cell.performClick(withFrame: fakeControlView.bounds, in: fakeControlView)
        fakeControlView.removeFromSuperview()
    }

    func cancel() {
        menu.cancelTrackingWithoutAnimation()
    }

    private func addItem(_ item: OwlFreshNativeMenuItem) {
        if item.separator {
            menu.addItem(.separator())
            return
        }

        let title = item.label.isEmpty ? " " : item.label
        let menuItem = menu.addItem(
            withTitle: title,
            action: #selector(menuItemSelected(_:)),
            keyEquivalent: ""
        )
        if !item.toolTip.isEmpty {
            menuItem.toolTip = item.toolTip
        }
        menuItem.isEnabled = item.enabled && !item.group
        menuItem.target = self

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = rightAligned ? .right : .left
        let writingDirection: NSWritingDirection = item.textDirection == 1
            ? .rightToLeft
            : .leftToRight
        paragraphStyle.baseWritingDirection = writingDirection
        paragraphStyle.lineBreakMode = .byTruncatingTail

        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.menuFont(ofSize: itemFontSize),
        ]
        if item.hasTextDirectionOverride {
            attributes[.writingDirection] = [
                NSNumber(value: writingDirection.rawValue | NSWritingDirectionFormatType.override.rawValue),
            ]
        }
        menuItem.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        menuItem.title = title.trimmingCharacters(in: .whitespaces)
        menuItem.tag = menu.numberOfItems - 1
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        selectedMenuItemIndex = sender.tag
    }
}

private final class NativeMenuCaptureBox {
    var result: Result<CapturedWindow, Error>?
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

private final class OwlFreshMojoRuntime {
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
    private typealias InvokeJSON = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
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
    private let sessionInvokeJSON: InvokeJSON
    private let eventPoll: PollEvents
    private let freeBuffer: FreeBuffer

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw VerifierError.bridge("dlopen failed for \(path): \(dlerrorString())")
        }
        self.handle = handle
        self.globalInit = try loadSymbol(handle, "owl_fresh_mojo_global_init", as: GlobalInit.self)
        self.sessionCreate = try loadSymbol(handle, "owl_fresh_mojo_session_create", as: SessionCreate.self)
        self.sessionDestroy = try loadSymbol(handle, "owl_fresh_mojo_session_destroy", as: SessionDestroy.self)
        self.sessionHostPID = try loadSymbol(handle, "owl_fresh_mojo_session_host_pid", as: HostPID.self)
        self.sessionInvokeJSON = try loadSymbol(handle, "owl_fresh_mojo_session_invoke_json", as: InvokeJSON.self)
        self.eventPoll = try loadSymbol(handle, "owl_fresh_mojo_poll_events", as: PollEvents.self)
        self.freeBuffer = try loadSymbol(handle, "owl_fresh_mojo_free_buffer", as: FreeBuffer.self)
    }

    deinit {
        dlclose(handle)
    }

    func initialize() throws {
        let status = globalInit()
        guard status == 0 else {
            throw VerifierError.bridge("owl_fresh_mojo_global_init failed with status \(status)")
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
            throw VerifierError.launch("owl_fresh_mojo_session_create returned null")
        }
        return session
    }

    func destroy(_ session: OpaquePointer?) {
        sessionDestroy(session)
    }

    func hostPID(_ session: OpaquePointer?) -> Int32 {
        sessionHostPID(session)
    }

    func pollEvents(milliseconds: UInt32) {
        eventPoll(milliseconds)
    }

    func invokeJSON(
        session: OpaquePointer?,
        interface: String,
        method: String,
        payload: String = "{}"
    ) throws -> String {
        var resultPointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = interface.withCString { interfacePointer in
            method.withCString { methodPointer in
                payload.withCString { payloadPointer in
                    sessionInvokeJSON(
                        session,
                        interfacePointer,
                        methodPointer,
                        payloadPointer,
                        &resultPointer,
                        &errorPointer
                    )
                }
            }
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
            let message = errorPointer.map { String(cString: $0) } ?? "unknown Mojo runtime error"
            throw VerifierError.bridge("\(interface).\(method) failed: \(message)")
        }
        return resultPointer.map { String(cString: $0) } ?? "{}"
    }

    func invokeVoid(
        session: OpaquePointer?,
        interface: String,
        method: String,
        payload: [String: Any]
    ) throws {
        _ = try invokeJSON(
            session: session,
            interface: interface,
            method: method,
            payload: try runtimePayloadJSON(payload)
        )
    }

    func captureSurfacePNG(_ session: OpaquePointer?, to url: URL) throws -> MojoSurfaceCapture {
        let result = try captureSurface(session)
        guard result.error.isEmpty else {
            throw VerifierError.capture("CaptureSurface failed: \(result.error)")
        }
        guard let data = Data(base64Encoded: result.pngBase64), !data.isEmpty else {
            throw VerifierError.capture("CaptureSurface returned invalid PNG base64")
        }
        try data.write(to: url)
        return MojoSurfaceCapture(path: url.path, mode: result.captureMode, width: result.width, height: result.height)
    }

    func executeJavaScript(_ session: OpaquePointer?, script: String) throws -> String {
        try invokeJSON(
            session: session,
            interface: "ShellController",
            method: "executeJavaScript",
            payload: runtimePayloadJSON(["script": script])
        )
    }

    func flushHost(_ session: OpaquePointer?) throws {
        let result = try invokeJSON(session: session, interface: "OwlFreshHost", method: "flush")
        guard try result.jsonObjectBoolValue(for: "ok") else {
            throw VerifierError.bridge("OwlFreshHost.flush returned false")
        }
    }

    func captureSurface(_ session: OpaquePointer?) throws -> RuntimeCaptureSurfaceResult {
        let json = try invokeJSON(session: session, interface: "OwlFreshHost", method: "captureSurface")
        let data = Data(json.utf8)
        return try JSONDecoder().decode(RuntimeCaptureSurfaceResult.self, from: data)
    }

    func getSurfaceTree(_ session: OpaquePointer?) throws -> OwlFreshSurfaceTree {
        let json = try invokeJSON(session: session, interface: "OwlFreshHost", method: "getSurfaceTree")
        let data = Data(json.utf8)
        return try JSONDecoder().decode(OwlFreshSurfaceTree.self, from: data)
    }

    func acceptActivePopupMenuItem(_ session: OpaquePointer?, index: UInt32) throws -> Bool {
        let result = try invokeJSON(
            session: session,
            interface: "OwlFreshHost",
            method: "acceptActivePopupMenuItem",
            payload: try runtimePayloadJSON(["index": Int(index)])
        )
        return try result.jsonObjectBoolValue(for: "ok")
    }

    func cancelActivePopup(_ session: OpaquePointer?) throws -> Bool {
        let result = try invokeJSON(
            session: session,
            interface: "OwlFreshHost",
            method: "cancelActivePopup"
        )
        return try result.jsonObjectBoolValue(for: "ok")
    }
}

private struct RuntimeCaptureSurfaceResult: Decodable {
    let pngBase64: String
    let width: UInt32
    let height: UInt32
    let captureMode: String
    let error: String
}

private final class OwlFreshMojoHostController {
    private let runtime: OwlFreshMojoRuntime
    private let session: OpaquePointer
    private let sink: OwlFreshMojoRuntimeHostSink
    private let transport: GeneratedOwlFreshHostMojoTransport

    init(runtime: OwlFreshMojoRuntime, session: OpaquePointer) {
        self.runtime = runtime
        self.session = session
        self.sink = OwlFreshMojoRuntimeHostSink(runtime: runtime, session: session)
        self.transport = GeneratedOwlFreshHostMojoTransport(sink: sink)
    }

    var recordedCalls: [OwlFreshMojoTransportCall] {
        transport.recordedCalls
    }

    func navigate(_ url: String) throws {
        transport.navigate(url)
        try sink.throwIfFailed()
    }

    func resize(_ request: OwlFreshHostResizeRequest) throws {
        transport.resize(request)
        try sink.throwIfFailed()
    }

    func setFocus(_ focused: Bool) throws {
        transport.setFocus(focused)
        try sink.throwIfFailed()
    }

    func sendMouse(_ event: OwlFreshMouseEvent) throws {
        transport.sendMouse(event)
        try sink.throwIfFailed()
    }

    func sendKey(_ event: OwlFreshKeyEvent) throws {
        transport.sendKey(event)
        try sink.throwIfFailed()
    }

    func flush() async throws -> Bool {
        let result = try await transport.flush()
        try sink.throwIfFailed()
        return result
    }

    func captureSurface() async throws -> OwlFreshCaptureResult {
        let result = try await transport.captureSurface()
        try sink.throwIfFailed()
        return result
    }

    func getSurfaceTree() throws -> OwlFreshSurfaceTree {
        try runtime.getSurfaceTree(session)
    }

    func acceptActivePopupMenuItem(_ index: UInt32) throws -> Bool {
        try runtime.acceptActivePopupMenuItem(session, index: index)
    }

    func cancelActivePopup() throws -> Bool {
        try runtime.cancelActivePopup(session)
    }
}

private final class OwlFreshMojoRuntimeHostSink: OwlFreshHostMojoSink {
    private let runtime: OwlFreshMojoRuntime
    private let session: OpaquePointer
    private var lastError: VerifierError?

    init(runtime: OwlFreshMojoRuntime, session: OpaquePointer) {
        self.runtime = runtime
        self.session = session
    }

    func throwIfFailed() throws {
        if let error = lastError {
            lastError = nil
            throw error
        }
    }

    func setClient(_ client: OwlFreshClientRemote) {
        lastError = VerifierError.bridge("Swift cannot synthesize pending_remote handles yet")
    }

    func navigate(_ url: String) {
        invoke(method: "navigate", payload: ["url": url])
    }

    func resize(_ request: OwlFreshHostResizeRequest) {
        invoke(method: "resize", payload: [
            "width": Int(request.width),
            "height": Int(request.height),
            "scale": Double(request.scale),
        ])
    }

    func setFocus(_ focused: Bool) {
        invoke(method: "setFocus", payload: ["focused": focused])
    }

    func sendMouse(_ event: OwlFreshMouseEvent) {
        invoke(method: "sendMouse", payload: [
            "kind": Int(event.kind.rawValue),
            "x": Double(event.x),
            "y": Double(event.y),
            "button": Int(event.button),
            "clickCount": Int(event.clickCount),
            "deltaX": Double(event.deltaX),
            "deltaY": Double(event.deltaY),
            "modifiers": Int(event.modifiers),
        ])
    }

    func sendKey(_ event: OwlFreshKeyEvent) {
        invoke(method: "sendKey", payload: [
            "keyDown": event.keyDown,
            "keyCode": Int(event.keyCode),
            "text": event.text,
            "modifiers": Int(event.modifiers),
        ])
    }

    func flush() async throws -> Bool {
        try runtime.flushHost(session)
        return true
    }

    func captureSurface() async throws -> OwlFreshCaptureResult {
        let result = try runtime.captureSurface(session)
        guard result.error.isEmpty else {
            throw VerifierError.capture("CaptureSurface failed: \(result.error)")
        }
        let data = Data(base64Encoded: result.pngBase64) ?? Data()
        return OwlFreshCaptureResult(
            png: Array(data),
            width: result.width,
            height: result.height,
            captureMode: result.captureMode,
            error: result.error
        )
    }

    func getSurfaceTree() async throws -> OwlFreshSurfaceTree {
        try runtime.getSurfaceTree(session)
    }

    func acceptActivePopupMenuItem(_ index: UInt32) async throws -> Bool {
        try runtime.acceptActivePopupMenuItem(session, index: index)
    }

    func cancelActivePopup() async throws -> Bool {
        try runtime.cancelActivePopup(session)
    }

    private func invoke(method: String, payload: [String: Any]) {
        do {
            try runtime.invokeVoid(session: session, interface: "OwlFreshHost", method: method, payload: payload)
        } catch let error as VerifierError {
            lastError = error
        } catch {
            lastError = VerifierError.bridge(String(describing: error))
        }
    }
}

private func runtimePayloadJSON(_ payload: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    guard let json = String(data: data, encoding: .utf8) else {
        throw VerifierError.bridge("failed to encode runtime JSON payload")
    }
    return json
}

private extension String {
    func jsonObjectStringValue(for key: String) throws -> String {
        let data = Data(utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String else {
            throw VerifierError.bridge("expected JSON object string field \(key), got \(self)")
        }
        return value
    }

    func jsonObjectBoolValue(for key: String) throws -> Bool {
        let data = Data(utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? Bool else {
            throw VerifierError.bridge("expected JSON object bool field \(key), got \(self)")
        }
        return value
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
    }

    return nil
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
        let capture = try captureWindowWithScreencapture(windowID: windowID, to: url)
        if isMostlyBlack(capture.image),
           let fallback = try? captureWindowWithCoreGraphics(windowID: windowID, to: url),
           !isMostlyBlack(fallback.image) {
            return fallback
        }
        return capture
    } catch {
        return try captureWindowWithCoreGraphics(windowID: windowID, to: url)
    }
}

private func captureWindowWithCoreGraphics(windowID: UInt32, to url: URL) throws -> CapturedWindow {
    guard let image = CGWindowListCreateImage(
        .null,
        [.optionIncludingWindow],
        CGWindowID(windowID),
        [.bestResolution, .boundsIgnoreFraming]
    ) else {
        throw VerifierError.capture("CGWindowListCreateImage returned nil for windowID=\(windowID)")
    }
    try pngData(from: image).write(to: url)
    return CapturedWindow(image: image)
}

private func captureScreenRegion(
    aroundWindowID windowID: UInt32,
    nativeSurfaceFrame: CGRect,
    to url: URL
) throws -> CapturedWindow {
    guard let windowBounds = screenBounds(windowID: windowID) else {
        throw VerifierError.capture("could not resolve screen bounds for windowID=\(windowID)")
    }
    let captureBounds = nativeMenuCaptureBounds(
        hostWindowID: windowID,
        hostWindowBounds: windowBounds,
        nativeSurfaceFrame: nativeSurfaceFrame
    )
    guard let image = CGWindowListCreateImage(
        captureBounds,
        [.optionOnScreenOnly],
        kCGNullWindowID,
        [.bestResolution]
    ) else {
        throw VerifierError.capture("CGWindowListCreateImage returned nil for screen bounds \(captureBounds)")
    }
    try pngData(from: image).write(to: url)
    return CapturedWindow(image: image)
}

private func nativeMenuCaptureBounds(
    hostWindowID: UInt32,
    hostWindowBounds: CGRect,
    nativeSurfaceFrame: CGRect
) -> CGRect {
    let menuBounds = currentProcessWindowBounds(excluding: hostWindowID)
        .filter { bounds in
            bounds.width >= 24 && bounds.height >= 24 &&
                bounds.width <= 1_200 && bounds.height <= 1_200
        }
    if !menuBounds.isEmpty {
        return menuBounds
            .reduce(hostWindowBounds) { $0.union($1) }
            .insetBy(dx: -18, dy: -18)
            .integral
    }

    let xPadding = max(CGFloat(360), nativeSurfaceFrame.width + 96)
    let yPadding = max(CGFloat(260), nativeSurfaceFrame.height + 96)
    return hostWindowBounds
        .insetBy(dx: -xPadding, dy: -yPadding)
        .integral
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

private func screenBounds(windowID: UInt32) -> CGRect? {
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionIncludingWindow],
        CGWindowID(windowID)
    ) as? [[String: Any]] else {
        return nil
    }
    for window in windows where windowNumber(from: window) == windowID {
        return screenBounds(from: window)
    }
    return nil
}

private func currentProcessWindowBounds(excluding excludedWindowID: UInt32) -> [CGRect] {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    return windows.compactMap { window in
        guard (window[kCGWindowOwnerPID as String] as? Int32) == getpid(),
              windowNumber(from: window) != excludedWindowID,
              let bounds = screenBounds(from: window) else {
            return nil
        }
        return bounds
    }
}

private func screenBounds(from window: [String: Any]) -> CGRect? {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? NSNumber,
          let y = bounds["Y"] as? NSNumber,
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber else {
        return nil
    }
    return CGRect(
        x: CGFloat(truncating: x),
        y: CGFloat(truncating: y),
        width: CGFloat(truncating: width),
        height: CGFloat(truncating: height)
    )
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

private func isMostlyBlack(_ image: CGImage) -> Bool {
    let stats = analyze(image: image)
    return stats.darkPixels > (stats.width * stats.height * 95 / 100)
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

private func terminateHostProcessIfNeeded(pid: Int32) {
    guard pid > 0, kill(pid, 0) == 0 else {
        return
    }

    _ = kill(pid, SIGTERM)
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        if kill(pid, 0) != 0 {
            return
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }

    if kill(pid, 0) == 0 {
        _ = kill(pid, SIGKILL)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func renderGeneratedTransportReport(summary: Summary) -> String {
    let rows = summary.captures.map { capture in
        """
              <tr>
                <td><code>\(escapeHTML(capture.name))</code></td>
                <td>\(capture.generatedTransportCallCount)</td>
                <td><code>\(escapeHTML(capture.generatedTransportTracePath))</code></td>
              </tr>
        """
    }.joined(separator: "\n")

    return """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL Generated Transport Report</title>
      <style>
        html, body { margin: 0; background: #f7f7f7; color: #141414; font: 16px -apple-system, BlinkMacSystemFont, sans-serif; }
        main { width: 1120px; margin: 0 auto; padding: 32px 0 48px; }
        h1 { margin: 0 0 12px; font-size: 34px; letter-spacing: 0; }
        .status { border: 4px solid #141414; padding: 18px 22px; background: rgb(0, 204, 82); font-weight: 900; font-size: 30px; }
        .grid { display: grid; grid-template-columns: 230px 1fr; gap: 8px 18px; margin: 18px 0 26px; }
        .label { font-weight: 800; }
        table { width: 100%; border-collapse: collapse; background: white; border: 4px solid #141414; }
        th, td { border: 2px solid #141414; padding: 10px 12px; text-align: left; vertical-align: top; }
        th { background: #0059ff; color: white; font-weight: 900; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 14px; }
      </style>
    </head>
    <body>
      <main>
        <h1>OWL Generated Transport Report</h1>
        <div class="status">PASS: Swift host requests used the generated Mojo transport surface.</div>
        <div class="grid">
          <div class="label">Control transport</div><div><code>\(escapeHTML(summary.controlTransport))</code></div>
          <div class="label">Swift host transport</div><div><code>\(escapeHTML(summary.swiftHostTransport))</code></div>
          <div class="label">Mojo runtime</div><div><code>\(escapeHTML(summary.mojoRuntime))</code></div>
          <div class="label">Binding checksum</div><div><code>\(escapeHTML(summary.mojoBindingSourceChecksum))</code></div>
          <div class="label">Binding declarations</div><div><code>\(summary.mojoBindingDeclarationCount)</code></div>
          <div class="label">DevTools active port</div><div><code>\(summary.devToolsActivePortFound)</code></div>
          <div class="label">Remote debugging args</div><div><code>\(summary.remoteDebuggingArgumentFound)</code></div>
        </div>
        <table>
          <thead>
            <tr><th>Capture</th><th>Generated transport calls</th><th>Trace artifact</th></tr>
          </thead>
          <tbody>
    \(rows)
          </tbody>
        </table>
      </main>
    </body>
    </html>
    """

}

private func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
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

    static let formFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost form fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        body { font: 30px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #banner {
          position: absolute;
          left: 48px;
          top: 40px;
          width: 864px;
          height: 58px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 700;
        }
        #nameInput {
          position: absolute;
          left: 48px;
          top: 116px;
          width: 380px;
          height: 64px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          border-radius: 0;
          font: 30px -apple-system, BlinkMacSystemFont, sans-serif;
          padding: 0 16px;
          color: rgb(20,20,20);
          background: white;
        }
        #typed {
          position: absolute;
          left: 456px;
          top: 127px;
          width: 420px;
          height: 48px;
          font-weight: 700;
        }
        #agreeLabel {
          position: absolute;
          left: 48px;
          top: 218px;
          height: 58px;
          display: flex;
          align-items: center;
          gap: 14px;
          font-weight: 700;
        }
        #agree {
          width: 32px;
          height: 32px;
        }
        #submit {
          position: absolute;
          left: 48px;
          top: 298px;
          width: 220px;
          height: 72px;
          border: 4px solid rgb(20,20,20);
          background: rgb(255, 210, 0);
          color: rgb(20,20,20);
          font: 30px -apple-system, BlinkMacSystemFont, sans-serif;
          font-weight: 800;
        }
        #status {
          position: absolute;
          left: 300px;
          top: 314px;
          width: 560px;
          height: 42px;
          font-weight: 800;
        }
        #result {
          position: absolute;
          left: 48px;
          top: 408px;
          width: 864px;
          height: 144px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 28px;
          font-size: 40px;
          font-weight: 900;
        }
        body.submitted #result {
          background: rgb(0, 204, 82);
        }
        body.submitted #nameInput,
        body.submitted #typed,
        body.submitted #agreeLabel,
        body.submitted #submit {
          display: none;
        }
        body.submitted #status {
          left: 48px;
          top: 128px;
          width: 864px;
          height: 72px;
          display: flex;
          align-items: center;
          box-sizing: border-box;
          padding-left: 28px;
          background: rgb(255, 210, 0);
          font-size: 46px;
        }
        body.submitted #result {
          top: 220px;
          height: 250px;
        }
      </style>
    </head>
    <body class="ready">
      <div id="banner">HELLO_OWL_FORM_READY</div>
      <input id="nameInput" aria-label="Hello OWL input" autocomplete="off" spellcheck="false" autofocus>
      <div id="typed">typed: EMPTY</div>
      <label id="agreeLabel"><input id="agree" type="checkbox">check path active</label>
      <button id="submit" type="button">Submit</button>
      <div id="status">HELLO_OWL_WAITING</div>
      <div id="result">HELLO_OWL_NOT_SUBMITTED</div>
      <script>
        const input = document.getElementById("nameInput");
        const agree = document.getElementById("agree");
        const submit = document.getElementById("submit");
        const typed = document.getElementById("typed");
        const status = document.getElementById("status");
        const result = document.getElementById("result");

        const updateTyped = () => {
          typed.textContent = "typed: " + (input.value || "EMPTY");
        };
        const submitForm = () => {
          if (input.value === "hello owl" && agree.checked) {
            input.blur();
            submit.blur();
            document.body.classList.add("submitted");
            status.textContent = "HELLO_OWL_SUBMITTED";
            result.textContent = "HELLO_OWL_SUBMITTED: " + input.value;
          } else {
            status.textContent = "HELLO_OWL_INCOMPLETE";
          }
        };

        input.addEventListener("input", updateTyped);
        submit.addEventListener("click", submitForm);
        input.focus();
        updateTyped();
      </script>
    </body>
    </html>
    """

    static let modifierFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost modifier fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        body { font: 30px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #banner {
          position: absolute;
          left: 48px;
          top: 40px;
          width: 864px;
          height: 58px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 700;
        }
        #modInput {
          position: absolute;
          left: 48px;
          top: 116px;
          width: 380px;
          height: 64px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          border-radius: 0;
          font: 30px -apple-system, BlinkMacSystemFont, sans-serif;
          padding: 0 16px;
          color: rgb(20,20,20);
          background: white;
        }
        #typed {
          position: absolute;
          left: 456px;
          top: 127px;
          width: 420px;
          height: 48px;
          font-weight: 700;
        }
        #modifiers {
          position: absolute;
          left: 48px;
          top: 218px;
          width: 864px;
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 12px;
        }
        .chip {
          height: 70px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          justify-content: center;
          font-weight: 900;
        }
        .chip.ok {
          background: rgb(255, 210, 0);
        }
        #status {
          position: absolute;
          left: 48px;
          top: 340px;
          width: 864px;
          height: 72px;
          display: flex;
          align-items: center;
          box-sizing: border-box;
          padding-left: 28px;
          background: rgb(238,238,238);
          border: 4px solid rgb(20,20,20);
          font-size: 42px;
          font-weight: 900;
        }
        body.done #status {
          background: rgb(0, 204, 82);
        }
        #result {
          position: absolute;
          left: 48px;
          top: 452px;
          width: 864px;
          height: 96px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          background: white;
          display: flex;
          align-items: center;
          padding-left: 28px;
          font-size: 38px;
          font-weight: 900;
        }
      </style>
    </head>
    <body class="ready">
      <div id="banner">OWL_MODIFIER_FORM_READY</div>
      <input id="modInput" aria-label="OWL modifier input" autocomplete="off" spellcheck="false" autofocus>
      <div id="typed">typed: EMPTY</div>
      <div id="modifiers">
        <div id="cmd" class="chip">CMD</div>
        <div id="opt" class="chip">OPT</div>
        <div id="ctrl" class="chip">CTRL</div>
        <div id="shift" class="chip">SHIFT</div>
      </div>
      <div id="status">OWL_MODIFIERS_WAITING</div>
      <div id="result">value: EMPTY</div>
      <script>
        const input = document.getElementById("modInput");
        const typed = document.getElementById("typed");
        const status = document.getElementById("status");
        const result = document.getElementById("result");
        const state = {
          commandSeen: false,
          optionSeen: false,
          controlSeen: false,
          shiftSeen: false
        };
        window.owlModifierState = state;

        const setChip = (id, ok) => {
          document.getElementById(id).classList.toggle("ok", ok);
        };
        const render = () => {
          typed.textContent = "typed: " + (input.value || "EMPTY");
          result.textContent = "value: " + (input.value || "EMPTY");
          setChip("cmd", state.commandSeen);
          setChip("opt", state.optionSeen);
          setChip("ctrl", state.controlSeen);
          setChip("shift", state.shiftSeen);
          if (
            input.value === "plainS" &&
            state.commandSeen &&
            state.optionSeen &&
            state.controlSeen &&
            state.shiftSeen
          ) {
            input.blur();
            document.body.classList.add("done");
            status.textContent = "OWL_MODIFIERS_OK";
          }
        };

        input.addEventListener("input", render);
        document.addEventListener("keydown", (event) => {
          if (event.metaKey) {
            state.commandSeen = true;
          }
          if (event.altKey) {
            state.optionSeen = true;
          }
          if (event.ctrlKey) {
            state.controlSeen = true;
          }
          if (event.shiftKey) {
            state.shiftSeen = true;
          }
          render();
        });
        input.focus();
        render();
      </script>
    </body>
    </html>
    """

    static let resizeFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost resize fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        body { font: 30px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #frame {
          position: absolute;
          left: 32px;
          top: 32px;
          right: 32px;
          bottom: 32px;
          border: 6px solid rgb(20,20,20);
          background: rgb(248,248,248);
          box-sizing: border-box;
        }
        #banner {
          position: absolute;
          left: 64px;
          top: 56px;
          right: 64px;
          height: 64px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 900;
        }
        #size {
          position: absolute;
          left: 64px;
          top: 150px;
          width: 390px;
          height: 82px;
          border: 4px solid rgb(20,20,20);
          background: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-size: 40px;
          font-weight: 900;
        }
        #status {
          position: absolute;
          left: 64px;
          top: 260px;
          right: 64px;
          height: 94px;
          border: 4px solid rgb(20,20,20);
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-size: 44px;
          font-weight: 900;
        }
        #marker {
          position: absolute;
          left: 64px;
          right: 64px;
          bottom: 58px;
          height: 92px;
          border: 4px solid rgb(20,20,20);
          background: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 900;
        }
        body.small #banner,
        body.restored #banner,
        body.small #status,
        body.restored #status {
          background: rgb(0, 204, 82);
        }
        body.small #size,
        body.restored #marker {
          background: rgb(255, 210, 0);
        }
        body.restored #size,
        body.small #marker {
          background: rgb(255, 210, 0);
        }
      </style>
    </head>
    <body>
      <div id="frame"></div>
      <div id="banner">OWL_RESIZE_READY</div>
      <div id="size">0 x 0</div>
      <div id="status">OWL_RESIZE_WAITING</div>
      <div id="marker">edge marker tracks viewport</div>
      <script>
        const size = document.getElementById("size");
        const status = document.getElementById("status");
        const banner = document.getElementById("banner");
        const marker = document.getElementById("marker");
        const state = {
          sawSmall: false
        };

        const update = () => {
          const width = window.innerWidth;
          const height = window.innerHeight;
          let mode = "initial";
          let label = "OWL_RESIZE_READY";
          if (width <= 760 && height <= 540) {
            mode = "small";
            label = "OWL_RESIZE_SMALL_OK";
            state.sawSmall = true;
          } else if (state.sawSmall && width >= 900 && height >= 600) {
            mode = "restored";
            label = "OWL_RESIZE_ROUNDTRIP_OK";
          }
          document.body.className = mode;
          size.textContent = `${width} x ${height}`;
          status.textContent = label;
          banner.textContent = label;
          marker.textContent = `mode: ${mode}`;
          window.owlResizeState = { width, height, mode, status: label, sawSmall: state.sawSmall };
        };

        let lastWidth = 0;
        let lastHeight = 0;
        const tick = () => {
          if (window.innerWidth !== lastWidth || window.innerHeight !== lastHeight) {
            lastWidth = window.innerWidth;
            lastHeight = window.innerHeight;
            update();
          }
          requestAnimationFrame(tick);
        };

        window.addEventListener("resize", update);
        update();
        setInterval(update, 50);
        requestAnimationFrame(tick);
      </script>
    </body>
    </html>
    """

    static let scrollFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost scroll fixture</title>
      <style>
        html, body { margin: 0; width: 100%; min-height: 2500px; background: rgb(248,248,248); }
        body { font: 30px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #header {
          position: sticky;
          left: 48px;
          top: 0;
          margin-left: 48px;
          margin-top: 0;
          width: 864px;
          height: 82px;
          border: 4px solid rgb(20,20,20);
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 24px;
          box-sizing: border-box;
          font-size: 42px;
          font-weight: 900;
          z-index: 3;
        }
        #status {
          position: sticky;
          left: 48px;
          top: 82px;
          margin-left: 48px;
          width: 864px;
          height: 84px;
          border: 4px solid rgb(20,20,20);
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 24px;
          box-sizing: border-box;
          font-size: 42px;
          font-weight: 900;
          z-index: 3;
        }
        #after {
          position: sticky;
          left: 48px;
          top: 166px;
          margin-left: 48px;
          width: 864px;
          height: 94px;
          border: 4px solid rgb(20,20,20);
          background: white;
          display: flex;
          align-items: center;
          padding-left: 24px;
          box-sizing: border-box;
          font-weight: 900;
          z-index: 3;
        }
        #lines {
          margin-left: 48px;
          margin-top: 170px;
          width: 864px;
        }
        .line {
          height: 144px;
          border: 4px solid rgb(20,20,20);
          background: white;
          box-sizing: border-box;
          display: flex;
          align-items: center;
          padding-left: 24px;
          margin-bottom: 16px;
          font-weight: 900;
        }
        .line:nth-child(even) {
          background: rgb(238,238,238);
        }
        .line.current {
          background: rgb(255, 210, 0);
        }
        body.scrolled #header,
        body.scrolled #status {
          background: rgb(0, 204, 82);
          color: rgb(20,20,20);
        }
        body.scrolled #after {
          background: rgb(255, 210, 0);
        }
      </style>
    </head>
    <body>
      <div id="header">OWL_SCROLL_LINE_READY</div>
      <div id="status">OWL_SCROLL_TOP</div>
      <div id="after">scroll delta not seen</div>
      <div id="lines"></div>
      <script>
        const header = document.getElementById("header");
        const status = document.getElementById("status");
        const after = document.getElementById("after");
        const lines = document.getElementById("lines");
        const lineCount = 14;
        for (let index = 1; index <= lineCount; index++) {
          const line = document.createElement("div");
          const label = `LINE_${String(index).padStart(2, "0")}`;
          line.id = label;
          line.className = "line";
          line.textContent = `${label} content row ${index}: distinct scroll payload`;
          lines.appendChild(line);
        }

        const update = () => {
          const y = Math.round(window.scrollY);
          const firstVisibleIndex = Math.max(1, Math.min(lineCount, Math.floor(y / 160) + 1));
          const firstVisibleLine = `LINE_${String(firstVisibleIndex).padStart(2, "0")}`;
          const ok = y >= 850 && firstVisibleLine === "LINE_06";
          for (const line of document.querySelectorAll(".line")) {
            line.classList.toggle("current", line.id === firstVisibleLine);
          }
          document.body.classList.toggle("scrolled", ok);
          header.textContent = ok ? "OWL_SCROLL_LINE_OK" : "OWL_SCROLL_LINE_READY";
          status.textContent = ok ? "OWL_SCROLL_LINE_OK" : "OWL_SCROLL_TOP";
          after.textContent = `scrollY: ${y} first visible: ${firstVisibleLine}`;
          window.owlScrollState = { y, firstVisibleLine, ok };
        };

        window.addEventListener("scroll", update);
        update();
      </script>
    </body>
    </html>
    """

    static let textEditingFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost text and selection fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        body { font: 26px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #banner {
          position: absolute;
          left: 48px;
          top: 32px;
          width: 864px;
          height: 54px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 800;
        }
        input {
          position: absolute;
          left: 48px;
          width: 500px;
          height: 58px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          border-radius: 0;
          font: 30px -apple-system, BlinkMacSystemFont, sans-serif;
          padding: 0 16px;
          color: rgb(20,20,20);
          background: white;
        }
        #editInput { top: 122px; }
        #selectionInput { top: 342px; }
        .value {
          position: absolute;
          left: 576px;
          width: 336px;
          height: 42px;
          font-weight: 900;
        }
        #value { top: 132px; }
        #range { top: 352px; }
        .steps {
          position: absolute;
          left: 48px;
          width: 864px;
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 12px;
        }
        #editSteps { top: 198px; }
        #selectionSteps { top: 418px; }
        .step {
          height: 62px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          justify-content: center;
          font-weight: 900;
        }
        .step.ok {
          background: rgb(255, 210, 0);
        }
        .sectionLabel {
          position: absolute;
          left: 48px;
          width: 864px;
          height: 24px;
          font-size: 22px;
          font-weight: 900;
        }
        #editLabel { top: 94px; }
        #selectionLabel { top: 310px; }
        #status {
          position: absolute;
          left: 48px;
          top: 488px;
          width: 864px;
          height: 62px;
          border: 4px solid rgb(20,20,20);
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 24px;
          box-sizing: border-box;
          font-size: 36px;
          font-weight: 900;
        }
        #result {
          position: absolute;
          left: 48px;
          top: 560px;
          width: 864px;
          height: 44px;
          border: 4px solid rgb(20,20,20);
          background: white;
          display: flex;
          align-items: center;
          padding-left: 24px;
          box-sizing: border-box;
          font-size: 26px;
          font-weight: 900;
        }
        body.done #status,
        body.done #result {
          background: rgb(0, 204, 82);
        }
      </style>
    </head>
    <body class="ready">
      <div id="banner">OWL_TEXT_SELECTION_READY</div>
      <div id="editLabel" class="sectionLabel">caret editing</div>
      <input id="editInput" aria-label="OWL text editing input" autocomplete="off" spellcheck="false" autofocus>
      <div id="value" class="value">edit: EMPTY</div>
      <div id="editSteps" class="steps">
        <div id="step-type" class="step">TYPE</div>
        <div id="step-edit" class="step">EDIT</div>
        <div id="step-insert" class="step">INSERT</div>
      </div>
      <div id="selectionLabel" class="sectionLabel">selection replacement</div>
      <input id="selectionInput" aria-label="OWL selection input" autocomplete="off" spellcheck="false">
      <div id="range" class="value">range: 0-0</div>
      <div id="selectionSteps" class="steps">
        <div id="step-selection-type" class="step">TYPE</div>
        <div id="step-selection-range" class="step">RANGE</div>
        <div id="step-selection-replace" class="step">REPLACE</div>
      </div>
      <div id="status">OWL_TEXT_SELECTION_WAITING</div>
      <div id="result">values pending</div>
      <script>
        const editInput = document.getElementById("editInput");
        const selectionInput = document.getElementById("selectionInput");
        const value = document.getElementById("value");
        const range = document.getElementById("range");
        const status = document.getElementById("status");
        const result = document.getElementById("result");
        const state = {
          sawTyped: false,
          sawIntermediate: false,
          sawFinal: false,
          sawSelectionTyped: false,
          sawSelection: false,
          sawSelectionReplacement: false
        };
        window.owlTextEditState = state;

        const mark = (id, ok) => {
          document.getElementById(id).classList.toggle("ok", ok);
        };
        const render = () => {
          if (editInput.value === "abcdef") {
            state.sawTyped = true;
          }
          if (editInput.value === "abcZf") {
            state.sawIntermediate = true;
          }
          if (state.sawIntermediate && editInput.value === "abcZfinalf") {
            state.sawFinal = true;
          }

          const selectionStart = selectionInput.selectionStart ?? 0;
          const selectionEnd = selectionInput.selectionEnd ?? 0;
          if (selectionInput.value === "selection") {
            state.sawSelectionTyped = true;
          }
          if (selectionInput.value === "selection" && selectionStart === 6 && selectionEnd === 9) {
            state.sawSelection = true;
          }
          if (state.sawSelection && selectionInput.value === "selectXYZ") {
            state.sawSelectionReplacement = true;
          }

          value.textContent = "edit: " + (editInput.value || "EMPTY");
          range.textContent = `range: ${selectionStart}-${selectionEnd}`;
          result.textContent = `edit=${editInput.value || "EMPTY"} selection=${selectionInput.value || "EMPTY"}`;
          mark("step-type", state.sawTyped);
          mark("step-edit", state.sawIntermediate);
          mark("step-insert", state.sawFinal);
          mark("step-selection-type", state.sawSelectionTyped);
          mark("step-selection-range", state.sawSelection);
          mark("step-selection-replace", state.sawSelectionReplacement);
          if (state.sawFinal && state.sawSelectionReplacement) {
            document.body.classList.add("done");
            status.textContent = "OWL_TEXT_SELECTION_OK";
          }
        };

        editInput.addEventListener("input", render);
        selectionInput.addEventListener("input", render);
        selectionInput.addEventListener("keyup", render);
        selectionInput.addEventListener("select", render);
        document.addEventListener("selectionchange", render);
        editInput.focus();
        render();
      </script>
    </body>
    </html>
    """

    static let widgetFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost widget fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        body { font: 26px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #banner {
          position: absolute;
          left: 48px;
          top: 34px;
          width: 864px;
          height: 58px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 900;
        }
        label {
          position: absolute;
          left: 48px;
          font-weight: 900;
        }
        #selectLabel { top: 112px; }
        #contextLabel { top: 266px; }
        #colorLabel { top: 418px; }
        #nativeSelect {
          position: absolute;
          left: 48px;
          top: 142px;
          width: 360px;
          height: 112px;
          font: 28px -apple-system, BlinkMacSystemFont, sans-serif;
        }
        #selectState,
        #colorState {
          position: absolute;
          left: 360px;
          width: 520px;
          height: 58px;
          display: flex;
          align-items: center;
          font-weight: 900;
        }
        #selectState { top: 142px; }
        #colorState { top: 448px; }
        #contextZone {
          position: absolute;
          left: 48px;
          top: 296px;
          width: 864px;
          height: 88px;
          border: 4px solid rgb(20,20,20);
          box-sizing: border-box;
          background: white;
          display: flex;
          align-items: center;
          padding-left: 24px;
          font-weight: 900;
        }
        #colorInput {
          position: absolute;
          left: 48px;
          top: 448px;
          width: 250px;
          height: 58px;
        }
        #status {
          position: absolute;
          left: 48px;
          top: 540px;
          width: 864px;
          height: 70px;
          border: 4px solid rgb(20,20,20);
          box-sizing: border-box;
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 24px;
          font-size: 34px;
          font-weight: 900;
        }
        .ok {
          background: rgb(255, 210, 0) !important;
        }
        body.done #status {
          background: rgb(0, 204, 82);
        }
      </style>
    </head>
    <body>
      <div id="banner">OWL_WIDGETS_READY</div>
      <label id="selectLabel" for="nativeSelect">native select</label>
      <select id="nativeSelect" size="3">
        <option value="alpha">ALPHA_WIDGET_OPTION</option>
        <option value="beta">BETA_WIDGET_OPTION</option>
        <option value="gamma">GAMMA_WIDGET_OPTION</option>
      </select>
      <div id="selectState">select: alpha</div>
      <label id="contextLabel" for="contextZone">context menu target</label>
      <div id="contextZone">right click here</div>
      <label id="colorLabel" for="colorInput">color input</label>
      <input id="colorInput" type="color" value="#0059ff">
      <div id="colorState">color: not clicked</div>
      <div id="status">OWL_WIDGETS_WAITING</div>
      <script>
        const state = {
          ready: true,
          colorClicked: false,
          colorFocused: false,
          contextSeen: false
        };
        window.owlWidgetState = state;

        const select = document.getElementById("nativeSelect");
        const selectState = document.getElementById("selectState");
        const contextZone = document.getElementById("contextZone");
        const colorInput = document.getElementById("colorInput");
        const colorState = document.getElementById("colorState");
        const status = document.getElementById("status");

        const render = () => {
          selectState.textContent = "select: " + select.value;
          selectState.classList.toggle("ok", select.value === "beta");
          contextZone.textContent = state.contextSeen ? "OWL_CONTEXT_MENU_SEEN" : "right click here";
          contextZone.classList.toggle("ok", state.contextSeen);
          colorState.textContent = state.colorClicked ? "color input clicked and focused" : "color: not clicked";
          colorState.classList.toggle("ok", state.colorClicked && state.colorFocused);
          if (select.value === "beta" && state.contextSeen && state.colorClicked && state.colorFocused) {
            document.body.classList.add("done");
            status.textContent = "OWL_WIDGETS_OK";
          }
        };

        select.addEventListener("change", render);
        select.addEventListener("input", render);
        contextZone.addEventListener("contextmenu", (event) => {
          event.preventDefault();
          state.contextSeen = true;
          render();
        });
        colorInput.addEventListener("focus", () => {
          state.colorFocused = true;
          render();
        });
        colorInput.addEventListener("click", (event) => {
          event.preventDefault();
          state.colorClicked = true;
          state.colorFocused = true;
          colorInput.focus();
          render();
        });
        colorInput.addEventListener("input", render);
        render();
      </script>
    </body>
    </html>
    """

    static let nativePopupFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OWL LayerHost native popup fixture</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: rgb(248,248,248); }
        body { font: 26px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #banner {
          position: absolute;
          left: 48px;
          top: 34px;
          width: 864px;
          height: 58px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 900;
        }
        label {
          position: absolute;
          left: 48px;
          font-weight: 900;
        }
        #selectLabel { top: 112px; }
        #contextLabel { top: 266px; }
        #nativeSelect {
          position: absolute;
          left: 48px;
          top: 142px;
          width: 280px;
          height: 56px;
          box-sizing: border-box;
          border: 4px solid rgb(20,20,20);
          border-radius: 0;
          background: white;
          color: rgb(20,20,20);
          font: 24px -apple-system, BlinkMacSystemFont, sans-serif;
          font-weight: 900;
        }
        #selectState {
          position: absolute;
          left: 440px;
          top: 142px;
          width: 520px;
          height: 58px;
          display: flex;
          align-items: center;
          font-weight: 900;
        }
        #contextZone {
          position: absolute;
          left: 48px;
          top: 296px;
          width: 864px;
          height: 88px;
          border: 4px solid rgb(20,20,20);
          box-sizing: border-box;
          background: white;
          display: flex;
          align-items: center;
          padding-left: 24px;
          font-weight: 900;
        }
        #status {
          position: absolute;
          left: 48px;
          top: 540px;
          width: 864px;
          height: 70px;
          border: 4px solid rgb(20,20,20);
          box-sizing: border-box;
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 24px;
          font-size: 34px;
          font-weight: 900;
        }
        .ok {
          background: rgb(255, 210, 0) !important;
        }
        body.done #status {
          background: rgb(0, 204, 82);
        }
      </style>
    </head>
    <body>
      <div id="banner">OWL_NATIVE_POPUPS_READY</div>
      <label id="selectLabel" for="nativeSelect">collapsed select</label>
      <select id="nativeSelect">
        <option value="alpha">ALPHA_NATIVE_OPTION</option>
        <option value="beta">BETA_NATIVE_OPTION</option>
        <option value="gamma">GAMMA_NATIVE_OPTION</option>
      </select>
      <div id="selectState">select: alpha</div>
      <label id="contextLabel" for="contextZone">context menu target</label>
      <div id="contextZone">right click here</div>
      <div id="status">OWL_NATIVE_POPUPS_WAITING</div>
      <script>
        const state = {
          ready: true,
          contextSeen: false
        };
        window.owlNativePopupState = state;

        const select = document.getElementById("nativeSelect");
        const selectState = document.getElementById("selectState");
        const contextZone = document.getElementById("contextZone");
        const status = document.getElementById("status");

        const render = () => {
          selectState.textContent = "select: " + select.value;
          selectState.classList.toggle("ok", select.value === "beta");
          contextZone.textContent = state.contextSeen ? "OWL_CONTEXT_MENU_SEEN" : "right click here";
          contextZone.classList.toggle("ok", state.contextSeen);
          if (select.value === "beta" && state.contextSeen) {
            document.body.classList.add("done");
            status.textContent = "OWL_NATIVE_POPUPS_OK";
          }
        };

        select.addEventListener("change", render);
        select.addEventListener("input", render);
        contextZone.addEventListener("contextmenu", () => {
          state.contextSeen = true;
          render();
        });
        render();
      </script>
    </body>
    </html>
    """

    static let plainNativeSelectFixture = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Plain native select</title>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: white; }
        body { font: 26px -apple-system, BlinkMacSystemFont, sans-serif; color: rgb(20,20,20); }
        #banner {
          position: absolute;
          left: 48px;
          top: 34px;
          width: 864px;
          height: 58px;
          background: rgb(0, 89, 255);
          color: white;
          display: flex;
          align-items: center;
          padding-left: 22px;
          box-sizing: border-box;
          font-weight: 900;
        }
        #selectLabel {
          position: absolute;
          left: 48px;
          top: 112px;
          font-weight: 900;
        }
        #selectMount {
          position: absolute;
          left: 48px;
          top: 146px;
        }
        #selectState {
          position: absolute;
          left: 48px;
          top: 224px;
          width: 864px;
          height: 70px;
          border: 4px solid rgb(20,20,20);
          box-sizing: border-box;
          background: rgb(238,238,238);
          display: flex;
          align-items: center;
          padding-left: 24px;
          font-weight: 900;
        }
        body.done #selectState {
          background: rgb(0, 204, 82);
        }
      </style>
    </head>
    <body>
      <div id="banner">PLAIN_NATIVE_SELECT_READY</div>
      <label id="selectLabel" for="plainSelect">browser default select, no select CSS</label>
      <div id="selectMount">
        <select id="plainSelect">
          <option value="alpha">Alpha native option</option>
          <option value="beta">Beta native option</option>
          <option value="gamma">Gamma native option</option>
        </select>
      </div>
      <div id="selectState">select: alpha</div>
        <script>
          window.owlPlainNativeSelectState = { ready: true, changed: false };
          const select = document.getElementById("plainSelect");
          const selectState = document.getElementById("selectState");
          const render = () => {
            selectState.textContent = "select: " + select.value;
            if (select.value === "beta") {
              window.owlPlainNativeSelectState.changed = true;
              document.body.classList.add("done");
            }
          };
          select.addEventListener("change", render);
          select.addEventListener("input", render);
          render();
        </script>
    </body>
    </html>
    """
}
