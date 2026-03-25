const std = @import("std");
const build_options = @import("build_options");
const cli_relay = @import("cli_relay.zig");
const cli_session = @import("cli_session.zig");
const serve_tls = @import("serve_tls.zig");
const serve_unix = @import("serve_unix.zig");
const ticket_auth = @import("ticket_auth.zig");
const serve_stdio = @import("serve_stdio.zig");
const json_rpc = @import("json_rpc.zig");
const proxy_streams = @import("proxy_streams.zig");
const session_registry = @import("session_registry.zig");
const terminal_session = @import("terminal_session.zig");

pub fn main() !void {
    _ = json_rpc;
    _ = proxy_streams;
    _ = session_registry;
    _ = ticket_auth;
    _ = terminal_session;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = try std.process.argsAlloc(alloc);

    const exit_code = try run(args);
    std.process.exit(exit_code);
}

fn run(args: []const []const u8) !u8 {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    const argv0 = if (args.len > 0) std.fs.path.basename(args[0]) else "cmuxd-remote";
    if (std.mem.eql(u8, argv0, "cmux")) {
        return cli_relay.run(if (args.len > 1) args[1..] else &.{}, stderr);
    }

    if (args.len <= 1) {
        try usage(stderr);
        return 2;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "version")) {
        try stdout.print("{s}\n", .{build_options.version});
        try stdout.flush();
        return 0;
    }
    if (std.mem.eql(u8, command, "cli")) {
        return cli_relay.run(if (args.len > 2) args[2..] else &.{}, stderr);
    }
    if (std.mem.eql(u8, command, "session")) {
        return cli_session.run(if (args.len > 2) args[2..] else &.{}, stderr, stdout);
    }
    if (isTopLevelSessionCommand(command)) {
        return cli_session.run(args[1..], stderr, stdout);
    }
    if (std.mem.eql(u8, command, "serve")) {
        if (args.len == 3 and std.mem.eql(u8, args[2], "--stdio")) {
            try serve_stdio.serve();
            return 0;
        }
        if (args.len >= 3 and std.mem.eql(u8, args[2], "--unix")) {
            const cfg = try parseServeUnixArgs(args[3..]);
            try serve_unix.serve(cfg);
            return 0;
        }
        if (args.len >= 3 and std.mem.eql(u8, args[2], "--tls")) {
            const cfg = try parseServeTLSArgs(args[3..]);
            try serve_tls.serve(cfg);
            return 0;
        }
        try stderr.print("serve requires exactly one of --stdio, --unix, or --tls\n", .{});
        try stderr.flush();
        return 2;
    }

    try usage(stderr);
    return 2;
}

fn isTopLevelSessionCommand(command: []const u8) bool {
    return std.mem.eql(u8, command, "attach")
        or std.mem.eql(u8, command, "ls")
        or std.mem.eql(u8, command, "list")
        or std.mem.eql(u8, command, "status")
        or std.mem.eql(u8, command, "history")
        or std.mem.eql(u8, command, "kill")
        or std.mem.eql(u8, command, "new");
}

fn usage(stderr: anytype) !void {
    try stderr.print("Usage:\n", .{});
    try stderr.print("  cmuxd-remote version\n", .{});
    try stderr.print("  cmuxd-remote serve --stdio\n", .{});
    try stderr.print("  cmuxd-remote serve --unix --socket <path>\n", .{});
    try stderr.print("  cmuxd-remote serve --tls --listen <addr> --server-id <id> --ticket-secret <secret> --cert-file <path> --key-file <path>\n", .{});
    try stderr.print("  cmuxd-remote cli <command> [args...]\n", .{});
    try stderr.print("  cmuxd-remote session <command> [args...]\n", .{});
    try stderr.print("  cmuxd-remote list|ls [--socket <path>]\n", .{});
    try stderr.print("  cmuxd-remote attach|status|history|kill <name> [--socket <path>]\n", .{});
    try stderr.print("  cmuxd-remote new <name> [--socket <path>] [--detached] [--quiet] [-- <command>]\n", .{});
    try stderr.flush();
}

fn parseServeUnixArgs(args: []const []const u8) !serve_unix.Config {
    var cfg = serve_unix.Config{
        .socket_path = "",
    };

    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const flag = args[idx];
        if (idx + 1 >= args.len) return error.InvalidServeUnixArgs;
        const value = args[idx + 1];

        if (std.mem.eql(u8, flag, "--socket")) {
            cfg.socket_path = value;
        } else {
            return error.InvalidServeUnixArgs;
        }
        idx += 1;
    }

    if (cfg.socket_path.len == 0) return error.InvalidServeUnixArgs;
    return cfg;
}

fn parseServeTLSArgs(args: []const []const u8) !serve_tls.Config {
    var cfg = serve_tls.Config{
        .listen_addr = "",
        .server_id = "",
        .ticket_secret = "",
        .cert_file = "",
        .key_file = "",
    };

    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const flag = args[idx];
        if (idx + 1 >= args.len) return error.InvalidServeTLSArgs;
        const value = args[idx + 1];

        if (std.mem.eql(u8, flag, "--listen")) {
            cfg.listen_addr = value;
        } else if (std.mem.eql(u8, flag, "--server-id")) {
            cfg.server_id = value;
        } else if (std.mem.eql(u8, flag, "--ticket-secret")) {
            cfg.ticket_secret = value;
        } else if (std.mem.eql(u8, flag, "--cert-file")) {
            cfg.cert_file = value;
        } else if (std.mem.eql(u8, flag, "--key-file")) {
            cfg.key_file = value;
        } else {
            return error.InvalidServeTLSArgs;
        }
        idx += 1;
    }

    if (cfg.listen_addr.len == 0 or cfg.server_id.len == 0 or cfg.ticket_secret.len == 0 or cfg.cert_file.len == 0 or cfg.key_file.len == 0) {
        return error.InvalidServeTLSArgs;
    }
    return cfg;
}
