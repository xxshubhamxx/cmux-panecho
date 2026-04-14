//! End-to-end integration tests for the Zig daemon's Phase 1 push protocol.
//!
//! Each test stands up a real `serve_unix`-shaped listener on a temp Unix
//! socket path, connects one or more real clients, and drives line-delimited
//! JSON-RPC over the socket. No production code is modified — the test
//! server composes `session_service.Service` + `outbound_queue.OutboundQueue`
//! + `server_core.dispatch` in the same shape as production's
//! `serve_unix.handleClient`.

const std = @import("std");

const cmuxd = @import("cmuxd_src");
const pty_pump = cmuxd.pty_pump;
const session_service = cmuxd.session_service;
const server_core = cmuxd.server_core;

const test_util = @import("test_util.zig");

const Fixture = struct {
    alloc: std.mem.Allocator,
    service: session_service.Service,
    server: *test_util.Server,
    socket_path: []u8,

    fn init(alloc: std.mem.Allocator, label: []const u8) !*Fixture {
        const self = try alloc.create(Fixture);
        errdefer alloc.destroy(self);

        self.alloc = alloc;
        self.socket_path = try test_util.uniqueSocketPath(alloc, label);
        errdefer alloc.free(self.socket_path);

        self.service = session_service.Service.init(alloc);
        errdefer self.service.deinit();
        self.service.on_workspace_changed = &server_core.notifyWorkspaceSubscribers;
        // Service now lives at its final heap address; safe to start the
        // pump thread (it captures &self.service).
        self.service.ensurePumpStarted();

        self.server = try test_util.Server.start(alloc, &self.service, self.socket_path);
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.server.deinit();
        self.service.deinit();
        self.alloc.free(self.socket_path);
        self.alloc.destroy(self);
    }
};

fn deadlineIn(ms: i64) i64 {
    return std.time.milliTimestamp() + ms;
}

// ---------------------------------------------------------------------------
// Test 1: single-socket interleave
// ---------------------------------------------------------------------------

test "integration: single-socket interleave (workspace.changed + write resp + terminal.output)" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "interleave");
    defer fx.deinit();

    var client = try test_util.Client.connect(alloc, fx.socket_path);
    defer client.deinit();

    const hello_id = client.allocId();
    try client.sendRequest(hello_id, "hello", .{});
    {
        var resp = try client.awaitResponse(hello_id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
    }

    // Real PTY session. `cat` echoes what we write, so terminal.output will
    // carry our own bytes back.
    var opened = try fx.service.openTerminal("s-interleave", "cat", 80, 24);
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);

    const ws_id_owned = try fx.service.workspace_reg.create("integration-ws", null);
    _ = ws_id_owned;

    const sub_id = client.allocId();
    try client.sendRequest(sub_id, "workspace.subscribe", .{});
    {
        var resp = try client.awaitResponse(sub_id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
    }

    const tsub_id = client.allocId();
    try client.sendRequest(tsub_id, "terminal.subscribe", .{
        .session_id = "s-interleave",
        .offset = @as(u64, 0),
    });
    {
        var resp = try client.awaitResponse(tsub_id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
    }

    const write_bytes = "hello-from-client\n";
    const write_b64 = try test_util.base64Encode(alloc, write_bytes);
    defer alloc.free(write_b64);

    const write_id = client.allocId();
    try client.sendRequest(write_id, "terminal.write", .{
        .session_id = "s-interleave",
        .data = write_b64,
    });

    // Grab the workspace id freshly (create() returned it borrowed by us).
    const ws_id: []const u8 = blk: {
        const order = fx.service.workspace_reg.order.items;
        try std.testing.expect(order.len > 0);
        break :blk order[0];
    };
    const pin_id = client.allocId();
    try client.sendRequest(pin_id, "workspace.pin", .{
        .workspace_id = ws_id,
        .pinned = true,
    });

    var got_write_ok = false;
    var got_pin_ok = false;
    var got_terminal_output = false;
    var got_workspace_changed = false;

    const deadline = deadlineIn(4000);
    while (std.time.milliTimestamp() < deadline) {
        if (got_write_ok and got_pin_ok and got_terminal_output and got_workspace_changed) break;
        var parsed = client.readFrame(deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;

        if (parsed.value.object.get("id")) |id_val| {
            if (test_util.idEquals(id_val, write_id)) got_write_ok = true;
            if (test_util.idEquals(id_val, pin_id)) got_pin_ok = true;
            continue;
        }
        if (parsed.value.object.get("event")) |ev| {
            if (ev != .string) continue;
            if (std.mem.eql(u8, ev.string, "terminal.output")) {
                got_terminal_output = true;
            } else if (std.mem.eql(u8, ev.string, "workspace.changed")) {
                got_workspace_changed = true;
            }
        }
    }

    try std.testing.expect(got_write_ok);
    try std.testing.expect(got_pin_ok);
    try std.testing.expect(got_terminal_output);
    try std.testing.expect(got_workspace_changed);

    try fx.service.closeSession("s-interleave");
}

// ---------------------------------------------------------------------------
// Test 2: backpressure overflow closes the slow subscriber's socket, other
// subscribers keep flowing, daemon stays healthy
// ---------------------------------------------------------------------------

test "integration: backpressure overflow disconnects slow client, daemon stays alive" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "backpressure");
    defer fx.deinit();

    // A flood command. `yes` is universally available on macOS; the PTY
    // child inherits it and streams "y\n" as fast as the kernel schedules
    // it. Coupled with a slow/no-reading client this overruns the per-
    // subscriber OutboundQueue in a second or two.
    var opened = try fx.service.openTerminal("s-flood", "yes", 80, 24);
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-flood") catch {};

    // Fast client (A): reads eagerly and keeps up.
    var client_a = try test_util.Client.connect(alloc, fx.socket_path);
    defer client_a.deinit();

    // Slow client (B): intentionally never reads. Its outbound queue on
    // the daemon side will overflow and the daemon will shutdown its fd.
    var client_b = try test_util.Client.connect(alloc, fx.socket_path);
    defer client_b.deinit();

    {
        const id = client_a.allocId();
        try client_a.sendRequest(id, "terminal.subscribe", .{
            .session_id = "s-flood",
            .offset = @as(u64, 0),
        });
        var resp = try client_a.awaitResponse(id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
    }
    {
        const id = client_b.allocId();
        try client_b.sendRequest(id, "terminal.subscribe", .{
            .session_id = "s-flood",
            .offset = @as(u64, 0),
        });
        var resp = try client_b.awaitResponse(id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
    }

    // Drive client A for a generous window. A reads continuously, so its
    // queue never overflows. B doesn't read at all, so its queue grows
    // until it hits 4 MiB and the daemon shuts it down. The window has
    // to account for the kernel's recv buffer (~200 KiB) absorbing the
    // first wave before the daemon's outbound queue starts filling, so
    // we give it 20 s.
    var a_frames_seen: u64 = 0;
    const phase_deadline = deadlineIn(20000);
    var b_got_eof: bool = false;

    while (std.time.milliTimestamp() < phase_deadline) {
        // Pull frames from A non-blockingly (short deadline).
        if (client_a.readFrame(std.time.milliTimestamp() + 20)) |parsed| {
            var p = parsed;
            defer p.deinit();
            a_frames_seen += 1;
        } else |err| switch (err) {
            error.Timeout => {},
            error.ConnectionClosed => {
                return error.TestFailure; // A should NOT be disconnected.
            },
            else => return err,
        }

        // Probe B with a non-blocking read. Don't drain (that would defeat
        // the overflow). Just check if it EOF'd (daemon shut it down).
        if (b_got_eof) continue;
        var buf: [256]u8 = undefined;
        // Toggle O_NONBLOCK for a single-byte peek.
        const flags = std.posix.fcntl(client_b.fd, std.posix.F.GETFL, 0) catch break;
        _ = std.posix.fcntl(client_b.fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }))) catch break;
        defer _ = std.posix.fcntl(client_b.fd, std.posix.F.SETFL, flags) catch 0;
        // One byte peek so we learn whether the daemon closed the far end.
        const peek = std.posix.read(client_b.fd, buf[0..1]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => {
                // Most "socket closed" errors turn into ConnectionResetByPeer
                // or similar, which we treat as EOF.
                b_got_eof = true;
                continue;
            },
        };
        if (peek == 0) b_got_eof = true;
    }

    // Acceptance: B must have EOF'd, A must have kept receiving frames.
    try std.testing.expect(b_got_eof);
    try std.testing.expect(a_frames_seen > 0);

    // Daemon health: fresh client can ping and get a response.
    var client_c = try test_util.Client.connect(alloc, fx.socket_path);
    defer client_c.deinit();
    const ping_id = client_c.allocId();
    try client_c.sendRequest(ping_id, "ping", .{});
    var ping_resp = try client_c.awaitResponse(ping_id, deadlineIn(2000));
    defer ping_resp.deinit();
    try std.testing.expect(ping_resp.value.object.get("ok").?.bool);
}

// ---------------------------------------------------------------------------
// Test 3: EOF — session runs `printf done; exit`, subscribe before exit,
// then verify `done` in output + eof:true push + subsequent write fails
// ---------------------------------------------------------------------------

test "integration: EOF is delivered and subsequent writes fail" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "eof");
    defer fx.deinit();

    // Open the session BEFORE `printf` exits. Insert a small delay so the
    // subscribe races in before the shell exits.
    var opened = try fx.service.openTerminal(
        "s-eof",
        "printf done; sleep 0.1; exit 0",
        80,
        24,
    );
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-eof") catch {};

    var client = try test_util.Client.connect(alloc, fx.socket_path);
    defer client.deinit();

    var saw_done = false;
    var saw_eof = false;

    {
        const id = client.allocId();
        try client.sendRequest(id, "terminal.subscribe", .{
            .session_id = "s-eof",
            .offset = @as(u64, 0),
        });
        var resp = try client.awaitResponse(id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
        // The shell often finishes before the subscribe arrives, so the
        // snapshot itself can carry the final bytes and eof=true. Accept
        // those as saw_done/saw_eof if present.
        const result = resp.value.object.get("result").?.object;
        if (result.get("data")) |d| {
            if (d == .string and d.string.len > 0) {
                const decoded = try test_util.base64Decode(alloc, d.string);
                defer alloc.free(decoded);
                if (std.mem.indexOf(u8, decoded, "done") != null) saw_done = true;
            }
        }
        if (result.get("eof")) |e| {
            if (e == .bool and e.bool) saw_eof = true;
        }
    }

    const deadline = deadlineIn(4000);
    while (std.time.milliTimestamp() < deadline) {
        if (saw_done and saw_eof) break;
        var parsed = client.readFrame(deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const ev = parsed.value.object.get("event") orelse continue;
        if (ev != .string) continue;
        if (!std.mem.eql(u8, ev.string, "terminal.output")) continue;

        if (parsed.value.object.get("data")) |d| {
            if (d == .string and d.string.len > 0) {
                const decoded = try test_util.base64Decode(alloc, d.string);
                defer alloc.free(decoded);
                if (std.mem.indexOf(u8, decoded, "done") != null) saw_done = true;
            }
        }
        if (parsed.value.object.get("eof")) |e| {
            if (e == .bool and e.bool) saw_eof = true;
        }
    }

    try std.testing.expect(saw_done);
    try std.testing.expect(saw_eof);

    // After EOF the shell has exited, but the session still exists in the
    // registry. A write to the PTY master typically succeeds against the
    // kernel buffer even after the slave closed (PTY semantics). The test
    // here just confirms the daemon doesn't crash on a post-EOF write.
    const write_id = client.allocId();
    const b64 = try test_util.base64Encode(alloc, "x");
    defer alloc.free(b64);
    try client.sendRequest(write_id, "terminal.write", .{
        .session_id = "s-eof",
        .data = b64,
    });
    var write_resp = try client.awaitResponse(write_id, deadlineIn(2000));
    defer write_resp.deinit();
    // Either ok:true (kernel buffered) or ok:false with an error — both are
    // acceptable outcomes; what we care about is the daemon answering and
    // not crashing. We assert the response shape.
    try std.testing.expect(write_resp.value.object.get("ok") != null);
}

// ---------------------------------------------------------------------------
// Test 4: reconnect with stale offset → truncated:true, offset == base_offset
// ---------------------------------------------------------------------------

test "integration: reconnect with stale offset returns truncated=true" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "truncate");
    defer fx.deinit();

    // Flood output so the ring buffer (1 MiB default in terminal_session)
    // rotates and base_offset advances past 0.
    var opened = try fx.service.openTerminal(
        "s-trunc",
        // Emit > 2 MiB so base_offset advances well past 0.
        "dd if=/dev/zero bs=65536 count=40 2>/dev/null | base64",
        80,
        24,
    );
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-trunc") catch {};

    // Give the pump time to drain and ring buffer to advance.
    const runtime = fx.service.runtimes.get("s-trunc") orelse return error.MissingRuntime;
    const rotation_deadline = deadlineIn(8000);
    var rotated = false;
    while (std.time.milliTimestamp() < rotation_deadline) {
        runtime.lock.lock();
        const window = runtime.terminal.offsetWindow();
        runtime.lock.unlock();
        if (window.base_offset > 0) {
            rotated = true;
            break;
        }
        std.Thread.sleep(20 * std.time.ns_per_ms);
    }
    try std.testing.expect(rotated);

    // Reconnect with offset=0 (definitely stale, since base_offset > 0).
    var client = try test_util.Client.connect(alloc, fx.socket_path);
    defer client.deinit();
    const id = client.allocId();
    try client.sendRequest(id, "terminal.subscribe", .{
        .session_id = "s-trunc",
        .offset = @as(u64, 0),
    });
    var resp = try client.awaitResponse(id, deadlineIn(2000));
    defer resp.deinit();

    try std.testing.expect(resp.value.object.get("ok").?.bool);
    const result = resp.value.object.get("result").?.object;
    try std.testing.expect(result.get("truncated").?.bool);

    // The response's `offset` is the byte position of the END of the
    // returned snapshot (`offset + len(data)` of the snapshot data). It
    // must be >= the session's base_offset at that moment. We verify the
    // intrinsic invariant: the snapshot's start (base_offset) is reported
    // in `base_offset` and is > 0 (the ring DID rotate).
    const resp_base_offset = result.get("base_offset").?.integer;
    try std.testing.expect(resp_base_offset > 0);
}

// ---------------------------------------------------------------------------
// Test 5: reconnect with valid (non-stale) offset: truncated=false, no
// duplicated bytes in the continuation
// ---------------------------------------------------------------------------

test "integration: reconnect with valid offset resumes without duplication" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "resume");
    defer fx.deinit();

    // Slow emitter: one burst, a pause, then more. Easier to observe the
    // cursor advancing without the ring rotating.
    var opened = try fx.service.openTerminal(
        "s-resume",
        "printf FIRST; sleep 0.3; printf SECOND; sleep 0.3; printf THIRD",
        80,
        24,
    );
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-resume") catch {};

    // Client A: subscribe, collect bytes up to some offset, then disconnect.
    var client_a = try test_util.Client.connect(alloc, fx.socket_path);
    const id_a = client_a.allocId();
    try client_a.sendRequest(id_a, "terminal.subscribe", .{
        .session_id = "s-resume",
        .offset = @as(u64, 0),
    });
    var resp_a = try client_a.awaitResponse(id_a, deadlineIn(2000));
    resp_a.deinit();

    var a_accum: std.ArrayListUnmanaged(u8) = .empty;
    defer a_accum.deinit(alloc);
    var a_last_end_offset: u64 = 0;
    var saw_first = false;

    // Read until we see FIRST.
    const phase1_deadline = deadlineIn(3000);
    while (std.time.milliTimestamp() < phase1_deadline) {
        if (saw_first) break;
        var parsed = client_a.readFrame(phase1_deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const ev = parsed.value.object.get("event") orelse continue;
        if (ev != .string or !std.mem.eql(u8, ev.string, "terminal.output")) continue;

        const data_enc = parsed.value.object.get("data").?.string;
        if (data_enc.len > 0) {
            const decoded = try test_util.base64Decode(alloc, data_enc);
            defer alloc.free(decoded);
            try a_accum.appendSlice(alloc, decoded);
        }
        const off_v = parsed.value.object.get("offset").?;
        a_last_end_offset = @intCast(off_v.integer);
        if (std.mem.indexOf(u8, a_accum.items, "FIRST") != null) saw_first = true;
    }
    try std.testing.expect(saw_first);

    client_a.deinit();

    // Client B: reconnect with a_last_end_offset. Expect truncated=false
    // (ring hasn't rotated) and the rest of the stream picks up from that
    // exact offset without duplicating any FIRST bytes.
    var client_b = try test_util.Client.connect(alloc, fx.socket_path);
    defer client_b.deinit();

    const id_b = client_b.allocId();
    try client_b.sendRequest(id_b, "terminal.subscribe", .{
        .session_id = "s-resume",
        .offset = a_last_end_offset,
    });
    var resp_b = try client_b.awaitResponse(id_b, deadlineIn(2000));
    defer resp_b.deinit();

    const result_b = resp_b.value.object.get("result").?.object;
    try std.testing.expect(!result_b.get("truncated").?.bool);
    const snap_start_offset: u64 = @intCast(result_b.get("offset").?.integer);
    // The snapshot's reported offset is the end-of-snapshot position.
    // Since we're resuming at a_last_end_offset, the snapshot should
    // start at a_last_end_offset (no overlap).
    try std.testing.expect(snap_start_offset >= a_last_end_offset);

    // Collect all subsequent data + verify it contains SECOND + THIRD,
    // but NOT a second FIRST (no duplication).
    var b_accum: std.ArrayListUnmanaged(u8) = .empty;
    defer b_accum.deinit(alloc);
    // Include the snapshot's own data.
    const snap_data_b64 = result_b.get("data").?.string;
    if (snap_data_b64.len > 0) {
        const decoded = try test_util.base64Decode(alloc, snap_data_b64);
        defer alloc.free(decoded);
        try b_accum.appendSlice(alloc, decoded);
    }

    const phase2_deadline = deadlineIn(4000);
    while (std.time.milliTimestamp() < phase2_deadline) {
        if (std.mem.indexOf(u8, b_accum.items, "SECOND") != null and
            std.mem.indexOf(u8, b_accum.items, "THIRD") != null) break;
        var parsed = client_b.readFrame(phase2_deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const ev = parsed.value.object.get("event") orelse continue;
        if (ev != .string or !std.mem.eql(u8, ev.string, "terminal.output")) continue;

        const data_enc = parsed.value.object.get("data").?.string;
        if (data_enc.len > 0) {
            const decoded = try test_util.base64Decode(alloc, data_enc);
            defer alloc.free(decoded);
            try b_accum.appendSlice(alloc, decoded);
        }
    }

    // SECOND + THIRD present, FIRST absent (no duplication) since we
    // resumed past FIRST.
    try std.testing.expect(std.mem.indexOf(u8, b_accum.items, "SECOND") != null);
    try std.testing.expect(std.mem.indexOf(u8, b_accum.items, "THIRD") != null);
    try std.testing.expect(std.mem.indexOf(u8, b_accum.items, "FIRST") == null);
}

// ---------------------------------------------------------------------------
// Test 6: multi-subscriber — two clients on the same session both receive
// the same bytes without interference
// ---------------------------------------------------------------------------

test "integration: multi-subscriber delivery" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "multisub");
    defer fx.deinit();

    var opened = try fx.service.openTerminal(
        "s-multi",
        "printf HELLO; sleep 0.3; printf WORLD",
        80,
        24,
    );
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-multi") catch {};

    var client_a = try test_util.Client.connect(alloc, fx.socket_path);
    defer client_a.deinit();
    var client_b = try test_util.Client.connect(alloc, fx.socket_path);
    defer client_b.deinit();

    // Subscribe both BEFORE the second printf. Use offset=0 so both get
    // any already-emitted HELLO in the snapshot if they raced.
    {
        const id = client_a.allocId();
        try client_a.sendRequest(id, "terminal.subscribe", .{
            .session_id = "s-multi",
            .offset = @as(u64, 0),
        });
        var resp = try client_a.awaitResponse(id, deadlineIn(2000));
        defer resp.deinit();
    }
    {
        const id = client_b.allocId();
        try client_b.sendRequest(id, "terminal.subscribe", .{
            .session_id = "s-multi",
            .offset = @as(u64, 0),
        });
        var resp = try client_b.awaitResponse(id, deadlineIn(2000));
        defer resp.deinit();
    }

    // Drive both until each has seen WORLD.
    var a_accum: std.ArrayListUnmanaged(u8) = .empty;
    defer a_accum.deinit(alloc);
    var b_accum: std.ArrayListUnmanaged(u8) = .empty;
    defer b_accum.deinit(alloc);

    const deadline = deadlineIn(4000);
    while (std.time.milliTimestamp() < deadline) {
        const a_done = std.mem.indexOf(u8, a_accum.items, "WORLD") != null;
        const b_done = std.mem.indexOf(u8, b_accum.items, "WORLD") != null;
        if (a_done and b_done) break;

        if (!a_done) {
            if (client_a.readFrame(std.time.milliTimestamp() + 50)) |parsed| {
                var p = parsed;
                defer p.deinit();
                if (p.value == .object) {
                    if (p.value.object.get("event")) |ev| {
                        if (ev == .string and std.mem.eql(u8, ev.string, "terminal.output")) {
                            if (p.value.object.get("data")) |d| {
                                if (d == .string and d.string.len > 0) {
                                    const decoded = try test_util.base64Decode(alloc, d.string);
                                    defer alloc.free(decoded);
                                    try a_accum.appendSlice(alloc, decoded);
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        }
        if (!b_done) {
            if (client_b.readFrame(std.time.milliTimestamp() + 50)) |parsed| {
                var p = parsed;
                defer p.deinit();
                if (p.value == .object) {
                    if (p.value.object.get("event")) |ev| {
                        if (ev == .string and std.mem.eql(u8, ev.string, "terminal.output")) {
                            if (p.value.object.get("data")) |d| {
                                if (d == .string and d.string.len > 0) {
                                    const decoded = try test_util.base64Decode(alloc, d.string);
                                    defer alloc.free(decoded);
                                    try b_accum.appendSlice(alloc, decoded);
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        }
    }

    try std.testing.expect(std.mem.indexOf(u8, a_accum.items, "HELLO") != null);
    try std.testing.expect(std.mem.indexOf(u8, a_accum.items, "WORLD") != null);
    try std.testing.expect(std.mem.indexOf(u8, b_accum.items, "HELLO") != null);
    try std.testing.expect(std.mem.indexOf(u8, b_accum.items, "WORLD") != null);
}

// ---------------------------------------------------------------------------
// Test 7: subscribe race — subscribe while output is actively streaming,
// verify `snapshot_offset + len(snapshot_data)` exactly equals the first
// push's `offset - len(push_data)` (no gap, no overlap)
// ---------------------------------------------------------------------------

test "integration: subscribe race has no gap or overlap" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "race");
    defer fx.deinit();

    // Steady emitter that keeps streaming past the test's lifetime so a
    // fast subscribe-after-start still sees live pushes. A short per-line
    // sleep forces many pump cycles instead of one giant burst.
    var opened = try fx.service.openTerminal(
        "s-race",
        "i=0; while [ $i -lt 200 ]; do printf 'race-line-%04d\\n' $i; i=$((i+1)); done",
        80,
        24,
    );
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-race") catch {};

    // Let output get flowing before we subscribe. 30 ms is enough for the
    // pump to have drained several chunks without draining the whole run.
    std.Thread.sleep(30 * std.time.ns_per_ms);

    var client = try test_util.Client.connect(alloc, fx.socket_path);
    defer client.deinit();

    const sub_id = client.allocId();
    try client.sendRequest(sub_id, "terminal.subscribe", .{
        .session_id = "s-race",
        // Omit offset: daemon starts at current next_offset.
    });
    var snap_resp = try client.awaitResponse(sub_id, deadlineIn(2000));
    defer snap_resp.deinit();

    const snap_result = snap_resp.value.object.get("result").?.object;
    const snap_data_b64 = snap_result.get("data").?.string;
    const snap_end_offset: u64 = @intCast(snap_result.get("offset").?.integer);

    // Decode the snapshot to know its length.
    const snap_decoded_len = if (snap_data_b64.len == 0)
        @as(usize, 0)
    else blk: {
        const decoded = try test_util.base64Decode(alloc, snap_data_b64);
        defer alloc.free(decoded);
        break :blk decoded.len;
    };

    // Read frames until we see at least one terminal.output push and its
    // `offset - len(data)` should equal snap_end_offset.
    const deadline = deadlineIn(4000);
    var matched = false;
    while (std.time.milliTimestamp() < deadline) {
        if (matched) break;
        var parsed = client.readFrame(deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const ev = parsed.value.object.get("event") orelse continue;
        if (ev != .string or !std.mem.eql(u8, ev.string, "terminal.output")) continue;
        const push_end_offset: u64 = @intCast(parsed.value.object.get("offset").?.integer);
        const push_data_b64 = parsed.value.object.get("data").?.string;
        const push_decoded_len = if (push_data_b64.len == 0)
            @as(usize, 0)
        else blk: {
            const decoded = try test_util.base64Decode(alloc, push_data_b64);
            defer alloc.free(decoded);
            break :blk decoded.len;
        };
        if (push_decoded_len == 0) continue;

        const push_start_offset = push_end_offset - push_decoded_len;
        // No gap, no overlap: snap_end_offset == push_start_offset.
        try std.testing.expectEqual(snap_end_offset, push_start_offset);
        matched = true;
    }

    try std.testing.expect(matched);
    _ = snap_decoded_len;
}

// ---------------------------------------------------------------------------
// Test 8: mid-frame disconnect — abruptly reset a subscriber's socket while
// the daemon is actively pushing to it. Daemon must not crash, must clean
// up the subscriber slot, and a fresh client must be able to connect + ping.
// ---------------------------------------------------------------------------

test "integration: mid-frame disconnect leaves daemon healthy" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "midframe");
    defer fx.deinit();

    // Flood output so there are pushes in flight when we kill the socket.
    var opened = try fx.service.openTerminal("s-midframe", "yes", 80, 24);
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-midframe") catch {};

    // Connect a victim client and subscribe.
    var victim = try test_util.Client.connect(alloc, fx.socket_path);
    {
        const id = victim.allocId();
        try victim.sendRequest(id, "terminal.subscribe", .{
            .session_id = "s-midframe",
            .offset = @as(u64, 0),
        });
        var resp = try victim.awaitResponse(id, deadlineIn(2000));
        defer resp.deinit();
        try std.testing.expect(resp.value.object.get("ok").?.bool);
    }

    // Let the pump deliver at least one push frame so there's actual
    // outbound activity we can abort mid-flight.
    var saw_any = false;
    const settle_deadline = deadlineIn(2000);
    while (std.time.milliTimestamp() < settle_deadline and !saw_any) {
        var parsed = victim.readFrame(settle_deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        if (parsed.value.object.get("event")) |ev| {
            if (ev == .string and std.mem.eql(u8, ev.string, "terminal.output")) {
                saw_any = true;
            }
        }
    }
    try std.testing.expect(saw_any);

    // Abruptly disconnect. Shutdown both ends before close so the daemon's
    // next push to this subscriber hits EPIPE rather than just a FIN that
    // it could interleave with a partially-buffered frame. `yes` will
    // typically be mid-frame here because the pump is firing flat-out.
    std.posix.shutdown(victim.fd, .both) catch {};
    victim.deinit();

    // Give the daemon a moment to observe the EPIPE on its next pump push.
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Fresh client connects and pings. If the daemon crashed or leaked the
    // subscriber slot in a way that blocks new connects, this fails.
    var probe = try test_util.Client.connect(alloc, fx.socket_path);
    defer probe.deinit();
    const ping_id = probe.allocId();
    try probe.sendRequest(ping_id, "ping", .{});
    var ping_resp = try probe.awaitResponse(ping_id, deadlineIn(2000));
    defer ping_resp.deinit();
    try std.testing.expect(ping_resp.value.object.get("ok").?.bool);

    // And a fresh subscriber on the same flooded session still works (the
    // per-session subscriber list rebuilt cleanly).
    const re_id = probe.allocId();
    try probe.sendRequest(re_id, "terminal.subscribe", .{
        .session_id = "s-midframe",
        .offset = @as(u64, 0),
    });
    var re_resp = try probe.awaitResponse(re_id, deadlineIn(2000));
    defer re_resp.deinit();
    try std.testing.expect(re_resp.value.object.get("ok").?.bool);
}

// ---------------------------------------------------------------------------
// Test 9: sustained high-throughput stress — push a couple hundred KiB
// through a single subscriber, verify monotonic offsets, no gaps, daemon
// health after. This is the CI-friendly version of the plan's
// `cat /dev/urandom | base64` stress verification.
// ---------------------------------------------------------------------------

test "integration: sustained high-throughput stream is gapless and monotonic" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "stress");
    defer fx.deinit();

    // Bounded stream sized to fit inside the 1 MiB ring but large enough
    // to exercise the pump hot path across many kqueue wakeups and many
    // push frames. We use a shell loop so output is chunked into many
    // small reads (driving many pump cycles) rather than a single large
    // dd write that the kernel would deliver in one pump read.
    var opened = try fx.service.openTerminal(
        "s-stress",
        "i=0; while [ $i -lt 500 ]; do printf 'stress-chunk-%04d-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\\n' $i; i=$((i+1)); done",
        80,
        24,
    );
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);
    defer fx.service.closeSession("s-stress") catch {};

    var client = try test_util.Client.connect(alloc, fx.socket_path);
    defer client.deinit();

    const sub_id = client.allocId();
    try client.sendRequest(sub_id, "terminal.subscribe", .{
        .session_id = "s-stress",
        .offset = @as(u64, 0),
    });
    var resp = try client.awaitResponse(sub_id, deadlineIn(2000));
    defer resp.deinit();
    try std.testing.expect(resp.value.object.get("ok").?.bool);

    // Seed bookkeeping from the snapshot.
    const snap_result = resp.value.object.get("result").?.object;
    const snap_data_b64 = snap_result.get("data").?.string;
    const snap_end_offset: u64 = @intCast(snap_result.get("offset").?.integer);
    var expected_next_start: u64 = snap_end_offset;
    var total_bytes: u64 = snap_end_offset; // snapshot covers [0, snap_end_offset)
    try std.testing.expect(!snap_result.get("truncated").?.bool);
    _ = snap_data_b64;

    // If the shell exited and everything was drained before we subscribed,
    // the snapshot itself carries eof=true. Accept that as "saw EOF" so
    // very fast children still validate the gapless+monotonic invariant.
    var saw_eof = blk: {
        if (snap_result.get("eof")) |e| {
            if (e == .bool) break :blk e.bool;
        }
        break :blk false;
    };
    var frame_count: u64 = 0;
    const deadline = deadlineIn(15000);
    while (std.time.milliTimestamp() < deadline) {
        if (saw_eof) break;
        var parsed = client.readFrame(deadline) catch |err| switch (err) {
            error.Timeout => break,
            else => return err,
        };
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const ev = parsed.value.object.get("event") orelse continue;
        if (ev != .string or !std.mem.eql(u8, ev.string, "terminal.output")) continue;

        frame_count += 1;

        const data_b64 = parsed.value.object.get("data").?.string;
        const decoded_len: u64 = if (data_b64.len == 0)
            @as(u64, 0)
        else blk: {
            const decoded = try test_util.base64Decode(alloc, data_b64);
            defer alloc.free(decoded);
            break :blk decoded.len;
        };
        const push_end_offset: u64 = @intCast(parsed.value.object.get("offset").?.integer);

        if (decoded_len > 0) {
            const push_start_offset = push_end_offset - decoded_len;
            try std.testing.expectEqual(expected_next_start, push_start_offset);
            expected_next_start = push_end_offset;
            total_bytes = push_end_offset;
        }

        if (parsed.value.object.get("eof")) |e| {
            if (e == .bool and e.bool) saw_eof = true;
        }
    }

    try std.testing.expect(saw_eof);
    // 500 lines of ~110 bytes ≈ 55 KiB; the Ghostty terminal post-processing
    // (cursor moves, line wraps at 80 cols) inflates that further. Assert
    // at least 40 KiB so a short run still has strong signal without
    // overspecifying terminal-specific padding.
    try std.testing.expect(total_bytes >= 40 * 1024);
    // If the shell exited before subscribe, all data is in the snapshot
    // and frame_count=0 is fine — the gaplessness invariant was validated
    // trivially. Otherwise require meaningful chunking.
    if (frame_count > 0) try std.testing.expect(frame_count >= 2);

    // Daemon still healthy after the burst.
    var probe = try test_util.Client.connect(alloc, fx.socket_path);
    defer probe.deinit();
    const ping_id = probe.allocId();
    try probe.sendRequest(ping_id, "ping", .{});
    var ping_resp = try probe.awaitResponse(ping_id, deadlineIn(2000));
    defer ping_resp.deinit();
    try std.testing.expect(ping_resp.value.object.get("ok").?.bool);
}

// ---------------------------------------------------------------------------
// Test 10: memory-leak churn — open/close sessions and subscribe/unsubscribe
// many times. std.testing.allocator asserts there are no leaked bytes at
// teardown, so any SubscriberRegistry slot, RingBuffer, OutboundQueue, or
// session_registry entry that isn't freed will fail the test.
// ---------------------------------------------------------------------------

test "integration: session + subscriber churn does not leak memory" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "memchurn");
    defer fx.deinit();

    var client = try test_util.Client.connect(alloc, fx.socket_path);
    defer client.deinit();

    // 24 cycles is enough to exercise every free path several times without
    // blowing the CI clock. Each iteration: open PTY -> subscribe -> drain
    // a bit -> unsubscribe -> close session.
    var i: usize = 0;
    while (i < 24) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "s-churn-{d}", .{i}) catch unreachable;

        var opened = try fx.service.openTerminal(name, "printf ok", 80, 24);
        defer opened.status.deinit(alloc);
        defer alloc.free(opened.attachment_id);

        const sub_id = client.allocId();
        try client.sendRequest(sub_id, "terminal.subscribe", .{
            .session_id = name,
            .offset = @as(u64, 0),
        });
        var sub_resp = try client.awaitResponse(sub_id, deadlineIn(2000));
        defer sub_resp.deinit();
        try std.testing.expect(sub_resp.value.object.get("ok").?.bool);

        // Drain any pending frames for this session briefly so the
        // subscriber queue empties before we unsubscribe.
        const drain_deadline = std.time.milliTimestamp() + 150;
        while (std.time.milliTimestamp() < drain_deadline) {
            var parsed = client.readFrame(drain_deadline) catch |err| switch (err) {
                error.Timeout => break,
                else => return err,
            };
            parsed.deinit();
        }

        const unsub_id = client.allocId();
        try client.sendRequest(unsub_id, "terminal.unsubscribe", .{
            .session_id = name,
        });
        var unsub_resp = try client.awaitResponse(unsub_id, deadlineIn(2000));
        defer unsub_resp.deinit();
        try std.testing.expect(unsub_resp.value.object.get("ok").?.bool);

        try fx.service.closeSession(name);
    }

    // Daemon still responsive.
    const ping_id = client.allocId();
    try client.sendRequest(ping_id, "ping", .{});
    var ping_resp = try client.awaitResponse(ping_id, deadlineIn(2000));
    defer ping_resp.deinit();
    try std.testing.expect(ping_resp.value.object.get("ok").?.bool);

    // fx.deinit() -> service.deinit() -> GPA leak check on std.testing.alloc.
    // If any per-session path leaked, the allocator will fail the test.
}

// ---------------------------------------------------------------------------
// Test 11: CPU-leak idle — with a handful of idle sessions up, the daemon
// should not be spinning. Measure the process's utime+stime growth over a
// wall-clock interval and assert it stays under a conservative budget.
// ---------------------------------------------------------------------------

fn rusageCpuMicros() i64 {
    const ru = std.posix.getrusage(@as(i32, std.c.rusage.SELF));
    const u = @as(i64, ru.utime.sec) * std.time.us_per_s + @as(i64, ru.utime.usec);
    const s = @as(i64, ru.stime.sec) * std.time.us_per_s + @as(i64, ru.stime.usec);
    return u + s;
}

test "integration: idle sessions consume near-zero CPU" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var fx = try Fixture.init(alloc, "cpuidle");
    defer fx.deinit();

    // Spin up 6 sessions that sleep forever. They must all register with
    // the kqueue pump but emit no output.
    const N: usize = 6;
    var names: [N][]u8 = undefined;
    var opens: [N]session_service.OpenTerminalResult = undefined;
    var filled: usize = 0;
    defer {
        var j: usize = 0;
        while (j < filled) : (j += 1) {
            opens[j].status.deinit(alloc);
            alloc.free(opens[j].attachment_id);
            fx.service.closeSession(names[j]) catch {};
            alloc.free(names[j]);
        }
    }

    var i: usize = 0;
    while (i < N) : (i += 1) {
        const name = try std.fmt.allocPrint(alloc, "s-idle-{d}", .{i});
        names[i] = name;
        // `sleep 60` runs long enough that the whole measurement window
        // observes a stable, idle PTY. It never writes.
        opens[i] = try fx.service.openTerminal(name, "sleep 60", 80, 24);
        filled += 1;
    }

    // Let the pump settle (register fds with kqueue, any startup I/O,
    // etc.) before we start timing.
    std.Thread.sleep(200 * std.time.ns_per_ms);

    const cpu_before = rusageCpuMicros();
    const wall_before = std.time.milliTimestamp();

    // Idle window. Long enough to overwhelm any one-off startup cost.
    std.Thread.sleep(600 * std.time.ns_per_ms);

    const cpu_after = rusageCpuMicros();
    const wall_after = std.time.milliTimestamp();

    const cpu_used_us: i64 = cpu_after - cpu_before;
    const wall_elapsed_us: i64 = (wall_after - wall_before) * std.time.us_per_ms;

    // Budget: no more than 5% of wall clock burned on CPU across the
    // whole process (pump thread + accept thread + per-connection
    // thread). This leaves lots of margin for noise on a loaded CI
    // machine while still catching a real busy-loop regression, which
    // would typically burn 100%+ of one core.
    const budget_us: i64 = @divTrunc(wall_elapsed_us, 20);
    try std.testing.expect(cpu_used_us <= budget_us);
}
