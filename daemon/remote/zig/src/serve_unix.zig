const std = @import("std");
const local_peer_auth = @import("local_peer_auth.zig");
const server_core = @import("server_core.zig");
const session_service = @import("session_service.zig");
const serve_ws = @import("serve_ws.zig");

pub const Config = struct {
    socket_path: []const u8,
    ws_port: ?u16 = null,
    ws_secret: []const u8 = "",
};

pub fn serve(cfg: Config) !void {
    if (cfg.socket_path.len == 0) return error.MissingSocketPath;

    try ensurePrivateSocketDir(cfg.socket_path);
    try removeStaleSocket(cfg.socket_path);

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var shared = SharedService{
        .service = session_service.Service.init(alloc),
    };
    defer shared.service.deinit();

    // Start WebSocket listener on a separate thread if configured
    if (cfg.ws_port) |ws_port| {
        if (cfg.ws_secret.len > 0) {
            const ws_thread = try std.Thread.spawn(.{}, serve_ws.serveShared, .{
                &shared.service,
                ws_port,
                cfg.ws_secret,
            });
            ws_thread.detach();
        }
    }

    const listener_fd = try createSocket(cfg.socket_path);
    defer {
        std.posix.close(listener_fd);
        deleteSocket(cfg.socket_path) catch {};
    }

    while (true) {
        const client_fd = try std.posix.accept(listener_fd, null, null, std.posix.SOCK.CLOEXEC);
        const thread = try std.Thread.spawn(.{}, handleClientThread, .{ &shared, client_fd });
        thread.detach();
    }
}

const SharedService = struct {
    service: session_service.Service,
};

fn handleClientThread(shared: *SharedService, client_fd: std.posix.fd_t) void {
    handleClient(shared, client_fd) catch {};
}

fn handleClient(shared: *SharedService, client_fd: std.posix.fd_t) !void {
    defer std.posix.close(client_fd);
    try local_peer_auth.authorizeClient(client_fd);

    var file = std.fs.File{ .handle = client_fd };
    var output_buf: [64 * 1024]u8 = undefined;
    var output_writer = file.writer(&output_buf);
    const output = &output_writer.interface;

    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(std.heap.page_allocator);

    var read_buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try file.read(&read_buf);
        if (n == 0) break;

        try pending.appendSlice(std.heap.page_allocator, read_buf[0..n]);
        while (std.mem.indexOfScalar(u8, pending.items, '\n')) |newline_index| {
            server_core.handleLine(&shared.service, output, pending.items[0..newline_index]) catch |err| {
                return err;
            };

            const remaining = pending.items[newline_index + 1 ..];
            std.mem.copyForwards(u8, pending.items[0..remaining.len], remaining);
            pending.items.len = remaining.len;
        }
    }

    if (pending.items.len > 0) {
        server_core.handleLine(&shared.service, output, pending.items) catch |err| {
            return err;
        };
    }
}

fn createSocket(socket_path: []const u8) !std.posix.fd_t {
    var unix_addr = try std.net.Address.initUnix(socket_path);
    const listener_fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0);
    errdefer std.posix.close(listener_fd);

    try std.posix.bind(listener_fd, &unix_addr.any, unix_addr.getOsSockLen());
    try chmodPath(socket_path, 0o600);
    try std.posix.listen(listener_fd, 128);
    return listener_fd;
}

fn ensurePrivateSocketDir(socket_path: []const u8) !void {
    const dir_path = std.fs.path.dirname(socket_path) orelse return error.MissingSocketDirectory;
    try ensureDirExists(dir_path);

    const stat = try statPath(dir_path);
    if (stat.kind != .directory) return error.SocketDirectoryNotDirectory;
}

fn ensureDirExists(dir_path: []const u8) !void {
    if (std.fs.path.isAbsolute(dir_path)) {
        var root = try std.fs.openDirAbsolute("/", .{});
        defer root.close();
        const relative = std.mem.trimLeft(u8, dir_path, "/");
        if (relative.len > 0) try root.makePath(relative);
    } else {
        try std.fs.cwd().makePath(dir_path);
    }
}

fn removeStaleSocket(socket_path: []const u8) !void {
    const stat = statPath(socket_path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    if (stat.kind != .unix_domain_socket) return error.SocketPathOccupied;
    try deleteSocket(socket_path);
}

fn statPath(path: []const u8) !std.fs.File.Stat {
    if (std.fs.path.isAbsolute(path)) {
        const dir_path = std.fs.path.dirname(path) orelse return error.FileNotFound;
        const base = std.fs.path.basename(path);
        var dir = try std.fs.openDirAbsolute(dir_path, .{});
        defer dir.close();
        return dir.statFile(base);
    }
    return std.fs.cwd().statFile(path);
}

fn deleteSocket(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) return std.fs.deleteFileAbsolute(path);
    return std.fs.cwd().deleteFile(path);
}

fn chmodPath(path: []const u8, mode: std.posix.mode_t) !void {
    if (std.fs.path.isAbsolute(path)) {
        const dir_path = std.fs.path.dirname(path) orelse return error.FileNotFound;
        const base = std.fs.path.basename(path);
        var dir = try std.fs.openDirAbsolute(dir_path, .{});
        defer dir.close();
        return std.posix.fchmodat(dir.fd, base, mode, 0);
    }
    return std.posix.fchmodat(std.fs.cwd().fd, path, mode, 0);
}
