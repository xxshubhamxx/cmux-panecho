const std = @import("std");
const cross = @import("cross.zig");
const json_rpc = @import("json_rpc.zig");
const rpc_client = @import("rpc_client.zig");
const tty_raw = @import("tty_raw.zig");

const ReadOutcome = union(enum) {
    timeout,
    data: struct {
        payload: []u8,
        next_offset: u64,
        eof: bool,
    },
};

const Size = struct {
    cols: u16,
    rows: u16,
};

const default_size = Size{ .cols = 80, .rows = 24 };
const idle_read_timeout_ms: i32 = 2;

const InputPlan = struct {
    write_len: usize,
    next_pending_len: usize,
    detach: bool,
};

pub fn run(alloc: std.mem.Allocator, socket_path: []const u8, session_name: []const u8, stderr: anytype) !u8 {
    var client = rpc_client.Client.init(alloc, socket_path);
    defer client.deinit();
    const stdin_fd = std.fs.File.stdin().handle;
    const stdout_file = std.fs.File.stdout();
    var trace = try AttachTrace.init(alloc);
    defer trace.deinit();
    const fallback_size = try statusSize(&client, session_name, stderr);
    const size = currentAttachSizeWithTrace(fallback_size, &trace);
    const attachment_id = try std.fmt.allocPrint(alloc, "cli-{d}", .{cross.c.getpid()});
    defer alloc.free(attachment_id);

    try trace.log("attach_start", .{
        .hypothesis_id = "h2",
        .session_id = session_name,
        .attachment_id = attachment_id,
        .cols = size.cols,
        .rows = size.rows,
        .detail = "initial attach size",
    });
    try attachSession(&client, session_name, attachment_id, size.cols, size.rows, stderr);

    var guard = try tty_raw.RestoreGuard.enter(stdin_fd);
    defer guard.deinit();
    defer detachSession(&client, session_name, attachment_id, stderr) catch {};

    var last_size = size;
    var offset: u64 = 0;
    var pending_detach: [tty_raw.max_detach_prefix_bytes]u8 = undefined;
    var pending_detach_len: usize = 0;
    var input_buf: [4096 + tty_raw.max_detach_prefix_bytes]u8 = undefined;

    while (true) {
        const desired_size = currentAttachSizeWithTrace(last_size, &trace);
        if (desired_size.cols != last_size.cols or desired_size.rows != last_size.rows) {
            try trace.log("resize_sent", .{
                .hypothesis_id = "h2",
                .session_id = session_name,
                .attachment_id = attachment_id,
                .cols = desired_size.cols,
                .rows = desired_size.rows,
                .detail = "client observed tty resize",
            });
            try resizeSession(&client, session_name, attachment_id, desired_size.cols, desired_size.rows, stderr);
            last_size = desired_size;
        }

        if (try stdinReady(stdin_fd)) {
            pending_detach_len = try drainAndWriteInput(
                &client,
                session_name,
                stdin_fd,
                &input_buf,
                &pending_detach,
                pending_detach_len,
                stderr,
                &trace,
            ) orelse return 0;
            continue;
        }

        const read_started_ms = std.time.milliTimestamp();
        switch (try readTerminal(&client, session_name, offset, idle_read_timeout_ms, stderr)) {
            .timeout => std.Thread.yield() catch {},
            .data => |read| {
                defer alloc.free(read.payload);
                if (read.payload.len > 0) try stdout_file.writeAll(read.payload);
                offset = read.next_offset;
                try trace.log("read_result", .{
                    .hypothesis_id = "h1",
                    .session_id = session_name,
                    .attachment_id = attachment_id,
                    .elapsed_ms = std.time.milliTimestamp() - read_started_ms,
                    .payload_len = read.payload.len,
                    .detail = if (read.eof) "data_eof" else "data",
                });
                if (read.eof) return 0;
            },
        }
    }
}

const TraceEvent = struct {
    hypothesis_id: []const u8,
    session_id: ?[]const u8 = null,
    attachment_id: ?[]const u8 = null,
    probe: ?[]const u8 = null,
    detail: ?[]const u8 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
    payload_len: ?usize = null,
    elapsed_ms: ?i64 = null,
};

const AttachTrace = struct {
    file: ?std.fs.File = null,
    path: ?[]u8 = null,
    seq: u64 = 0,
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator) !AttachTrace {
        const path = std.process.getEnvVarOwned(alloc, "CMUXD_ATTACH_TRACE_PATH") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return .{ .alloc = alloc },
            else => return err,
        };
        errdefer alloc.free(path);

        var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        try file.writeAll("");
        return .{
            .file = file,
            .path = path,
            .alloc = alloc,
        };
    }

    fn deinit(self: *AttachTrace) void {
        if (self.file) |*file| file.close();
        if (self.path) |path| self.alloc.free(path);
        self.* = .{ .alloc = self.alloc };
    }

    fn log(self: *AttachTrace, name: []const u8, event: TraceEvent) !void {
        if (self.file == null) return;
        self.seq += 1;
        const file = &self.file.?;
        var output_buf: [1024]u8 = undefined;
        var output_writer = file.writer(&output_buf);
        const writer = &output_writer.interface;
        try writer.print(
            "{{\"seq\":{d},\"name\":\"{s}\",\"mono_ms\":{d},\"hypothesis_id\":\"{s}\"",
            .{ self.seq, name, std.time.milliTimestamp(), event.hypothesis_id },
        );
        if (event.session_id) |value| try writer.print(",\"session_id\":\"{s}\"", .{value});
        if (event.attachment_id) |value| try writer.print(",\"attachment_id\":\"{s}\"", .{value});
        if (event.probe) |value| try writer.print(",\"probe\":\"{s}\"", .{value});
        if (event.detail) |value| try writer.print(",\"detail\":\"{s}\"", .{value});
        if (event.cols) |value| try writer.print(",\"cols\":{d}", .{value});
        if (event.rows) |value| try writer.print(",\"rows\":{d}", .{value});
        if (event.payload_len) |value| try writer.print(",\"payload_len\":{d}", .{value});
        if (event.elapsed_ms) |value| try writer.print(",\"elapsed_ms\":{d}", .{value});
        try writer.writeAll("}\n");
        try writer.flush();
        try file.sync();
    }
};

fn attachSession(client: *rpc_client.Client, session_name: []const u8, attachment_id: []const u8, cols: u16, rows: u16, stderr: anytype) !void {
    var response = try call(client, .{
        .id = "1",
        .method = "session.attach",
        .params = .{
            .session_id = session_name,
            .attachment_id = attachment_id,
            .cols = cols,
            .rows = rows,
        },
    }, stderr);
    response.deinit();
}

fn resizeSession(client: *rpc_client.Client, session_name: []const u8, attachment_id: []const u8, cols: u16, rows: u16, stderr: anytype) !void {
    var response = try call(client, .{
        .id = "1",
        .method = "session.resize",
        .params = .{
            .session_id = session_name,
            .attachment_id = attachment_id,
            .cols = cols,
            .rows = rows,
        },
    }, stderr);
    response.deinit();
}

fn detachSession(client: *rpc_client.Client, session_name: []const u8, attachment_id: []const u8, stderr: anytype) !void {
    var response = try call(client, .{
        .id = "1",
        .method = "session.detach",
        .params = .{
            .session_id = session_name,
            .attachment_id = attachment_id,
        },
    }, stderr);
    response.deinit();
}

fn writeTerminal(client: *rpc_client.Client, session_name: []const u8, data: []const u8, stderr: anytype) !void {
    const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
    const encoded = try client.alloc.alloc(u8, encoded_len);
    defer client.alloc.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, data);

    var response = try call(client, .{
        .id = "1",
        .method = "terminal.write",
        .params = .{
            .session_id = session_name,
            .data = encoded,
        },
    }, stderr);
    response.deinit();
}

fn readTerminal(client: *rpc_client.Client, session_name: []const u8, offset: u64, timeout_ms: i32, stderr: anytype) !ReadOutcome {
    const request_json = try json_rpc.encodeResponse(client.alloc, .{
        .id = "1",
        .method = "terminal.read",
        .params = .{
            .session_id = session_name,
            .offset = offset,
            .max_bytes = 65536,
            .timeout_ms = timeout_ms,
        },
    });
    defer client.alloc.free(request_json);

    var response = try client.call(request_json);
    errdefer response.deinit();

    const root = response.value;
    if (root != .object) return error.InvalidResponse;
    const ok_value = root.object.get("ok") orelse return error.InvalidResponse;
    if (ok_value != .bool) return error.InvalidResponse;
    if (!ok_value.bool) {
        const err_obj = root.object.get("error") orelse return error.InvalidResponse;
        if (err_obj != .object) return error.InvalidResponse;
        const code = err_obj.object.get("code") orelse return error.InvalidResponse;
        if (code == .string and std.mem.eql(u8, code.string, "deadline_exceeded")) {
            response.deinit();
            return .timeout;
        }
        const message = err_obj.object.get("message") orelse return error.InvalidResponse;
        if (message != .string) return error.InvalidResponse;
        try stderr.print("{s}\n", .{message.string});
        try stderr.flush();
        return error.RemoteError;
    }

    const result = root.object.get("result") orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;
    const encoded = result.object.get("data") orelse return error.InvalidResponse;
    const next_offset_value = result.object.get("offset") orelse return error.InvalidResponse;
    const eof_value = result.object.get("eof") orelse return error.InvalidResponse;
    if (encoded != .string or eof_value != .bool) return error.InvalidResponse;

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded.string) catch return error.InvalidResponse;
    const decoded = try client.alloc.alloc(u8, decoded_len);
    errdefer client.alloc.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded.string) catch return error.InvalidResponse;

    const next_offset = try u64FromValue(next_offset_value);
    response.deinit();
    return .{
        .data = .{
            .payload = decoded,
            .next_offset = next_offset,
            .eof = eof_value.bool,
        },
    };
}

fn statusSize(client: *rpc_client.Client, session_name: []const u8, stderr: anytype) !Size {
    var response = try call(client, .{
        .id = "1",
        .method = "session.status",
        .params = .{ .session_id = session_name },
    }, stderr);
    defer response.deinit();

    const result = response.value.object.get("result").?.object;
    return preferredAttachSize(.{
        .cols = try u16FromValue(result.get("effective_cols").?),
        .rows = try u16FromValue(result.get("effective_rows").?),
    }, default_size);
}

pub fn currentAttachSize(fallback: Size) Size {
    return currentAttachSizeWithTrace(fallback, null);
}

fn currentAttachSizeWithTrace(fallback: Size, maybe_trace: ?*AttachTrace) Size {
    if (observedLocalSize(maybe_trace)) |observed| {
        return preferredAttachSize(observed, fallback);
    }
    if (isUsableLocalSize(fallback)) return fallback;
    return default_size;
}

fn observedLocalSize(maybe_trace: ?*AttachTrace) ?Size {
    const stdin_fd = std.fs.File.stdin().handle;
    if (probeSize("stdin", stdin_fd, maybe_trace)) |size| return size;

    const stdout_fd = std.fs.File.stdout().handle;
    if (stdout_fd != stdin_fd) {
        if (probeSize("stdout", stdout_fd, maybe_trace)) |size| return size;
    }

    const stderr_fd = std.fs.File.stderr().handle;
    if (stderr_fd != stdin_fd and stderr_fd != stdout_fd) {
        if (probeSize("stderr", stderr_fd, maybe_trace)) |size| return size;
    }

    if (std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write })) |tty| {
        defer tty.close();
        if (probeSize("tty", tty.handle, maybe_trace)) |size| return size;
    } else |_| {}

    return null;
}

fn probeSize(probe_name: []const u8, fd: std.posix.fd_t, maybe_trace: ?*AttachTrace) ?Size {
    const observed = tty_raw.currentSize(fd) catch |err| {
        if (maybe_trace) |trace| {
            trace.log("tty_probe", .{
                .hypothesis_id = "h2",
                .probe = probe_name,
                .detail = @errorName(err),
            }) catch {};
        }
        return null;
    };

    const size = Size{ .cols = observed.cols, .rows = observed.rows };
    if (maybe_trace) |trace| {
        trace.log("tty_probe", .{
            .hypothesis_id = "h2",
            .probe = probe_name,
            .cols = size.cols,
            .rows = size.rows,
            .detail = if (isUsableLocalSize(size)) "usable" else "too_small",
        }) catch {};
    }
    if (!isUsableLocalSize(size)) return null;
    return size;
}

fn stdinReady(fd: std.posix.fd_t) !bool {
    var poll_fds = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    return try std.posix.poll(&poll_fds, 0) > 0;
}

fn drainAndWriteInput(
    client: *rpc_client.Client,
    session_name: []const u8,
    stdin_fd: std.posix.fd_t,
    input_buf: *[4096 + tty_raw.max_detach_prefix_bytes]u8,
    pending_detach: *[tty_raw.max_detach_prefix_bytes]u8,
    pending_detach_len: usize,
    stderr: anytype,
    trace: *AttachTrace,
) !?usize {
    if (pending_detach_len > 0) {
        @memcpy(input_buf[0..pending_detach_len], pending_detach[0..pending_detach_len]);
    }

    const read_len = try drainTTYInput(stdin_fd, input_buf[pending_detach_len..]);
    if (read_len == 0) {
        if (pending_detach_len > 0) {
            const write_started_ms = std.time.milliTimestamp();
            try writeTerminal(client, session_name, pending_detach[0..pending_detach_len], stderr);
            try trace.log("write_result", .{
                .hypothesis_id = "h1",
                .session_id = session_name,
                .payload_len = pending_detach_len,
                .elapsed_ms = std.time.milliTimestamp() - write_started_ms,
                .detail = "flush_pending_on_eof",
            });
        }
        return null;
    }

    const total_len = pending_detach_len + read_len;
    const plan = planInput(input_buf[0..total_len]);
    if (plan.detach) {
        if (plan.write_len > 0) {
            const write_started_ms = std.time.milliTimestamp();
            try writeTerminal(client, session_name, input_buf[0..plan.write_len], stderr);
            try trace.log("write_result", .{
                .hypothesis_id = "h1",
                .session_id = session_name,
                .payload_len = plan.write_len,
                .elapsed_ms = std.time.milliTimestamp() - write_started_ms,
                .detail = "flush_before_detach",
            });
        }
        return null;
    }

    if (plan.write_len > 0) {
        const write_started_ms = std.time.milliTimestamp();
        try writeTerminal(client, session_name, input_buf[0..plan.write_len], stderr);
        try trace.log("write_result", .{
            .hypothesis_id = "h1",
            .session_id = session_name,
            .payload_len = plan.write_len,
            .elapsed_ms = std.time.milliTimestamp() - write_started_ms,
            .detail = "stdin_ready",
        });
    }

    if (plan.next_pending_len > 0) {
        @memcpy(pending_detach[0..plan.next_pending_len], input_buf[plan.write_len..total_len]);
    }
    return plan.next_pending_len;
}

fn planInput(input: []const u8) InputPlan {
    if (tty_raw.detachSequenceStart(input)) |detach_idx| {
        return .{
            .write_len = detach_idx,
            .next_pending_len = 0,
            .detach = true,
        };
    }

    const prefix_len = tty_raw.trailingDetachPrefixLen(input);
    return .{
        .write_len = input.len - prefix_len,
        .next_pending_len = prefix_len,
        .detach = false,
    };
}

fn drainTTYInput(fd: std.posix.fd_t, buf: []u8) !usize {
    if (buf.len == 0) return 0;

    var total = try std.posix.read(fd, buf);
    while (total > 0 and total < buf.len) {
        var poll_fds = [1]std.posix.pollfd{.{
            .fd = fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = try std.posix.poll(&poll_fds, 0);
        if (ready == 0) break;

        const next = try std.posix.read(fd, buf[total..]);
        if (next == 0) break;
        total += next;
    }

    return total;
}

fn preferredAttachSize(observed: Size, fallback: Size) Size {
    if (isUsableLocalSize(observed)) return observed;
    if (isUsableLocalSize(fallback)) return fallback;
    return default_size;
}

fn isUsableLocalSize(size: Size) bool {
    return size.cols >= 4 and size.rows >= 2;
}

fn call(client: *rpc_client.Client, request: anytype, stderr: anytype) !std.json.Parsed(std.json.Value) {
    const request_json = try json_rpc.encodeResponse(client.alloc, request);
    defer client.alloc.free(request_json);

    var response = try client.call(request_json);
    const root = response.value;
    if (root != .object) return error.InvalidResponse;
    if ((root.object.get("ok") orelse return error.InvalidResponse) != .bool) return error.InvalidResponse;
    if (root.object.get("ok").?.bool) return response;

    const err_obj = root.object.get("error") orelse return error.InvalidResponse;
    if (err_obj != .object) return error.InvalidResponse;
    const message = err_obj.object.get("message") orelse return error.InvalidResponse;
    if (message != .string) return error.InvalidResponse;

    try stderr.print("{s}\n", .{message.string});
    try stderr.flush();
    response.deinit();
    return error.RemoteError;
}

fn u64FromValue(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |int| if (int >= 0) @intCast(int) else error.InvalidResponse,
        .float => |float| if (float >= 0 and @floor(float) == float) @as(u64, @intFromFloat(float)) else error.InvalidResponse,
        .number_string => |raw| std.fmt.parseInt(u64, raw, 10) catch error.InvalidResponse,
        else => error.InvalidResponse,
    };
}

fn u16FromValue(value: std.json.Value) !u16 {
    const raw = try u64FromValue(value);
    if (raw > std.math.maxInt(u16)) return error.InvalidResponse;
    return @intCast(raw);
}

test "preferred attach size uses local tty when sane" {
    const size = preferredAttachSize(.{ .cols = 120, .rows = 40 }, .{ .cols = 80, .rows = 24 });
    try std.testing.expectEqual(@as(u16, 120), size.cols);
    try std.testing.expectEqual(@as(u16, 40), size.rows);
}

test "preferred attach size falls back for tiny tty" {
    const size = preferredAttachSize(.{ .cols = 1, .rows = 1 }, .{ .cols = 80, .rows = 24 });
    try std.testing.expectEqual(@as(u16, 80), size.cols);
    try std.testing.expectEqual(@as(u16, 24), size.rows);
}

test "plan input buffers fragmented kitty ctrl backslash until detach" {
    var pending: [tty_raw.max_detach_prefix_bytes + 1]u8 = undefined;
    var pending_len: usize = 0;

    const sequence = "\x1b[92;5u";
    for (sequence, 0..) |byte, index| {
        pending[pending_len] = byte;
        const total_len = pending_len + 1;
        const plan = planInput(pending[0..total_len]);

        if (index + 1 < sequence.len) {
            try std.testing.expect(!plan.detach);
            try std.testing.expectEqual(@as(usize, 0), plan.write_len);
            try std.testing.expectEqual(total_len, plan.next_pending_len);
            pending_len = plan.next_pending_len;
            continue;
        }

        try std.testing.expect(plan.detach);
        try std.testing.expectEqual(@as(usize, 0), plan.write_len);
        try std.testing.expectEqual(@as(usize, 0), plan.next_pending_len);
    }
}
