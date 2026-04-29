import Foundation
import XCTest

/// Exercises the right-sidebar Feed end-to-end: boot the app with a
/// dedicated socket, inject a synthetic permission request over the
/// socket's `feed.push` V2 verb, toggle the sidebar to Feed mode, tap
/// Allow Once, and assert the hook-side socket response carries the
/// resolved decision.
final class FeedSidebarUITests: XCTestCase {
    private var socketPath = ""
    private let modeKey = "socketControlMode"
    private var launchTag = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        launchTag = "ui-feed-\(UUID().uuidString.prefix(8))"
        socketPath = "/tmp/cmux-debug-\(UUID().uuidString).sock"
        removeSocketFiles()
    }

    func testFeedReceivesAndResolvesPermissionRequest() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-\(modeKey)", "allowAll"]
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_SOCKET_MODE"] = "allowAll"
        app.launchEnvironment["CMUX_SOCKET_ENABLE"] = "1"
        app.launchEnvironment["CMUX_ALLOW_SOCKET_OVERRIDE"] = "1"
        app.launchEnvironment["CMUX_TAG"] = launchTag
        app.launchEnvironment["CMUX_UI_TEST_SOCKET_SANITY"] = "1"
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "cmux failed to launch for Feed UI test"
        )

        guard let resolvedPath = resolveSocketPath(timeout: 15) else {
            XCTFail("Expected control socket at \(candidateSocketPaths().joined(separator: ", "))")
            return
        }
        socketPath = resolvedPath

        // Reveal the right sidebar and toggle to Feed.
        var feedButton = waitForButton(
            in: app,
            matching: ["RightSidebarModeButton.feed", "Feed"],
            timeout: 5
        )
        if feedButton == nil {
            // Fall back: send the right-sidebar toggle shortcut (⌘⌥B).
            app.typeKey("b", modifierFlags: [.command, .option])
            feedButton = waitForButton(
                in: app,
                matching: ["RightSidebarModeButton.feed", "Feed"],
                timeout: 5
            )
        }
        let visibleFeedButton = try XCTUnwrap(
            feedButton,
            "Feed tab not visible in right sidebar"
        )
        visibleFeedButton.click()

        // Push a synthetic permission request via the socket.
        let requestId = "uitest-\(UUID().uuidString)"
        let replyPayload = try sendFeedPush(requestId: requestId, waitSeconds: 30)

        // The reply arrives once the Feed row's Allow Once button is
        // clicked, run that on the UI side while the send is in-flight.
        let allowButton = try XCTUnwrap(
            waitForButton(
                in: app,
                matching: ["FeedPermissionAllowOnceButton", "Allow Once"],
                timeout: 10
            ),
            "Allow Once button did not appear in Feed"
        )
        allowButton.click()

        // Await the socket reply from the earlier push.
        let result = try replyPayload.result(timeout: 30)
        XCTAssertEqual(
            result.status, "resolved",
            "Expected feed.push to resolve, got status=\(result.status)"
        )
        XCTAssertEqual(result.mode, "once")

        app.terminate()
    }

    // MARK: - Socket helpers

    private struct FeedPushResult {
        let status: String
        let mode: String
    }

    private final class FeedPushFuture {
        private let semaphore = DispatchSemaphore(value: 0)
        private var outcome: Result<FeedPushResult, Error>?

        func resolve(_ outcome: Result<FeedPushResult, Error>) {
            self.outcome = outcome
            semaphore.signal()
        }

        func result(timeout: TimeInterval) throws -> FeedPushResult {
            let deadline: DispatchTime = .now() + timeout
            if semaphore.wait(timeout: deadline) == .timedOut {
                throw NSError(domain: "FeedPush", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "feed.push never returned"])
            }
            return try outcome!.get()
        }
    }

    private func sendFeedPush(requestId: String, waitSeconds: Double) throws -> FeedPushFuture {
        let future = FeedPushFuture()
        DispatchQueue.global().async {
            do {
                let params: [String: Any] = [
                    "event": [
                        "session_id": "uitest-\(requestId)",
                        "hook_event_name": "PermissionRequest",
                        "_source": "claude",
                        "tool_name": "Write",
                        "tool_input": ["file_path": "/tmp/feeduitest"],
                        "_opencode_request_id": requestId,
                    ],
                    "wait_timeout_seconds": waitSeconds,
                ]
                let respObj = try self.sendFrame(
                    method: "feed.push",
                    params: params,
                    responseTimeout: waitSeconds + 5
                )
                guard (respObj["ok"] as? Bool) == true,
                      let result = respObj["result"] as? [String: Any],
                      let status = result["status"] as? String
                else {
                    future.resolve(.failure(NSError(
                        domain: "FeedPush", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "invalid response: \(respObj)"]
                    )))
                    return
                }
                let mode = (result["decision"] as? [String: Any])?["mode"] as? String ?? ""
                future.resolve(.success(FeedPushResult(status: status, mode: mode)))
            } catch {
                future.resolve(.failure(error))
            }
        }
        return future
    }

    private func waitForButton(
        in app: XCUIApplication,
        matching identifiersOrLabels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifierOrLabel in identifiersOrLabels {
                let candidate = app.buttons[identifierOrLabel].firstMatch
                if candidate.exists {
                    return candidate
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private func waitForSocketPong(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? sendLine("ping\n", path: socketPath, responseTimeout: 1)) == "PONG" {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func resolveSocketPath(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for candidate in candidateSocketPaths() {
                if (try? sendLine("ping\n", path: candidate, responseTimeout: 1)) == "PONG" {
                    return candidate
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private func candidateSocketPaths() -> [String] {
        var seen = Set<String>()
        var candidates: [String] = []
        for path in [socketPath, taggedSocketPath()] where seen.insert(path).inserted {
            candidates.append(path)
        }
        return candidates
    }

    private func taggedSocketPath() -> String {
        "/tmp/cmux-debug-\(launchTag).sock"
    }

    private func sendFrame(
        method: String,
        params: [String: Any],
        responseTimeout: TimeInterval = 3
    ) throws -> [String: Any] {
        let frame: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: frame)
        let line = (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        let response = try sendLine(line, path: socketPath, responseTimeout: responseTimeout)
        guard let respData = response.data(using: .utf8),
              let respObj = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "invalid socket response: \(response)"]
            )
        }
        return respObj
    }

    private func sendLine(_ line: String, path: String, responseTimeout: TimeInterval) throws -> String {
        let sockFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockFd != -1 else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "socket() failed errno=\(errno)"]
            )
        }
        defer { close(sockFd) }

#if os(macOS)
        var noSigPipe: Int32 = 1
        _ = withUnsafePointer(to: &noSigPipe) { ptr in
            setsockopt(
                sockFd,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                ptr,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
#endif

        var addr = sockaddr_un()
        memset(&addr, 0, MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= maxLen else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "socket path too long: \(path)"]
            )
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            memset(raw, 0, maxLen)
            for index in 0..<bytes.count {
                raw[index] = bytes[index]
            }
        }

        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 0
        let size = socklen_t(pathOffset + bytes.count)
#if os(macOS)
        addr.sun_len = UInt8(min(Int(size), 255))
#endif
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { base in
                connect(sockFd, base, size)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "connect() failed errno=\(errno)"]
            )
        }

        let wrote = line.withCString { cString in
            var remaining = strlen(cString)
            var pointer = UnsafeRawPointer(cString)
            while remaining > 0 {
                let written = write(sockFd, pointer, remaining)
                if written <= 0 { return false }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
        guard wrote else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "write() failed errno=\(errno)"]
            )
        }

        // Read until newline or EOF.
        let deadline = Date().addingTimeInterval(responseTimeout)
        var chunk = [UInt8](repeating: 0, count: 4096)
        var accumulator = ""
        while Date() < deadline {
            var pollDescriptor = pollfd(fd: sockFd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, 100)
            if ready < 0 {
                throw NSError(
                    domain: "FeedSidebarUITests",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "poll() failed errno=\(errno)"]
                )
            }
            if ready == 0 { continue }
            let n = read(sockFd, &chunk, chunk.count)
            if n <= 0 { break }
            if let text = String(bytes: chunk[0..<n], encoding: .utf8) {
                accumulator.append(text)
                if let newline = accumulator.firstIndex(of: "\n") {
                    return String(accumulator[..<newline])
                }
            }
        }
        return accumulator.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeSocketFiles() {
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: taggedSocketPath())
    }
}
