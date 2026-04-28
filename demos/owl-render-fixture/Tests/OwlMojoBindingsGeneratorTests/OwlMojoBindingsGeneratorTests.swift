import XCTest
import OwlMojoBindingsGenerated
@testable import OwlMojoBindingsGeneratorCore

final class OwlMojoBindingsGeneratorTests: XCTestCase {
    func testParserReadsEnumsStructsAndInterfaces() throws {
        let file = try MojoParser.parse(source: sampleMojo)

        XCTAssertEqual(file.module, "content.mojom")
        XCTAssertEqual(file.declarations.count, 5)

        guard case .enumeration(let mouseKind) = file.declarations[0] else {
            return XCTFail("expected enum")
        }
        XCTAssertEqual(mouseKind.name, "OwlFreshMouseKind")
        XCTAssertEqual(mouseKind.cases.map(\.name), ["kDown", "kWheel"])
        XCTAssertEqual(mouseKind.cases.map(\.rawValue), [0, 3])

        guard case .structure(let event) = file.declarations[1] else {
            return XCTFail("expected struct")
        }
        XCTAssertEqual(event.fields.map(\.name), ["kind", "delta_x"])
        XCTAssertEqual(event.fields.map { $0.type.swiftName }, ["OwlFreshMouseKind", "Float"])

        guard case .interface(let session) = file.declarations[2] else {
            return XCTFail("expected interface")
        }
        XCTAssertEqual(session.name, "OwlFreshSession")
        XCTAssertEqual(session.methods.map(\.name), ["BindWebView", "BindInput", "Flush"])
        XCTAssertEqual(session.methods[0].parameters.map(\.name), ["web_view"])
        XCTAssertEqual(session.methods[0].parameters.first?.type.mojoName, "pending_receiver<OwlFreshWebView>")
        XCTAssertEqual(session.methods[0].parameters.first?.type.swiftName, "OwlFreshWebViewReceiver")
        XCTAssertEqual(session.methods[2].responseParameters.map(\.name), ["ok"])

        guard case .interface(let webView) = file.declarations[3] else {
            return XCTFail("expected web view interface")
        }
        XCTAssertEqual(webView.methods.map(\.name), ["Navigate", "Resize"])
        XCTAssertEqual(webView.methods[1].parameters.map(\.name), ["width", "height", "scale"])
    }

    func testGeneratorEmitsSwiftTypesAndSchemaChecksum() throws {
        let file = try MojoParser.parse(source: sampleMojo)
        let result = MojoSwiftGenerator.generate(file: file, source: sampleMojo)

        XCTAssertTrue(result.swift.contains("public enum OwlFreshMouseKind: UInt32"))
        XCTAssertTrue(result.swift.contains("case down = 0"))
        XCTAssertTrue(result.swift.contains("public struct OwlFreshMouseEvent"))
        XCTAssertTrue(result.swift.contains("public let deltaX: Float"))
        XCTAssertTrue(result.swift.contains("public struct MojoPendingReceiver<Interface>"))
        XCTAssertTrue(result.swift.contains("public typealias OwlFreshWebViewReceiver"))
        XCTAssertTrue(result.swift.contains("public struct OwlFreshWebViewResizeRequest"))
        XCTAssertTrue(result.swift.contains("func resize(_ request: OwlFreshWebViewResizeRequest)"))
        XCTAssertTrue(result.swift.contains("public final class GeneratedOwlFreshSessionMojoTransport"))
        XCTAssertTrue(result.swift.contains("public final class GeneratedOwlFreshWebViewMojoTransport"))
        XCTAssertTrue(result.swift.contains("public final class OwlFreshMojoTransportRecorder"))
        XCTAssertTrue(result.swift.contains("public static let sourceChecksum = \"\(result.checksum)\""))
    }

    func testReportShowsPassStatusAndGeneratedDeclarations() throws {
        let file = try MojoParser.parse(source: sampleMojo)
        let result = MojoSwiftGenerator.generate(file: file, source: sampleMojo)
        let report = BindingsReportRenderer.render(
            file: file,
            result: result,
            status: .passed,
            mojomPath: "Mojo/OwlFresh.mojom",
            swiftPath: "Sources/OwlLayerHostVerifier/OwlFresh.generated.swift"
        )

        XCTAssertTrue(report.contains("PASS"))
        XCTAssertTrue(report.contains("OwlFreshMouseKind"))
        XCTAssertTrue(report.contains(result.checksum))
        XCTAssertTrue(report.contains("protocol OwlFreshSessionMojoInterface"))
        XCTAssertTrue(report.contains("pending_receiver&lt;OwlFreshWebView&gt; web_view -&gt; OwlFreshWebViewReceiver webView"))
    }

    func testGeneratedTransportsShareRecorderAndForwardCalls() async throws {
        let sink = FakeOwlFreshSink()
        let recorder = OwlFreshMojoTransportRecorder()
        let session = GeneratedOwlFreshSessionMojoTransport(sink: sink, recorder: recorder)
        let webView = GeneratedOwlFreshWebViewMojoTransport(sink: sink, recorder: recorder)
        let input = GeneratedOwlFreshInputMojoTransport(sink: sink, recorder: recorder)
        let surfaceTree = GeneratedOwlFreshSurfaceTreeHostMojoTransport(sink: sink, recorder: recorder)
        let nativeSurface = GeneratedOwlFreshNativeSurfaceHostMojoTransport(sink: sink, recorder: recorder)

        session.bindWebView(OwlFreshWebViewReceiver(handle: 10))
        webView.navigate("https://example.com/")
        webView.resize(OwlFreshWebViewResizeRequest(width: 960, height: 640, scale: 1.0))
        input.sendMouse(OwlFreshMouseEvent(
            kind: .wheel,
            x: 520,
            y: 520,
            button: 0,
            clickCount: 0,
            deltaX: 0,
            deltaY: -900,
            modifiers: 0
        ))
        input.sendKey(OwlFreshKeyEvent(keyDown: true, keyCode: 83, text: "S", modifiers: 1))
        let flushed = try await session.flush()
        let tree = try await surfaceTree.getSurfaceTree()
        let accepted = try await nativeSurface.acceptActivePopupMenuItem(1)
        let canceled = try await nativeSurface.cancelActivePopup()

        XCTAssertTrue(flushed)
        XCTAssertEqual(tree.generation, 7)
        XCTAssertTrue(accepted)
        XCTAssertTrue(canceled)
        XCTAssertEqual(sink.calls, [
            "bindWebView",
            "navigate",
            "resize",
            "sendMouse",
            "sendKey",
            "flush",
            "getSurfaceTree",
            "acceptActivePopupMenuItem",
            "cancelActivePopup",
        ])
        XCTAssertEqual(session.recordedCalls.map(\.method), [
            "bindWebView",
            "navigate",
            "resize",
            "sendMouse",
            "sendKey",
            "flush",
            "getSurfaceTree",
            "acceptActivePopupMenuItem",
            "cancelActivePopup",
        ])
        XCTAssertEqual(session.recordedCalls.map(\.interface), [
            "OwlFreshSession",
            "OwlFreshWebView",
            "OwlFreshWebView",
            "OwlFreshInput",
            "OwlFreshInput",
            "OwlFreshSession",
            "OwlFreshSurfaceTreeHost",
            "OwlFreshNativeSurfaceHost",
            "OwlFreshNativeSurfaceHost",
        ])
        XCTAssertEqual(webView.recordedCalls, session.recordedCalls)
        XCTAssertEqual(session.recordedCalls[0].payloadType, "OwlFreshWebViewReceiver")
        XCTAssertEqual(session.recordedCalls[2].payloadType, "OwlFreshWebViewResizeRequest")
        XCTAssertEqual(session.recordedCalls[3].payloadType, "OwlFreshMouseEvent")
        XCTAssertTrue(session.recordedCalls[4].payloadSummary.contains("keyCode: 83"))
        XCTAssertEqual(session.recordedCalls[5].payloadType, "Void")
        XCTAssertEqual(session.recordedCalls[6].payloadType, "Void")
        XCTAssertEqual(session.recordedCalls[7].payloadType, "UInt32")
    }

    func testGeneratedSurfaceTreeDecodesWrappedUnsignedContextID() throws {
        let json = """
        {
          "generation": 1,
          "surfaces": [
            {
              "surfaceId": 2,
              "parentSurfaceId": 0,
              "kind": 0,
              "contextId": -603416498,
              "x": 0,
              "y": 0,
              "width": 960,
              "height": 640,
              "scale": 1,
              "zIndex": 0,
              "visible": true,
              "menuItems": [],
              "nativeMenuItems": [],
              "selectedIndex": -1,
              "itemFontSize": 0,
              "rightAligned": false,
              "label": "web-view"
            }
          ]
        }
        """.data(using: .utf8)!

        let tree = try JSONDecoder().decode(OwlFreshSurfaceTree.self, from: json)

        XCTAssertEqual(tree.surfaces.first?.contextId, UInt32(bitPattern: Int32(-603_416_498)))
        XCTAssertEqual(tree.surfaces.first?.contextId, 3_691_550_798)
    }

    private let sampleMojo = """
    module content.mojom;

    enum OwlFreshMouseKind {
      kDown = 0,
      kWheel = 3,
    };

    struct OwlFreshMouseEvent {
      OwlFreshMouseKind kind;
      float delta_x;
    };

    interface OwlFreshSession {
      BindWebView(pending_receiver<OwlFreshWebView> web_view);
      BindInput(pending_receiver<OwlFreshInput> input);
      Flush() => (bool ok);
    };

    interface OwlFreshWebView {
      Navigate(string url);
      Resize(uint32 width, uint32 height, float scale);
    };

    interface OwlFreshInput {
      SendMouse(OwlFreshMouseEvent event);
    };
    """
}

private final class FakeOwlFreshSink:
    OwlFreshSessionMojoSink,
    OwlFreshProfileMojoSink,
    OwlFreshWebViewMojoSink,
    OwlFreshInputMojoSink,
    OwlFreshSurfaceTreeHostMojoSink,
    OwlFreshNativeSurfaceHostMojoSink
{
    var calls: [String] = []

    func setClient(_ client: OwlFreshClientRemote) {
        calls.append("setClient")
    }

    func bindProfile(_ profile: OwlFreshProfileReceiver) {
        calls.append("bindProfile")
    }

    func bindWebView(_ webView: OwlFreshWebViewReceiver) {
        calls.append("bindWebView")
    }

    func bindInput(_ input: OwlFreshInputReceiver) {
        calls.append("bindInput")
    }

    func bindSurfaceTree(_ surfaceTree: OwlFreshSurfaceTreeHostReceiver) {
        calls.append("bindSurfaceTree")
    }

    func bindNativeSurfaceHost(_ nativeSurfaceHost: OwlFreshNativeSurfaceHostReceiver) {
        calls.append("bindNativeSurfaceHost")
    }

    func navigate(_ url: String) {
        calls.append("navigate")
    }

    func resize(_ request: OwlFreshWebViewResizeRequest) {
        calls.append("resize")
    }

    func setFocus(_ focused: Bool) {
        calls.append("setFocus")
    }

    func sendMouse(_ event: OwlFreshMouseEvent) {
        calls.append("sendMouse")
    }

    func sendKey(_ event: OwlFreshKeyEvent) {
        calls.append("sendKey")
    }

    func getPath() async throws -> String {
        calls.append("getPath")
        return "/tmp/owl-profile"
    }

    func flush() async throws -> Bool {
        calls.append("flush")
        return true
    }

    func captureSurface() async throws -> OwlFreshCaptureResult {
        calls.append("captureSurface")
        return OwlFreshCaptureResult(png: [], width: 0, height: 0, captureMode: "fake", error: "")
    }

    func getSurfaceTree() async throws -> OwlFreshSurfaceTree {
        calls.append("getSurfaceTree")
        return OwlFreshSurfaceTree(generation: 7, surfaces: [])
    }

    func acceptActivePopupMenuItem(_ index: UInt32) async throws -> Bool {
        calls.append("acceptActivePopupMenuItem")
        return index == 1
    }

    func cancelActivePopup() async throws -> Bool {
        calls.append("cancelActivePopup")
        return true
    }
}
