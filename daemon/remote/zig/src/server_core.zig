const std = @import("std");
const build_options = @import("build_options");
const json_rpc = @import("json_rpc.zig");
const session_registry = @import("session_registry.zig");
const session_service = @import("session_service.zig");
const workspace_registry = @import("workspace_registry.zig");
const serialize = @import("serialize.zig");

const AttachmentResult = struct {
    attachment_id: []const u8,
    cols: u16,
    rows: u16,
};

pub fn handleLine(service: *session_service.Service, output: anytype, raw_line: []const u8) !void {
    const alloc = service.alloc;
    const trimmed = std.mem.trimRight(u8, raw_line, "\r");
    if (trimmed.len == 0) return;

    var req = json_rpc.decodeRequest(alloc, trimmed) catch {
        return writeResponse(output, alloc, try json_rpc.encodeResponse(alloc, .{
            .ok = false,
            .@"error" = .{
                .code = "invalid_request",
                .message = "invalid JSON request",
            },
        }));
    };
    defer req.deinit(alloc);

    const response = try dispatch(service, &req);
    try writeResponse(output, alloc, response);
}

pub fn dispatch(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const seq_before = service.workspace_reg.change_seq;
    const result = try dispatchInner(service, req);
    // If any workspace state changed, notify subscribers
    if (service.workspace_reg.change_seq != seq_before) {
        notifyWorkspaceSubscribers(service);
    }
    return result;
}

fn dispatchInner(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;

    if (std.mem.eql(u8, req.method, "hello")) {
        return try json_rpc.encodeResponse(alloc, .{
            .id = req.id,
            .ok = true,
            .result = .{
                .name = "cmuxd-remote",
                .version = build_options.version,
                .workspace_count = service.workspace_reg.order.items.len,
                .capabilities = .{
                    "session.basic",
                    "session.resize.min",
                    "terminal.stream",
                    "proxy.http_connect",
                    "proxy.socks5",
                    "proxy.stream",
                },
            },
        });
    }
    if (std.mem.eql(u8, req.method, "ping")) {
        return try json_rpc.encodeResponse(alloc, .{
            .id = req.id,
            .ok = true,
            .result = .{ .pong = true },
        });
    }
    if (std.mem.eql(u8, req.method, "proxy.open")) return handleProxyOpen(service, req);
    if (std.mem.eql(u8, req.method, "proxy.close")) return handleProxyClose(service, req);
    if (std.mem.eql(u8, req.method, "proxy.write")) return handleProxyWrite(service, req);
    if (std.mem.eql(u8, req.method, "proxy.read")) return handleProxyRead(service, req);
    if (std.mem.eql(u8, req.method, "session.open")) return handleSessionOpen(service, req);
    if (std.mem.eql(u8, req.method, "session.close")) return handleSessionClose(service, req);
    if (std.mem.eql(u8, req.method, "session.attach")) return handleSessionAttach(service, req);
    if (std.mem.eql(u8, req.method, "session.resize")) return handleSessionResize(service, req);
    if (std.mem.eql(u8, req.method, "session.detach")) return handleSessionDetach(service, req);
    if (std.mem.eql(u8, req.method, "session.status")) return handleSessionStatus(service, req);
    if (std.mem.eql(u8, req.method, "session.list")) return handleSessionList(service, req);
    if (std.mem.eql(u8, req.method, "session.history")) return handleSessionHistory(service, req);
    if (std.mem.eql(u8, req.method, "workspace.list")) return handleWorkspaceList(service, req);
    if (std.mem.eql(u8, req.method, "workspace.create")) return handleWorkspaceCreate(service, req);
    if (std.mem.eql(u8, req.method, "workspace.rename")) return handleWorkspaceRename(service, req);
    if (std.mem.eql(u8, req.method, "workspace.close")) return handleWorkspaceClose(service, req);
    if (std.mem.eql(u8, req.method, "workspace.select")) return handleWorkspaceSelect(service, req);
    if (std.mem.eql(u8, req.method, "pane.split")) return handlePaneSplit(service, req);
    if (std.mem.eql(u8, req.method, "pane.close")) return handlePaneClose(service, req);
    if (std.mem.eql(u8, req.method, "pane.focus")) return handlePaneFocus(service, req);
    if (std.mem.eql(u8, req.method, "workspace.sync")) return handleWorkspaceSync(service, req);
    if (std.mem.eql(u8, req.method, "workspace.subscribe")) return handleWorkspaceSubscribe(service, req);
    if (std.mem.eql(u8, req.method, "terminal.open")) return handleTerminalOpen(service, req);
    if (std.mem.eql(u8, req.method, "terminal.read")) return handleTerminalRead(service, req);
    if (std.mem.eql(u8, req.method, "terminal.write")) return handleTerminalWrite(service, req);

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = false,
        .@"error" = .{
            .code = "method_not_found",
            .message = "unknown method",
        },
    });
}

fn handleProxyOpen(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "proxy.open requires params");
    const host = getRequiredStringParam(params, "host", "proxy.open requires host") catch |err| return paramError(service.alloc, req.id, err);
    const port = getRequiredPositiveU16Param(params, "port", "proxy.open requires port in range 1-65535") catch |err| return paramError(service.alloc, req.id, err);

    const stream_id = service.openProxy(host, port) catch |err| {
        return errorResponse(service.alloc, req.id, "open_failed", @errorName(err));
    };

    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .stream_id = stream_id },
    });
}

fn handleProxyClose(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "proxy.close requires params");
    const stream_id = getRequiredStringParam(params, "stream_id", "proxy.close requires stream_id") catch |err| return paramError(service.alloc, req.id, err);

    service.closeProxy(stream_id) catch {
        return errorResponse(service.alloc, req.id, "not_found", "stream not found");
    };
    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .closed = true },
    });
}

fn handleProxyWrite(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "proxy.write requires params");
    const stream_id = getRequiredStringParam(params, "stream_id", "proxy.write requires stream_id") catch |err| return paramError(service.alloc, req.id, err);
    const encoded = getRequiredStringParam(params, "data_base64", "proxy.write requires data_base64") catch |err| return paramError(service.alloc, req.id, err);

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch {
        return invalidParams(service.alloc, req.id, "data_base64 must be valid base64");
    };
    const decoded = try service.alloc.alloc(u8, decoded_len);
    defer service.alloc.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch {
        return invalidParams(service.alloc, req.id, "data_base64 must be valid base64");
    };

    const written = service.writeProxy(stream_id, decoded) catch |err| switch (err) {
        error.StreamNotFound => return errorResponse(service.alloc, req.id, "not_found", "stream not found"),
        else => return errorResponse(service.alloc, req.id, "stream_error", @errorName(err)),
    };
    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .written = written },
    });
}

fn handleProxyRead(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "proxy.read requires params");
    const stream_id = getRequiredStringParam(params, "stream_id", "proxy.read requires stream_id") catch |err| return paramError(service.alloc, req.id, err);
    const max_bytes = getOptionalPositiveIntParam(params, "max_bytes") orelse 32_768;
    if (max_bytes > 262_144) return invalidParams(service.alloc, req.id, "max_bytes must be in range 1-262144");
    const timeout_ms = if (getOptionalNonNegativeIntParam(params, "timeout_ms")) |value| @as(i32, @intCast(value)) else 50;

    const read = service.readProxy(stream_id, @intCast(max_bytes), timeout_ms) catch |err| switch (err) {
        error.StreamNotFound => return errorResponse(service.alloc, req.id, "not_found", "stream not found"),
        else => return errorResponse(service.alloc, req.id, "stream_error", @errorName(err)),
    };
    defer service.alloc.free(read.data);

    const encoded_len = std.base64.standard.Encoder.calcSize(read.data.len);
    const encoded = try service.alloc.alloc(u8, encoded_len);
    defer service.alloc.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, read.data);

    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .data_base64 = encoded,
            .eof = read.eof,
        },
    });
}

fn handleSessionOpen(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req);
    const requested_id = if (params) |object| getOptionalStringParam(object, "session_id") else null;
    var status = try service.openSession(requested_id);
    defer status.deinit(service.alloc);
    return encodeStatusResponse(service.alloc, req.id, status, null, null);
}

fn handleSessionClose(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "session.close requires params");
    const session_id = getRequiredStringParam(params, "session_id", "session.close requires session_id") catch |err| return paramError(service.alloc, req.id, err);

    service.closeSession(session_id) catch |err| return sessionErrorResponse(service.alloc, req.id, err);
    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .session_id = session_id,
            .closed = true,
        },
    });
}

fn handleSessionAttach(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "session.attach requires params");
    const parsed = parseAttachmentParams(params, "session.attach") catch |err| return paramError(service.alloc, req.id, err);

    var status = service.attachSession(parsed.session_id, parsed.attachment_id, parsed.cols, parsed.rows) catch |err| return sessionErrorResponse(service.alloc, req.id, err);
    defer status.deinit(service.alloc);
    return encodeStatusResponse(service.alloc, req.id, status, null, null);
}

fn handleSessionResize(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "session.resize requires params");
    const parsed = parseAttachmentParams(params, "session.resize") catch |err| return paramError(service.alloc, req.id, err);

    var status = service.resizeSession(parsed.session_id, parsed.attachment_id, parsed.cols, parsed.rows) catch |err| return sessionErrorResponse(service.alloc, req.id, err);
    defer status.deinit(service.alloc);
    return encodeStatusResponse(service.alloc, req.id, status, null, null);
}

fn handleSessionDetach(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "session.detach requires params");
    const session_id = getRequiredStringParam(params, "session_id", "session.detach requires session_id") catch |err| return paramError(service.alloc, req.id, err);
    const attachment_id = getRequiredStringParam(params, "attachment_id", "session.detach requires attachment_id") catch |err| return paramError(service.alloc, req.id, err);

    var status = service.detachSession(session_id, attachment_id) catch |err| return sessionErrorResponse(service.alloc, req.id, err);
    defer status.deinit(service.alloc);
    return encodeStatusResponse(service.alloc, req.id, status, null, null);
}

fn handleSessionStatus(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "session.status requires params");
    const session_id = getRequiredStringParam(params, "session_id", "session.status requires session_id") catch |err| return paramError(service.alloc, req.id, err);

    var status = service.sessionStatus(session_id) catch |err| return sessionErrorResponse(service.alloc, req.id, err);
    defer status.deinit(service.alloc);
    return encodeStatusResponse(service.alloc, req.id, status, null, null);
}

fn handleSessionList(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const sessions = try service.listSessions();
    defer {
        for (sessions) |*entry| entry.deinit(service.alloc);
        service.alloc.free(sessions);
    }

    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .sessions = sessions },
    });
}

fn handleSessionHistory(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "session.history requires params");
    const session_id = getRequiredStringParam(params, "session_id", "session.history requires session_id") catch |err| return paramError(service.alloc, req.id, err);

    const format: serialize.HistoryFormat = blk: {
        const fmt_str = getOptionalStringParam(params, "format") orelse break :blk .plain;
        if (std.mem.eql(u8, fmt_str, "vt")) break :blk .vt;
        if (std.mem.eql(u8, fmt_str, "html")) break :blk .html;
        break :blk .plain;
    };

    const history = service.history(session_id, format) catch |err| switch (err) {
        error.TerminalSessionNotFound => return terminalNotFound(service.alloc, req.id),
        else => return internalError(service.alloc, req.id, err),
    };
    defer service.alloc.free(history);

    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .session_id = session_id,
            .history = history,
        },
    });
}

fn handleTerminalOpen(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "terminal.open requires params");
    const requested_id = getOptionalStringParam(params, "session_id");
    const command = getRequiredStringParam(params, "command", "terminal.open requires command") catch |err| return paramError(service.alloc, req.id, err);
    const cols = getRequiredPositiveU16Param(params, "cols", "terminal.open requires cols > 0") catch |err| return paramError(service.alloc, req.id, err);
    const rows = getRequiredPositiveU16Param(params, "rows", "terminal.open requires rows > 0") catch |err| return paramError(service.alloc, req.id, err);

    var opened = service.openTerminal(requested_id, command, cols, rows) catch |err| switch (err) {
        error.SessionAlreadyExists => return errorResponse(service.alloc, req.id, "already_exists", "session already exists"),
        else => return internalError(service.alloc, req.id, err),
    };
    defer opened.status.deinit(service.alloc);
    defer service.alloc.free(opened.attachment_id);

    return encodeStatusResponse(service.alloc, req.id, opened.status, opened.attachment_id, opened.offset);
}

fn handleTerminalRead(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "terminal.read requires params");
    const session_id = getRequiredStringParam(params, "session_id", "terminal.read requires session_id") catch |err| return paramError(service.alloc, req.id, err);
    const offset = getRequiredU64Param(params, "offset", "terminal.read requires offset >= 0") catch |err| return paramError(service.alloc, req.id, err);
    const max_bytes = if (getOptionalPositiveIntParam(params, "max_bytes")) |value| @as(usize, @intCast(value)) else 65_536;
    const timeout_ms = if (getOptionalNonNegativeIntParam(params, "timeout_ms")) |value| @as(i32, @intCast(value)) else 0;

    const read = service.readTerminal(session_id, offset, max_bytes, timeout_ms) catch |err| switch (err) {
        error.TerminalSessionNotFound => return terminalNotFound(service.alloc, req.id),
        error.ReadTimeout => return deadlineExceeded(service.alloc, req.id, "terminal read timed out"),
        else => return internalError(service.alloc, req.id, err),
    };
    defer service.alloc.free(read.data);

    const encoded_len = std.base64.standard.Encoder.calcSize(read.data.len);
    const encoded = try service.alloc.alloc(u8, encoded_len);
    defer service.alloc.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, read.data);

    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .session_id = session_id,
            .offset = read.offset,
            .base_offset = read.base_offset,
            .truncated = read.truncated,
            .eof = read.eof,
            .data = encoded,
        },
    });
}

fn handleTerminalWrite(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const params = getParamsObject(req) orelse return invalidParams(service.alloc, req.id, "terminal.write requires params");
    const session_id = getRequiredStringParam(params, "session_id", "terminal.write requires session_id") catch |err| return paramError(service.alloc, req.id, err);
    const encoded = getRequiredStringParam(params, "data", "terminal.write requires data") catch |err| return paramError(service.alloc, req.id, err);

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch {
        return invalidParams(service.alloc, req.id, "terminal.write data must be base64");
    };
    const decoded = try service.alloc.alloc(u8, decoded_len);
    defer service.alloc.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch {
        return invalidParams(service.alloc, req.id, "terminal.write data must be base64");
    };

    const written = service.writeTerminal(session_id, decoded) catch |err| switch (err) {
        error.TerminalSessionNotFound => return terminalNotFound(service.alloc, req.id),
        else => return internalError(service.alloc, req.id, err),
    };
    return try json_rpc.encodeResponse(service.alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .session_id = session_id,
            .written = written,
        },
    });
}

fn encodeStatusResponse(
    alloc: std.mem.Allocator,
    id: ?std.json.Value,
    status: session_registry.SessionStatus,
    attachment_id: ?[]const u8,
    offset: ?u64,
) ![]u8 {
    var attachments = std.ArrayList(AttachmentResult).empty;
    defer attachments.deinit(alloc);

    for (status.attachments) |attachment| {
        try attachments.append(alloc, .{
            .attachment_id = attachment.attachment_id,
            .cols = attachment.cols,
            .rows = attachment.rows,
        });
    }

    return try json_rpc.encodeResponse(alloc, .{
        .id = id,
        .ok = true,
        .result = .{
            .session_id = status.session_id,
            .attachments = attachments.items,
            .effective_cols = status.effective_cols,
            .effective_rows = status.effective_rows,
            .last_known_cols = status.last_known_cols,
            .last_known_rows = status.last_known_rows,
            .attachment_id = attachment_id,
            .offset = offset,
        },
    });
}

fn getParamsObject(req: *const json_rpc.Request) ?std.json.ObjectMap {
    const value = req.parsed.value.object.get("params") orelse return null;
    if (value != .object) return null;
    return value.object;
}

fn getOptionalStringParam(params: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = params.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn getRequiredStringParam(params: std.json.ObjectMap, key: []const u8, message: []const u8) ![]const u8 {
    if (getOptionalStringParam(params, key)) |value| return value;
    _ = message;
    return error.InvalidStringParam;
}

fn getOptionalNonNegativeIntParam(params: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = params.get(key) orelse return null;
    return intFromValue(value);
}

fn getOptionalPositiveIntParam(params: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = intFromValue(params.get(key) orelse return null) orelse return null;
    if (value <= 0) return null;
    return value;
}

fn getRequiredPositiveU16Param(params: std.json.ObjectMap, key: []const u8, message: []const u8) !u16 {
    const value = getOptionalPositiveIntParam(params, key) orelse {
        _ = message;
        return error.InvalidPositiveParam;
    };
    if (value > std.math.maxInt(u16)) return error.InvalidPositiveParam;
    return @intCast(value);
}

fn getRequiredU64Param(params: std.json.ObjectMap, key: []const u8, message: []const u8) !u64 {
    const raw = params.get(key) orelse {
        _ = message;
        return error.InvalidUnsignedParam;
    };
    const value = intFromValue(raw) orelse {
        _ = message;
        return error.InvalidUnsignedParam;
    };
    if (value < 0) return error.InvalidUnsignedParam;
    return @intCast(value);
}

fn intFromValue(value: std.json.Value) ?i64 {
    return switch (value) {
        .integer => |int| int,
        .float => |float| if (@floor(float) == float) @as(i64, @intFromFloat(float)) else null,
        .number_string => |raw| std.fmt.parseInt(i64, raw, 10) catch null,
        else => null,
    };
}

const ParsedAttachmentParams = struct {
    session_id: []const u8,
    attachment_id: []const u8,
    cols: u16,
    rows: u16,
};

fn parseAttachmentParams(params: std.json.ObjectMap, method: []const u8) !ParsedAttachmentParams {
    const session_message = try std.fmt.allocPrint(std.heap.page_allocator, "{s} requires session_id", .{method});
    defer std.heap.page_allocator.free(session_message);
    const attachment_message = try std.fmt.allocPrint(std.heap.page_allocator, "{s} requires attachment_id", .{method});
    defer std.heap.page_allocator.free(attachment_message);
    const cols_message = try std.fmt.allocPrint(std.heap.page_allocator, "{s} requires cols > 0", .{method});
    defer std.heap.page_allocator.free(cols_message);
    const rows_message = try std.fmt.allocPrint(std.heap.page_allocator, "{s} requires rows > 0", .{method});
    defer std.heap.page_allocator.free(rows_message);

    return .{
        .session_id = try getRequiredStringParam(params, "session_id", session_message),
        .attachment_id = try getRequiredStringParam(params, "attachment_id", attachment_message),
        .cols = try getRequiredPositiveU16Param(params, "cols", cols_message),
        .rows = try getRequiredPositiveU16Param(params, "rows", rows_message),
    };
}

fn paramError(alloc: std.mem.Allocator, id: ?std.json.Value, err: anyerror) ![]u8 {
    return switch (err) {
        error.InvalidStringParam => invalidParams(alloc, id, "missing required string parameter"),
        error.InvalidPositiveParam => invalidParams(alloc, id, "missing required positive integer parameter"),
        error.InvalidUnsignedParam => invalidParams(alloc, id, "missing required unsigned integer parameter"),
        else => internalError(alloc, id, err),
    };
}

fn sessionErrorResponse(alloc: std.mem.Allocator, id: ?std.json.Value, err: anyerror) ![]u8 {
    return switch (err) {
        error.SessionNotFound => errorResponse(alloc, id, "not_found", "session not found"),
        error.AttachmentNotFound => errorResponse(alloc, id, "not_found", "attachment not found"),
        error.SessionAlreadyExists => errorResponse(alloc, id, "already_exists", "session already exists"),
        else => errorResponse(alloc, id, "invalid_params", "cols and rows must be greater than zero"),
    };
}

fn terminalNotFound(alloc: std.mem.Allocator, id: ?std.json.Value) ![]u8 {
    return errorResponse(alloc, id, "not_found", "terminal session not found");
}

fn deadlineExceeded(alloc: std.mem.Allocator, id: ?std.json.Value, message: []const u8) ![]u8 {
    return errorResponse(alloc, id, "deadline_exceeded", message);
}

fn invalidParams(alloc: std.mem.Allocator, id: ?std.json.Value, message: []const u8) ![]u8 {
    return errorResponse(alloc, id, "invalid_params", message);
}

fn internalError(alloc: std.mem.Allocator, id: ?std.json.Value, err: anyerror) ![]u8 {
    return errorResponse(alloc, id, "internal_error", @errorName(err));
}

fn handleWorkspaceList(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const reg = &service.workspace_reg;

    const WorkspaceEntry = struct {
        id: []const u8,
        title: []const u8,
        directory: []const u8,
        preview: []const u8,
        phase: []const u8,
        color: ?[]const u8,
        unread_count: u32,
        focused_pane_id: ?[]const u8,
        pane_count: usize,
        created_at: i64,
        last_activity_at: i64,
    };

    var entries: std.ArrayList(WorkspaceEntry) = .empty;
    defer entries.deinit(alloc);

    for (reg.order.items) |ws_id| {
        const ws = reg.workspaces.get(ws_id) orelse continue;
        const leaves = try ws.root_pane.collectLeaves(alloc);
        defer alloc.free(leaves);
        try entries.append(alloc, .{
            .id = ws.id,
            .title = ws.title,
            .directory = ws.directory,
            .preview = ws.preview,
            .phase = ws.phase,
            .color = ws.color,
            .unread_count = ws.unread_count,
            .focused_pane_id = ws.focused_pane_id,
            .pane_count = leaves.len,
            .created_at = ws.created_at,
            .last_activity_at = ws.last_activity_at,
        });
    }

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .workspaces = entries.items,
            .selected_workspace_id = reg.selected_id,
            .change_seq = reg.change_seq,
        },
    });
}

fn handleWorkspaceCreate(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req);
    const title = if (params) |p| getOptionalStringParam(p, "title") else null;
    const directory = if (params) |p| getOptionalStringParam(p, "directory") else null;
    const explicit_id = if (params) |p| getOptionalStringParam(p, "id") else null;

    const id = service.workspace_reg.createWithId(explicit_id, title, directory) catch |err| {
        return try errorResponse(alloc, req.id, "internal_error", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .workspace_id = id,
            .change_seq = service.workspace_reg.change_seq,
        },
    });
}

fn handleWorkspaceRename(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "workspace.rename requires params");
    const workspace_id = getRequiredStringParam(params, "workspace_id", "workspace.rename requires workspace_id") catch |err|
        return paramError(alloc, req.id, err);
    const title = getRequiredStringParam(params, "title", "workspace.rename requires title") catch |err|
        return paramError(alloc, req.id, err);

    service.workspace_reg.rename(workspace_id, title) catch |err| {
        return try errorResponse(alloc, req.id, "not_found", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .change_seq = service.workspace_reg.change_seq },
    });
}

fn handleWorkspaceClose(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "workspace.close requires params");
    const workspace_id = getRequiredStringParam(params, "workspace_id", "workspace.close requires workspace_id") catch |err|
        return paramError(alloc, req.id, err);

    service.workspace_reg.close(workspace_id) catch |err| {
        return try errorResponse(alloc, req.id, "not_found", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .change_seq = service.workspace_reg.change_seq },
    });
}

fn handleWorkspaceSelect(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "workspace.select requires params");
    const workspace_id = getRequiredStringParam(params, "workspace_id", "workspace.select requires workspace_id") catch |err|
        return paramError(alloc, req.id, err);

    service.workspace_reg.select(workspace_id) catch |err| {
        return try errorResponse(alloc, req.id, "not_found", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .change_seq = service.workspace_reg.change_seq },
    });
}

fn handlePaneSplit(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "pane.split requires params");
    const workspace_id = getRequiredStringParam(params, "workspace_id", "pane.split requires workspace_id") catch |err|
        return paramError(alloc, req.id, err);
    const pane_id = getRequiredStringParam(params, "pane_id", "pane.split requires pane_id") catch |err|
        return paramError(alloc, req.id, err);
    const dir_str = getOptionalStringParam(params, "direction") orelse "horizontal";
    const direction: workspace_registry.SplitDirection = if (std.mem.eql(u8, dir_str, "vertical")) .vertical else .horizontal;
    const type_str = getOptionalStringParam(params, "type") orelse "terminal";
    const pane_type: workspace_registry.PaneType = if (std.mem.eql(u8, type_str, "browser")) .browser else .terminal;

    const new_pane_id = service.workspace_reg.splitPane(workspace_id, pane_id, direction, pane_type) catch |err| {
        return try errorResponse(alloc, req.id, "not_found", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{
            .pane_id = new_pane_id,
            .change_seq = service.workspace_reg.change_seq,
        },
    });
}

fn handlePaneClose(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "pane.close requires params");
    const workspace_id = getRequiredStringParam(params, "workspace_id", "pane.close requires workspace_id") catch |err|
        return paramError(alloc, req.id, err);
    const pane_id = getRequiredStringParam(params, "pane_id", "pane.close requires pane_id") catch |err|
        return paramError(alloc, req.id, err);

    service.workspace_reg.closePane(workspace_id, pane_id) catch |err| {
        return try errorResponse(alloc, req.id, "not_found", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .change_seq = service.workspace_reg.change_seq },
    });
}

fn handlePaneFocus(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "pane.focus requires params");
    const workspace_id = getRequiredStringParam(params, "workspace_id", "pane.focus requires workspace_id") catch |err|
        return paramError(alloc, req.id, err);
    const pane_id = getRequiredStringParam(params, "pane_id", "pane.focus requires pane_id") catch |err|
        return paramError(alloc, req.id, err);

    service.workspace_reg.focusPane(workspace_id, pane_id) catch |err| {
        return try errorResponse(alloc, req.id, "not_found", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .change_seq = service.workspace_reg.change_seq },
    });
}

fn handleWorkspaceSync(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    const alloc = service.alloc;
    const params = getParamsObject(req) orelse
        return invalidParams(alloc, req.id, "workspace.sync requires params");

    const selected_id = getOptionalStringParam(params, "selected_workspace_id");

    // Parse workspaces array from the JSON Value
    const ws_value = params.get("workspaces") orelse
        return invalidParams(alloc, req.id, "workspace.sync requires workspaces array");

    if (ws_value != .array) return invalidParams(alloc, req.id, "workspaces must be an array");
    const ws_array = ws_value.array.items;

    var sync_workspaces: std.ArrayList(workspace_registry.Registry.SyncWorkspace) = .empty;
    defer sync_workspaces.deinit(alloc);

    for (ws_array) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const id = if (obj.get("id")) |v| (if (v == .string) v.string else null) else null;
        const title = if (obj.get("title")) |v| (if (v == .string) v.string else null) else null;
        if (id == null or title == null) continue;

        const unread_count: u32 = if (obj.get("unread_count")) |v| switch (v) {
            .integer => |i| if (i >= 0) @intCast(i) else 0,
            else => 0,
        } else 0;

        try sync_workspaces.append(alloc, .{
            .id = id.?,
            .title = title.?,
            .directory = if (obj.get("directory")) |v| (if (v == .string) v.string else "") else "",
            .preview = if (obj.get("preview")) |v| (if (v == .string) v.string else "") else "",
            .phase = if (obj.get("phase")) |v| (if (v == .string) v.string else "idle") else "idle",
            .color = if (obj.get("color")) |v| (if (v == .string) v.string else "") else "",
            .unread_count = unread_count,
        });
    }

    service.workspace_reg.syncAll(sync_workspaces.items, selected_id) catch |err| {
        return try errorResponse(alloc, req.id, "internal_error", @errorName(err));
    };

    return try json_rpc.encodeResponse(alloc, .{
        .id = req.id,
        .ok = true,
        .result = .{ .change_seq = service.workspace_reg.change_seq },
    });
}

fn handleWorkspaceSubscribe(service: *session_service.Service, req: *const json_rpc.Request) ![]u8 {
    // Note: actual subscription registration happens in serve_ws.zig's handleClient.
    // This handler just returns the current state as the initial snapshot.
    return handleWorkspaceList(service, req);
}

/// Notify all workspace subscribers that state has changed.
/// Called after any workspace/pane mutation.
/// Includes the full workspace list so clients don't need a round-trip re-fetch.
fn notifyWorkspaceSubscribers(service: *session_service.Service) void {
    const alloc = service.alloc;
    const reg = &service.workspace_reg;

    const WorkspaceEntry = struct {
        id: []const u8,
        title: []const u8,
        directory: []const u8,
        preview: []const u8,
        phase: []const u8,
        color: ?[]const u8,
        unread_count: u32,
        focused_pane_id: ?[]const u8,
        pane_count: usize,
        created_at: i64,
        last_activity_at: i64,
    };

    var entries: std.ArrayList(WorkspaceEntry) = .empty;
    defer entries.deinit(alloc);

    for (reg.order.items) |ws_id| {
        const ws = reg.workspaces.get(ws_id) orelse continue;
        const leaves = ws.root_pane.collectLeaves(alloc) catch continue;
        defer alloc.free(leaves);
        entries.append(alloc, .{
            .id = ws.id,
            .title = ws.title,
            .directory = ws.directory,
            .preview = ws.preview,
            .phase = ws.phase,
            .color = ws.color,
            .unread_count = ws.unread_count,
            .focused_pane_id = ws.focused_pane_id,
            .pane_count = leaves.len,
            .created_at = ws.created_at,
            .last_activity_at = ws.last_activity_at,
        }) catch continue;
    }

    const event = json_rpc.encodeResponse(alloc, .{
        .event = "workspace.changed",
        .change_seq = reg.change_seq,
        .result = .{
            .workspaces = entries.items,
            .selected_workspace_id = reg.selected_id,
        },
    }) catch return;
    defer alloc.free(event);
    service.subscriptions.notifyAll(event);
}

fn errorResponse(alloc: std.mem.Allocator, id: ?std.json.Value, code: []const u8, message: []const u8) ![]u8 {
    return try json_rpc.encodeResponse(alloc, .{
        .id = id,
        .ok = false,
        .@"error" = .{
            .code = code,
            .message = message,
        },
    });
}

fn writeResponse(output: anytype, alloc: std.mem.Allocator, payload: []u8) !void {
    defer alloc.free(payload);
    try output.print("{s}\n", .{payload});
    try output.flush();
}
