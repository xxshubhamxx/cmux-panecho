import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class CodexAppServerRequestFactoryTests: XCTestCase {
    func testInitializeRequestUsesCodexAppServerHandshakeShape() throws {
        let request = CodexAppServerRequestFactory.initializeRequest(id: 42)

        XCTAssertEqual(request["id"] as? Int, 42)
        XCTAssertEqual(request["method"] as? String, "initialize")

        let params = try XCTUnwrap(request["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["name"] as? String, "cmux")
        XCTAssertEqual(clientInfo["title"] as? String, "cmux")
        XCTAssertNotNil(clientInfo["version"] as? String)

        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["experimentalApi"] as? Bool, true)
    }

    func testInitializedNotificationHasNoRequestId() {
        let notification = CodexAppServerRequestFactory.initializedNotification()

        XCTAssertNil(notification["id"])
        XCTAssertEqual(notification["method"] as? String, "initialized")
    }

    func testThreadStartRequestCarriesCwdAndEphemeralSession() throws {
        let request = CodexAppServerRequestFactory.threadStartRequest(
            id: 7,
            cwd: "/Users/cmux/project"
        )

        XCTAssertEqual(request["id"] as? Int, 7)
        XCTAssertEqual(request["method"] as? String, "thread/start")

        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["cwd"] as? String, "/Users/cmux/project")
        XCTAssertEqual(params["serviceName"] as? String, "cmux")
        XCTAssertEqual(params["ephemeral"] as? Bool, true)
    }

    func testTurnStartRequestUsesTextInputItemShape() throws {
        let request = CodexAppServerRequestFactory.turnStartRequest(
            id: 9,
            threadId: "thr_123",
            text: "Summarize this repo",
            cwd: "/Users/cmux/project"
        )

        XCTAssertEqual(request["id"] as? Int, 9)
        XCTAssertEqual(request["method"] as? String, "turn/start")

        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "thr_123")
        XCTAssertEqual(params["cwd"] as? String, "/Users/cmux/project")

        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["type"] as? String, "text")
        XCTAssertEqual(input[0]["text"] as? String, "Summarize this repo")
        XCTAssertNotNil(input[0]["textElements"] as? [Any])
    }
}
