// Generated from Mojo/OwlFresh.mojom by OwlMojoBindingsGenerator.
// Do not edit by hand.
import Foundation

public struct MojoPendingRemote<Interface>: Equatable, Codable {
    public let handle: UInt64

    public init(handle: UInt64) {
        self.handle = handle
    }
}

public struct OwlFreshMojoTransportCall: Equatable, Codable {
    public let interface: String
    public let method: String
    public let payloadType: String
    public let payloadSummary: String

    public init(interface: String, method: String, payloadType: String, payloadSummary: String) {
        self.interface = interface
        self.method = method
        self.payloadType = payloadType
        self.payloadSummary = payloadSummary
    }
}

public enum OwlFreshGeneratedMojoTransport {
    public static let name = "GeneratedOwlFreshMojoTransport"
}

private enum MojoJSONCoding {
    static func decodeUInt8<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> UInt8 {
        if let value = try? container.decode(UInt8.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            if value >= 0, value <= Int64(UInt8.max) {
                return UInt8(value)
            }
            guard let signed = Int8(exactly: value) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "signed value cannot wrap to UInt8")
            }
            return UInt8(bitPattern: signed)
        }
        if let value = try? container.decode(String.self, forKey: key), let parsed = UInt8(value) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "expected UInt8-compatible value")
    }

    static func decodeUInt32<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> UInt32 {
        if let value = try? container.decode(UInt32.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            if value >= 0, value <= Int64(UInt32.max) {
                return UInt32(value)
            }
            guard let signed = Int32(exactly: value) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "signed value cannot wrap to UInt32")
            }
            return UInt32(bitPattern: signed)
        }
        if let value = try? container.decode(String.self, forKey: key), let parsed = UInt32(value) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "expected UInt32-compatible value")
    }

    static func decodeUInt64<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> UInt64 {
        if let value = try? container.decode(UInt64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            if value >= 0 {
                return UInt64(value)
            }
            return UInt64(bitPattern: value)
        }
        if let value = try? container.decode(String.self, forKey: key), let parsed = UInt64(value) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "expected UInt64-compatible value")
    }
}

public enum OwlFreshMouseKind: UInt32, Codable, CaseIterable {
    case down = 0
    case up = 1
    case move = 2
    case wheel = 3
}

public struct OwlFreshMouseEvent: Equatable, Codable {
    public let kind: OwlFreshMouseKind
    public let x: Float
    public let y: Float
    public let button: UInt32
    public let clickCount: UInt32
    public let deltaX: Float
    public let deltaY: Float
    public let modifiers: UInt32

    public init(kind: OwlFreshMouseKind, x: Float, y: Float, button: UInt32, clickCount: UInt32, deltaX: Float, deltaY: Float, modifiers: UInt32) {
        self.kind = kind
        self.x = x
        self.y = y
        self.button = button
        self.clickCount = clickCount
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.modifiers = modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(OwlFreshMouseKind.self, forKey: .kind)
        self.x = try container.decode(Float.self, forKey: .x)
        self.y = try container.decode(Float.self, forKey: .y)
        self.button = try MojoJSONCoding.decodeUInt32(from: container, forKey: .button)
        self.clickCount = try MojoJSONCoding.decodeUInt32(from: container, forKey: .clickCount)
        self.deltaX = try container.decode(Float.self, forKey: .deltaX)
        self.deltaY = try container.decode(Float.self, forKey: .deltaY)
        self.modifiers = try MojoJSONCoding.decodeUInt32(from: container, forKey: .modifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(button, forKey: .button)
        try container.encode(clickCount, forKey: .clickCount)
        try container.encode(deltaX, forKey: .deltaX)
        try container.encode(deltaY, forKey: .deltaY)
        try container.encode(modifiers, forKey: .modifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case x
        case y
        case button
        case clickCount
        case deltaX
        case deltaY
        case modifiers
    }
}

public struct OwlFreshKeyEvent: Equatable, Codable {
    public let keyDown: Bool
    public let keyCode: UInt32
    public let text: String
    public let modifiers: UInt32

    public init(keyDown: Bool, keyCode: UInt32, text: String, modifiers: UInt32) {
        self.keyDown = keyDown
        self.keyCode = keyCode
        self.text = text
        self.modifiers = modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyDown = try container.decode(Bool.self, forKey: .keyDown)
        self.keyCode = try MojoJSONCoding.decodeUInt32(from: container, forKey: .keyCode)
        self.text = try container.decode(String.self, forKey: .text)
        self.modifiers = try MojoJSONCoding.decodeUInt32(from: container, forKey: .modifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyDown, forKey: .keyDown)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(text, forKey: .text)
        try container.encode(modifiers, forKey: .modifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case keyDown
        case keyCode
        case text
        case modifiers
    }
}

public struct OwlFreshCompositorInfo: Equatable, Codable {
    public let contextId: UInt32

    public init(contextId: UInt32) {
        self.contextId = contextId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contextId = try MojoJSONCoding.decodeUInt32(from: container, forKey: .contextId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contextId, forKey: .contextId)
    }

    private enum CodingKeys: String, CodingKey {
        case contextId
    }
}

public enum OwlFreshSurfaceKind: UInt32, Codable, CaseIterable {
    case webView = 0
    case popupWidget = 1
    case nativeMenu = 2
}

public struct OwlFreshSurfaceInfo: Equatable, Codable {
    public let surfaceId: UInt64
    public let parentSurfaceId: UInt64
    public let kind: OwlFreshSurfaceKind
    public let contextId: UInt32
    public let x: Int32
    public let y: Int32
    public let width: UInt32
    public let height: UInt32
    public let scale: Float
    public let zIndex: Int32
    public let visible: Bool
    public let menuItems: [String]
    public let selectedIndex: Int32
    public let label: String

    public init(surfaceId: UInt64, parentSurfaceId: UInt64, kind: OwlFreshSurfaceKind, contextId: UInt32, x: Int32, y: Int32, width: UInt32, height: UInt32, scale: Float, zIndex: Int32, visible: Bool, menuItems: [String], selectedIndex: Int32, label: String) {
        self.surfaceId = surfaceId
        self.parentSurfaceId = parentSurfaceId
        self.kind = kind
        self.contextId = contextId
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.scale = scale
        self.zIndex = zIndex
        self.visible = visible
        self.menuItems = menuItems
        self.selectedIndex = selectedIndex
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.surfaceId = try MojoJSONCoding.decodeUInt64(from: container, forKey: .surfaceId)
        self.parentSurfaceId = try MojoJSONCoding.decodeUInt64(from: container, forKey: .parentSurfaceId)
        self.kind = try container.decode(OwlFreshSurfaceKind.self, forKey: .kind)
        self.contextId = try MojoJSONCoding.decodeUInt32(from: container, forKey: .contextId)
        self.x = try container.decode(Int32.self, forKey: .x)
        self.y = try container.decode(Int32.self, forKey: .y)
        self.width = try MojoJSONCoding.decodeUInt32(from: container, forKey: .width)
        self.height = try MojoJSONCoding.decodeUInt32(from: container, forKey: .height)
        self.scale = try container.decode(Float.self, forKey: .scale)
        self.zIndex = try container.decode(Int32.self, forKey: .zIndex)
        self.visible = try container.decode(Bool.self, forKey: .visible)
        self.menuItems = try container.decode([String].self, forKey: .menuItems)
        self.selectedIndex = try container.decode(Int32.self, forKey: .selectedIndex)
        self.label = try container.decode(String.self, forKey: .label)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surfaceId, forKey: .surfaceId)
        try container.encode(parentSurfaceId, forKey: .parentSurfaceId)
        try container.encode(kind, forKey: .kind)
        try container.encode(contextId, forKey: .contextId)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(scale, forKey: .scale)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(visible, forKey: .visible)
        try container.encode(menuItems, forKey: .menuItems)
        try container.encode(selectedIndex, forKey: .selectedIndex)
        try container.encode(label, forKey: .label)
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceId
        case parentSurfaceId
        case kind
        case contextId
        case x
        case y
        case width
        case height
        case scale
        case zIndex
        case visible
        case menuItems
        case selectedIndex
        case label
    }
}

public struct OwlFreshSurfaceTree: Equatable, Codable {
    public let generation: UInt64
    public let surfaces: [OwlFreshSurfaceInfo]

    public init(generation: UInt64, surfaces: [OwlFreshSurfaceInfo]) {
        self.generation = generation
        self.surfaces = surfaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generation = try MojoJSONCoding.decodeUInt64(from: container, forKey: .generation)
        self.surfaces = try container.decode([OwlFreshSurfaceInfo].self, forKey: .surfaces)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generation, forKey: .generation)
        try container.encode(surfaces, forKey: .surfaces)
    }

    private enum CodingKeys: String, CodingKey {
        case generation
        case surfaces
    }
}

public struct OwlFreshCaptureResult: Equatable, Codable {
    public let png: [UInt8]
    public let width: UInt32
    public let height: UInt32
    public let captureMode: String
    public let error: String

    public init(png: [UInt8], width: UInt32, height: UInt32, captureMode: String, error: String) {
        self.png = png
        self.width = width
        self.height = height
        self.captureMode = captureMode
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.png = try container.decode([UInt8].self, forKey: .png)
        self.width = try MojoJSONCoding.decodeUInt32(from: container, forKey: .width)
        self.height = try MojoJSONCoding.decodeUInt32(from: container, forKey: .height)
        self.captureMode = try container.decode(String.self, forKey: .captureMode)
        self.error = try container.decode(String.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(png, forKey: .png)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encode(error, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case png
        case width
        case height
        case captureMode
        case error
    }
}

public enum OwlFreshClientMojoInterfaceMarker {}
public typealias OwlFreshClientRemote = MojoPendingRemote<OwlFreshClientMojoInterfaceMarker>

public protocol OwlFreshClientMojoInterface {
    func onReady(_ request: OwlFreshClientOnReadyRequest)
    func onCompositorChanged(_ compositor: OwlFreshCompositorInfo)
    func onSurfaceTreeChanged(_ surfaceTree: OwlFreshSurfaceTree)
    func onNavigationChanged(_ request: OwlFreshClientOnNavigationChangedRequest)
    func onHostLog(_ message: String)
}

public struct OwlFreshClientOnReadyRequest: Equatable, Codable {
    public let hostPid: Int32
    public let compositor: OwlFreshCompositorInfo

    public init(hostPid: Int32, compositor: OwlFreshCompositorInfo) {
        self.hostPid = hostPid
        self.compositor = compositor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hostPid = try container.decode(Int32.self, forKey: .hostPid)
        self.compositor = try container.decode(OwlFreshCompositorInfo.self, forKey: .compositor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostPid, forKey: .hostPid)
        try container.encode(compositor, forKey: .compositor)
    }

    private enum CodingKeys: String, CodingKey {
        case hostPid
        case compositor
    }
}

public struct OwlFreshClientOnNavigationChangedRequest: Equatable, Codable {
    public let url: String
    public let title: String
    public let loading: Bool

    public init(url: String, title: String, loading: Bool) {
        self.url = url
        self.title = title
        self.loading = loading
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.title = try container.decode(String.self, forKey: .title)
        self.loading = try container.decode(Bool.self, forKey: .loading)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(loading, forKey: .loading)
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case loading
    }
}

public protocol OwlFreshClientMojoSink: AnyObject {
    func onReady(_ request: OwlFreshClientOnReadyRequest)
    func onCompositorChanged(_ compositor: OwlFreshCompositorInfo)
    func onSurfaceTreeChanged(_ surfaceTree: OwlFreshSurfaceTree)
    func onNavigationChanged(_ request: OwlFreshClientOnNavigationChangedRequest)
    func onHostLog(_ message: String)
}

public final class GeneratedOwlFreshClientMojoTransport: OwlFreshClientMojoInterface {
    public private(set) var recordedCalls: [OwlFreshMojoTransportCall] = []
    private let sink: OwlFreshClientMojoSink

    public init(sink: OwlFreshClientMojoSink) {
        self.sink = sink
    }

    public func resetRecordedCalls() {
        recordedCalls.removeAll()
    }

    private func record(method: String, payloadType: String, payloadSummary: String) {
        recordedCalls.append(OwlFreshMojoTransportCall(
            interface: "OwlFreshClient",
            method: method,
            payloadType: payloadType,
            payloadSummary: payloadSummary
        ))
    }

    public func onReady(_ request: OwlFreshClientOnReadyRequest) {
        record(method: "onReady", payloadType: "OwlFreshClientOnReadyRequest", payloadSummary: String(describing: request))
        sink.onReady(request)
    }

    public func onCompositorChanged(_ compositor: OwlFreshCompositorInfo) {
        record(method: "onCompositorChanged", payloadType: "OwlFreshCompositorInfo", payloadSummary: String(describing: compositor))
        sink.onCompositorChanged(compositor)
    }

    public func onSurfaceTreeChanged(_ surfaceTree: OwlFreshSurfaceTree) {
        record(method: "onSurfaceTreeChanged", payloadType: "OwlFreshSurfaceTree", payloadSummary: String(describing: surfaceTree))
        sink.onSurfaceTreeChanged(surfaceTree)
    }

    public func onNavigationChanged(_ request: OwlFreshClientOnNavigationChangedRequest) {
        record(method: "onNavigationChanged", payloadType: "OwlFreshClientOnNavigationChangedRequest", payloadSummary: String(describing: request))
        sink.onNavigationChanged(request)
    }

    public func onHostLog(_ message: String) {
        record(method: "onHostLog", payloadType: "String", payloadSummary: String(describing: message))
        sink.onHostLog(message)
    }
}

public enum OwlFreshHostMojoInterfaceMarker {}
public typealias OwlFreshHostRemote = MojoPendingRemote<OwlFreshHostMojoInterfaceMarker>

public protocol OwlFreshHostMojoInterface {
    func setClient(_ client: OwlFreshClientRemote)
    func navigate(_ url: String)
    func resize(_ request: OwlFreshHostResizeRequest)
    func setFocus(_ focused: Bool)
    func sendMouse(_ event: OwlFreshMouseEvent)
    func sendKey(_ event: OwlFreshKeyEvent)
    func flush() async throws -> Bool
    func captureSurface() async throws -> OwlFreshCaptureResult
    func getSurfaceTree() async throws -> OwlFreshSurfaceTree
    func acceptActivePopupMenuItem(_ index: UInt32) async throws -> Bool
    func cancelActivePopup() async throws -> Bool
}

public struct OwlFreshHostResizeRequest: Equatable, Codable {
    public let width: UInt32
    public let height: UInt32
    public let scale: Float

    public init(width: UInt32, height: UInt32, scale: Float) {
        self.width = width
        self.height = height
        self.scale = scale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.width = try MojoJSONCoding.decodeUInt32(from: container, forKey: .width)
        self.height = try MojoJSONCoding.decodeUInt32(from: container, forKey: .height)
        self.scale = try container.decode(Float.self, forKey: .scale)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(scale, forKey: .scale)
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case scale
    }
}

public protocol OwlFreshHostMojoSink: AnyObject {
    func setClient(_ client: OwlFreshClientRemote)
    func navigate(_ url: String)
    func resize(_ request: OwlFreshHostResizeRequest)
    func setFocus(_ focused: Bool)
    func sendMouse(_ event: OwlFreshMouseEvent)
    func sendKey(_ event: OwlFreshKeyEvent)
    func flush() async throws -> Bool
    func captureSurface() async throws -> OwlFreshCaptureResult
    func getSurfaceTree() async throws -> OwlFreshSurfaceTree
    func acceptActivePopupMenuItem(_ index: UInt32) async throws -> Bool
    func cancelActivePopup() async throws -> Bool
}

public final class GeneratedOwlFreshHostMojoTransport: OwlFreshHostMojoInterface {
    public private(set) var recordedCalls: [OwlFreshMojoTransportCall] = []
    private let sink: OwlFreshHostMojoSink

    public init(sink: OwlFreshHostMojoSink) {
        self.sink = sink
    }

    public func resetRecordedCalls() {
        recordedCalls.removeAll()
    }

    private func record(method: String, payloadType: String, payloadSummary: String) {
        recordedCalls.append(OwlFreshMojoTransportCall(
            interface: "OwlFreshHost",
            method: method,
            payloadType: payloadType,
            payloadSummary: payloadSummary
        ))
    }

    public func setClient(_ client: OwlFreshClientRemote) {
        record(method: "setClient", payloadType: "OwlFreshClientRemote", payloadSummary: String(describing: client))
        sink.setClient(client)
    }

    public func navigate(_ url: String) {
        record(method: "navigate", payloadType: "String", payloadSummary: String(describing: url))
        sink.navigate(url)
    }

    public func resize(_ request: OwlFreshHostResizeRequest) {
        record(method: "resize", payloadType: "OwlFreshHostResizeRequest", payloadSummary: String(describing: request))
        sink.resize(request)
    }

    public func setFocus(_ focused: Bool) {
        record(method: "setFocus", payloadType: "Bool", payloadSummary: String(describing: focused))
        sink.setFocus(focused)
    }

    public func sendMouse(_ event: OwlFreshMouseEvent) {
        record(method: "sendMouse", payloadType: "OwlFreshMouseEvent", payloadSummary: String(describing: event))
        sink.sendMouse(event)
    }

    public func sendKey(_ event: OwlFreshKeyEvent) {
        record(method: "sendKey", payloadType: "OwlFreshKeyEvent", payloadSummary: String(describing: event))
        sink.sendKey(event)
    }

    public func flush() async throws -> Bool {
        record(method: "flush", payloadType: "Void", payloadSummary: "")
        return try await sink.flush()
    }

    public func captureSurface() async throws -> OwlFreshCaptureResult {
        record(method: "captureSurface", payloadType: "Void", payloadSummary: "")
        return try await sink.captureSurface()
    }

    public func getSurfaceTree() async throws -> OwlFreshSurfaceTree {
        record(method: "getSurfaceTree", payloadType: "Void", payloadSummary: "")
        return try await sink.getSurfaceTree()
    }

    public func acceptActivePopupMenuItem(_ index: UInt32) async throws -> Bool {
        record(method: "acceptActivePopupMenuItem", payloadType: "UInt32", payloadSummary: String(describing: index))
        return try await sink.acceptActivePopupMenuItem(index)
    }

    public func cancelActivePopup() async throws -> Bool {
        record(method: "cancelActivePopup", payloadType: "Void", payloadSummary: "")
        return try await sink.cancelActivePopup()
    }
}

public struct MojoSchemaDeclaration: Equatable, Codable {
    public let kind: String
    public let name: String
}

public enum OwlFreshMojoSchema {
    public static let module = "content.mojom"
    public static let sourceChecksum = "fnv1a64:9ea0a10990b5c8cb"
    public static let declarations: [MojoSchemaDeclaration] = [
        MojoSchemaDeclaration(kind: "enum", name: "OwlFreshMouseKind"),
        MojoSchemaDeclaration(kind: "struct", name: "OwlFreshMouseEvent"),
        MojoSchemaDeclaration(kind: "struct", name: "OwlFreshKeyEvent"),
        MojoSchemaDeclaration(kind: "struct", name: "OwlFreshCompositorInfo"),
        MojoSchemaDeclaration(kind: "enum", name: "OwlFreshSurfaceKind"),
        MojoSchemaDeclaration(kind: "struct", name: "OwlFreshSurfaceInfo"),
        MojoSchemaDeclaration(kind: "struct", name: "OwlFreshSurfaceTree"),
        MojoSchemaDeclaration(kind: "struct", name: "OwlFreshCaptureResult"),
        MojoSchemaDeclaration(kind: "interface", name: "OwlFreshClient"),
        MojoSchemaDeclaration(kind: "interface", name: "OwlFreshHost")
    ]
}
