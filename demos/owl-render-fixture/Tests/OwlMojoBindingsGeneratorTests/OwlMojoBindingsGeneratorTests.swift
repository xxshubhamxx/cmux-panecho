import XCTest
import OwlMojoBindingsGenerated
@testable import OwlMojoBindingsGeneratorCore

final class OwlMojoBindingsGeneratorTests: XCTestCase {
    func testParserReadsEnumsStructsAndInterfaces() throws {
        let file = try MojoParser.parse(source: sampleMojo)

        XCTAssertEqual(file.module, "content.mojom")
        XCTAssertEqual(file.declarations.count, 3)

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

        guard case .interface(let host) = file.declarations[2] else {
            return XCTFail("expected interface")
        }
        XCTAssertEqual(host.methods.map(\.name), ["Resize", "SendMouse", "CaptureSurface"])
        XCTAssertEqual(host.methods[0].parameters.map(\.name), ["width", "height", "scale"])
        XCTAssertEqual(host.methods[2].responseParameters.map(\.name), ["result"])
    }

    func testGeneratorEmitsSwiftTypesAndSchemaChecksum() throws {
        let file = try MojoParser.parse(source: sampleMojo)
        let result = MojoSwiftGenerator.generate(file: file, source: sampleMojo)

        XCTAssertTrue(result.swift.contains("public enum OwlFreshMouseKind: UInt32"))
        XCTAssertTrue(result.swift.contains("case down = 0"))
        XCTAssertTrue(result.swift.contains("public struct OwlFreshMouseEvent"))
        XCTAssertTrue(result.swift.contains("public let deltaX: Float"))
        XCTAssertTrue(result.swift.contains("public struct OwlFreshHostResizeRequest"))
        XCTAssertTrue(result.swift.contains("func resize(_ request: OwlFreshHostResizeRequest)"))
        XCTAssertTrue(result.swift.contains("public final class GeneratedOwlFreshHostMojoTransport"))
        XCTAssertTrue(result.swift.contains("public private(set) var recordedCalls"))
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
        XCTAssertTrue(report.contains("protocol OwlFreshHostMojoInterface"))
    }

    func testGeneratedHostTransportRecordsAndForwardsCalls() async throws {
        let sink = FakeHostSink()
        let transport = GeneratedOwlFreshHostMojoTransport(sink: sink)

        transport.navigate("https://example.com/")
        transport.resize(OwlFreshHostResizeRequest(width: 960, height: 640, scale: 1.0))
        transport.sendMouse(OwlFreshMouseEvent(
            kind: .wheel,
            x: 520,
            y: 520,
            button: 0,
            clickCount: 0,
            deltaX: 0,
            deltaY: -900,
            modifiers: 0
        ))
        transport.sendKey(OwlFreshKeyEvent(keyDown: true, keyCode: 83, text: "S", modifiers: 1))
        let flushed = try await transport.flush()
        let tree = try await transport.getSurfaceTree()
        let accepted = try await transport.acceptActivePopupMenuItem(1)
        let canceled = try await transport.cancelActivePopup()

        XCTAssertTrue(flushed)
        XCTAssertEqual(tree.generation, 7)
        XCTAssertTrue(accepted)
        XCTAssertTrue(canceled)
        XCTAssertEqual(sink.calls, [
            "navigate",
            "resize",
            "sendMouse",
            "sendKey",
            "flush",
            "getSurfaceTree",
            "acceptActivePopupMenuItem",
            "cancelActivePopup",
        ])
        XCTAssertEqual(transport.recordedCalls.map(\.method), [
            "navigate",
            "resize",
            "sendMouse",
            "sendKey",
            "flush",
            "getSurfaceTree",
            "acceptActivePopupMenuItem",
            "cancelActivePopup",
        ])
        XCTAssertEqual(transport.recordedCalls.map(\.interface), Array(repeating: "OwlFreshHost", count: 8))
        XCTAssertEqual(transport.recordedCalls[1].payloadType, "OwlFreshHostResizeRequest")
        XCTAssertEqual(transport.recordedCalls[2].payloadType, "OwlFreshMouseEvent")
        XCTAssertTrue(transport.recordedCalls[3].payloadSummary.contains("keyCode: 83"))
        XCTAssertEqual(transport.recordedCalls[4].payloadType, "Void")
        XCTAssertEqual(transport.recordedCalls[5].payloadType, "Void")
        XCTAssertEqual(transport.recordedCalls[6].payloadType, "UInt32")
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
              "selectedIndex": -1,
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

    interface OwlFreshHost {
      Resize(uint32 width, uint32 height, float scale);
      SendMouse(OwlFreshMouseEvent event);
      CaptureSurface() => (OwlFreshMouseEvent result);
    };
    """
}

private final class FakeHostSink: OwlFreshHostMojoSink {
    var calls: [String] = []

    func setClient(_ client: OwlFreshClientRemote) {
        calls.append("setClient")
    }

    func navigate(_ url: String) {
        calls.append("navigate")
    }

    func resize(_ request: OwlFreshHostResizeRequest) {
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
