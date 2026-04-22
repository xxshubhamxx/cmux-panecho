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

    func testThreadResumeRequestCarriesThreadIdAndCwd() throws {
        let request = CodexAppServerRequestFactory.threadResumeRequest(
            id: 8,
            threadId: "00000000-0000-0000-0000-000000000000",
            cwd: "/Users/cmux/project"
        )

        XCTAssertEqual(request["id"] as? Int, 8)
        XCTAssertEqual(request["method"] as? String, "thread/resume")

        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(params["cwd"] as? String, "/Users/cmux/project")
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

    func testResponseObjectUsesJsonRpcResponseShapeWithoutMethod() throws {
        let response = CodexAppServerRequestFactory.response(
            id: 12,
            result: ["decision": "accept"]
        )

        XCTAssertEqual(response["id"] as? Int, 12)
        XCTAssertNil(response["method"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["decision"] as? String, "accept")
    }

    func testErrorResponseCarriesMessage() throws {
        let response = CodexAppServerRequestFactory.errorResponse(
            id: 13,
            message: "unsupported"
        )

        XCTAssertEqual(response["id"] as? Int, 13)
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["message"] as? String, "unsupported")
        XCTAssertNotNil(error["code"] as? Int)
    }

    func testAppServerEnvironmentIncludesNodeVersionManagerPaths() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-codex-app-server-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let nvmNodeBin = tempDirectory
            .appendingPathComponent(".nvm/versions/node/v25.8.1/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: nvmNodeBin, withIntermediateDirectories: true)

        let environment = CodexAppServerClient.appServerEnvironment(
            baseEnvironment: [
                "HOME": tempDirectory.path,
                "PATH": "/usr/bin:/bin",
            ]
        )

        let pathComponents = try XCTUnwrap(environment["PATH"]).split(separator: ":").map(String.init)
        XCTAssertTrue(pathComponents.contains(nvmNodeBin.path))
    }

    func testLaunchConfigurationRunsNodeBackedCodexScriptWithResolvedNode() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-codex-launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let codexBin = tempDirectory.appendingPathComponent("codex-bin", isDirectory: true)
        let nodeBin = tempDirectory.appendingPathComponent(".nvm/versions/node/v25.8.1/bin", isDirectory: true)
        try fileManager.createDirectory(at: codexBin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nodeBin, withIntermediateDirectories: true)

        let codexPath = codexBin.appendingPathComponent("codex")
        let nodePath = nodeBin.appendingPathComponent("node")
        try "#!/usr/bin/env node\n".write(to: codexPath, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: nodePath, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codexPath.path)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nodePath.path)

        let configuration = CodexAppServerClient.appServerLaunchConfiguration(
            baseEnvironment: [
                "HOME": tempDirectory.path,
                "PATH": codexBin.path,
            ]
        )

        XCTAssertEqual(configuration.executablePath, nodePath.path)
        XCTAssertEqual(configuration.arguments, [
            codexPath.path,
            "app-server",
            "--listen",
            "stdio://",
        ])
    }

    func testLineBufferFramesLinesAcrossLargeChunks() throws {
        var buffer = CodexAppServerLineBuffer()

        XCTAssertTrue(buffer.append(Data(repeating: 65, count: 32_768)).isEmpty)
        XCTAssertEqual(buffer.bufferedByteCount, 32_768)

        let lines = buffer.append(Data([0x0A, 66, 0x0A]))

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].count, 32_768)
        XCTAssertEqual(String(data: lines[1], encoding: .utf8), "B")
        XCTAssertEqual(buffer.bufferedByteCount, 0)
    }

    func testLineBufferReturnsFinalLineWithoutTrailingNewline() throws {
        var buffer = CodexAppServerLineBuffer()

        XCTAssertTrue(buffer.append(Data("partial".utf8)).isEmpty)

        let finalLine = try XCTUnwrap(buffer.finish())
        XCTAssertEqual(String(data: finalLine, encoding: .utf8), "partial")
        XCTAssertNil(buffer.finish())
    }

    func testLocalCodexHistoryLoaderRestoresTailFromJsonl() throws {
        let fileManager = FileManager.default
        let threadId = "019d6637-e5cc-7cc0-a321-2c43b799036b"
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-codex-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let sessionDirectory = tempDirectory
            .appendingPathComponent("2026/04/06", isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let fileURL = sessionDirectory
            .appendingPathComponent("rollout-2026-04-06T21-33-52-\(threadId).jsonl")

        let records: [[String: Any]] = [
            [
                "timestamp": "2026-04-06T21:33:52.000Z",
                "type": "session_meta",
                "payload": ["id": threadId],
            ],
            Self.responseItem(role: "developer", text: "skip developer instructions"),
            Self.responseItem(role: "user", text: "user 1"),
            Self.responseItem(role: "assistant", text: "agent 1"),
            [
                "timestamp": "2026-04-06T21:34:03.000Z",
                "type": "response_item",
                "payload": [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"ls -la\"}",
                ],
            ],
            [
                "timestamp": "2026-04-06T21:34:04.000Z",
                "type": "response_item",
                "payload": [
                    "type": "function_call_output",
                    "call_id": "call_1",
                    "output": "output text",
                ],
            ],
            Self.responseItem(role: "assistant", text: "agent 2"),
        ]
        let jsonl = try records.map(Self.jsonLine).joined(separator: "\n")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let snapshot = CodexSessionHistoryLoader.loadHistorySync(
            threadId: threadId,
            limit: 3,
            searchRoots: [tempDirectory]
        )

        XCTAssertEqual(snapshot.fileURL?.resolvingSymlinksInPath(), fileURL.resolvingSymlinksInPath())
        XCTAssertEqual(snapshot.totalDisplayableItemCount, 5)
        XCTAssertTrue(snapshot.didTruncate)
        XCTAssertEqual(snapshot.transcriptItems.map(\.role), [.event, .event, .assistant])
        XCTAssertEqual(snapshot.transcriptItems.map(\.body), ["ls -la", "output text", "agent 2"])
    }

    @MainActor
    func testResumeSnapshotCapsRestoredTranscriptToTailItems() throws {
        let turns: [[String: Any]] = (0..<3).map { index in
            [
                "startedAt": index,
                "items": [
                    [
                        "type": "userMessage",
                        "content": [
                            [
                                "type": "text",
                                "text": "user \(index)",
                            ],
                        ],
                    ],
                    [
                        "type": "agentMessage",
                        "text": "agent \(index)",
                    ],
                ],
            ]
        }
        let response: [String: Any] = [
            "cwd": "/Users/cmux/project",
            "thread": [
                "id": "thread-123",
                "turns": turns,
            ],
        ]

        let snapshot = CodexAppServerPanel.resumeSnapshot(
            from: response,
            fallbackThreadId: "fallback-thread",
            restoredItemLimit: 3
        )

        XCTAssertEqual(snapshot.threadId, "thread-123")
        XCTAssertEqual(snapshot.cwd, "/Users/cmux/project")
        XCTAssertEqual(snapshot.totalRestoredItemCount, 6)
        XCTAssertTrue(snapshot.didTruncate)
        XCTAssertFalse(snapshot.responseWasTruncated)
        XCTAssertEqual(snapshot.transcriptItems.map(\.body), ["agent 1", "user 2", "agent 2"])
    }

    @MainActor
    func testResumeSnapshotHandlesOversizedResponseFallback() throws {
        let response: [String: Any] = [
            "_cmuxResponseTruncated": true,
            "thread": ["id": "thread-large"],
        ]

        let snapshot = CodexAppServerPanel.resumeSnapshot(
            from: response,
            fallbackThreadId: "fallback-thread",
            restoredItemLimit: 3
        )

        XCTAssertEqual(snapshot.threadId, "thread-large")
        XCTAssertTrue(snapshot.responseWasTruncated)
        XCTAssertTrue(snapshot.transcriptItems.isEmpty)
    }

    func testGeneratedSchemasCoverCodexAppServerProtocolUnions() {
        XCTAssertEqual(CodexAppServerProtocolSchemas.sourceRemote, "https://github.com/openai/codex.git")
        XCTAssertEqual(
            CodexAppServerProtocolSchemas.sourceRevision,
            "b04ffeee4c806834bc9173455729cf47f874e836"
        )
        XCTAssertEqual(CodexAppServerServerNotificationMethod.allCases.count, 56)
        XCTAssertEqual(CodexAppServerServerRequestMethod.allCases.count, 9)
        XCTAssertEqual(CodexAppServerClientRequestMethod.allCases.count, 69)
        XCTAssertEqual(CodexAppServerClientNotificationMethod.allCases.count, 1)
    }

    func testGeneratedSchemaLookupIncludesKnownEventPayloadSchemas() throws {
        let agentDelta = try XCTUnwrap(
            CodexAppServerProtocolSchemas.serverNotificationSchema(for: "item/agentMessage/delta")
        )
        XCTAssertEqual(agentDelta.paramsSchemaName, "AgentMessageDeltaNotification")

        let permissionsApproval = try XCTUnwrap(
            CodexAppServerProtocolSchemas.serverRequestSchema(for: "item/permissions/requestApproval")
        )
        XCTAssertEqual(permissionsApproval.paramsSchemaName, "PermissionsRequestApprovalParams")

        let turnStart = try XCTUnwrap(
            CodexAppServerProtocolSchemas.clientRequestSchema(for: "turn/start")
        )
        XCTAssertEqual(turnStart.paramsSchemaName, "TurnStartParams")
    }

    func testGeneratedRootSchemaJSONRoundTrips() throws {
        let json = try XCTUnwrap(CodexAppServerProtocolSchemas.rootSchemaJSON(named: "ServerNotification"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual((object["oneOf"] as? [Any])?.count, 56)

        let requestJSON = try XCTUnwrap(CodexAppServerProtocolSchemas.rootSchemaJSON(named: "ClientRequest"))
        let requestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(requestJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual((requestObject["oneOf"] as? [Any])?.count, 69)
    }

    func testProtocolEventWrappersPreserveTypedMethodsAndParams() {
        let notification = CodexAppServerServerNotification(
            method: "item/agentMessage/delta",
            params: ["delta": "hello", "index": 2]
        )

        XCTAssertEqual(notification.method, .itemAgentMessageDelta)
        XCTAssertEqual(notification.schema?.paramsSchemaName, "AgentMessageDeltaNotification")
        XCTAssertEqual(notification.paramsObject?["delta"] as? String, "hello")
        XCTAssertEqual(notification.paramsObject?["index"] as? Double, 2)

        let request = CodexAppServerServerRequest(
            id: 88,
            method: "item/permissions/requestApproval",
            params: ["reason": "test"]
        )
        XCTAssertEqual(request.id, 88)
        XCTAssertEqual(request.method, .itemPermissionsRequestApproval)
        XCTAssertEqual(request.paramsObject?["reason"] as? String, "test")
    }

    private static func responseItem(role: String, text: String) -> [String: Any] {
        [
            "timestamp": "2026-04-06T21:34:00.000Z",
            "type": "response_item",
            "payload": [
                "type": "message",
                "role": role,
                "content": [
                    [
                        "type": role == "assistant" ? "output_text" : "input_text",
                        "text": text,
                    ],
                ],
            ],
        ]
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
