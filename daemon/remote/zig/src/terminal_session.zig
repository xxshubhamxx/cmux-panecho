const std = @import("std");
const ghostty_vt = @import("ghostty-vt");
const serialize = @import("serialize.zig");

const max_raw_buffer_bytes = 1 << 20;

pub const Options = struct {
    cols: u16,
    rows: u16,
    max_scrollback: usize,
};

pub const RawReadResult = struct {
    data: []u8,
    offset: u64,
    base_offset: u64,
    truncated: bool,
};

pub const OffsetWindow = struct {
    base_offset: u64,
    next_offset: u64,
};

pub const TerminalSession = struct {
    alloc: std.mem.Allocator,
    terminal: *ghostty_vt.Terminal,
    stream: ghostty_vt.ReadonlyStream,
    raw_buffer: std.ArrayList(u8),
    base_offset: u64 = 0,
    next_offset: u64 = 0,

    pub fn init(alloc: std.mem.Allocator, opts: Options) !TerminalSession {
        const terminal = try alloc.create(ghostty_vt.Terminal);
        errdefer alloc.destroy(terminal);

        terminal.* = try ghostty_vt.Terminal.init(alloc, .{
            .cols = opts.cols,
            .rows = opts.rows,
            .max_scrollback = opts.max_scrollback,
        });
        errdefer terminal.deinit(alloc);

        var raw_buffer: std.ArrayList(u8) = .empty;
        try raw_buffer.ensureTotalCapacity(alloc, 4096);

        var session: TerminalSession = .{
            .alloc = alloc,
            .terminal = terminal,
            .stream = undefined,
            .raw_buffer = raw_buffer,
        };
        session.stream = terminal.vtStream();
        return session;
    }

    pub fn deinit(self: *TerminalSession) void {
        self.stream.deinit();
        self.terminal.deinit(self.alloc);
        self.alloc.destroy(self.terminal);
        self.raw_buffer.deinit(self.alloc);
    }

    pub fn feed(self: *TerminalSession, data: []const u8) !void {
        if (data.len == 0) return;

        try self.stream.nextSlice(data);
        try self.raw_buffer.appendSlice(self.alloc, data);
        self.next_offset += data.len;

        if (self.raw_buffer.items.len > max_raw_buffer_bytes) {
            const overflow = self.raw_buffer.items.len - max_raw_buffer_bytes;
            const remaining = self.raw_buffer.items[overflow..];
            std.mem.copyForwards(u8, self.raw_buffer.items[0..remaining.len], remaining);
            self.raw_buffer.items.len = remaining.len;
            self.base_offset += overflow;
        }
    }

    pub fn resize(self: *TerminalSession, cols: u16, rows: u16) !void {
        try self.terminal.resize(self.alloc, cols, rows);
    }

    pub fn snapshot(self: *TerminalSession, alloc: std.mem.Allocator, format: serialize.HistoryFormat) ![]u8 {
        return serialize.serializeTerminal(alloc, self.terminal, format) orelse error.SerializeFailed;
    }

    pub fn history(self: *TerminalSession, alloc: std.mem.Allocator, format: serialize.HistoryFormat) ![]u8 {
        return serialize.serializeTerminal(alloc, self.terminal, format) orelse error.SerializeFailed;
    }

    pub fn offsetWindow(self: *const TerminalSession) OffsetWindow {
        return .{
            .base_offset = self.base_offset,
            .next_offset = self.next_offset,
        };
    }

    pub fn readRaw(self: *TerminalSession, alloc: std.mem.Allocator, offset: u64, max_bytes: usize) !RawReadResult {
        var effective_offset = offset;
        var truncated = false;
        if (effective_offset < self.base_offset) {
            effective_offset = self.base_offset;
            truncated = true;
        }
        if (effective_offset > self.next_offset) {
            effective_offset = self.next_offset;
        }

        const start: usize = @intCast(effective_offset - self.base_offset);
        var end = self.raw_buffer.items.len;
        if (max_bytes > 0 and end > start + max_bytes) {
            end = start + max_bytes;
        }

        return .{
            .data = try alloc.dupe(u8, self.raw_buffer.items[start..end]),
            .offset = effective_offset + (end - start),
            .base_offset = self.base_offset,
            .truncated = truncated,
        };
    }
};

test "feed plain text then snapshot plain returns visible screen" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 10,
        .rows = 4,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    try session.feed("hello\r\nworld\r\n");
    const snapshot = try session.snapshot(std.testing.allocator, .plain);
    defer std.testing.allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "world") != null);
}

test "resize reflows tracked screen state" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 12,
        .rows = 4,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    try session.feed("hello world\r\n");
    try session.resize(5, 4);

    const snapshot = try session.snapshot(std.testing.allocator, .plain);
    defer std.testing.allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "world") != null);
}

test "history plain includes prior scrollback lines" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 8,
        .rows = 2,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    try session.feed("line1\r\nline2\r\nline3\r\n");
    const history = try session.history(std.testing.allocator, .plain);
    defer std.testing.allocator.free(history);

    try std.testing.expect(std.mem.indexOf(u8, history, "line1") != null);
    try std.testing.expect(std.mem.indexOf(u8, history, "line3") != null);
}

test "fragmented utf8 feed preserves visible content" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 16,
        .rows = 4,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    const smile = "\xF0\x9F\x98\x80";
    try session.feed("hi ");
    try session.feed(smile[0..2]);
    try session.feed(smile[2..]);
    try session.feed("\r\n");

    const snapshot = try session.snapshot(std.testing.allocator, .plain);
    defer std.testing.allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "hi ") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, smile) != null);
}

test "fragmented ansi escape feed preserves visible content" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 16,
        .rows = 4,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    try session.feed("\x1b[31");
    try session.feed("mred");
    try session.feed("\x1b[0m\r\n");

    const snapshot = try session.snapshot(std.testing.allocator, .plain);
    defer std.testing.allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "red") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, snapshot, 0x1b) == null);
}

test "raw ring truncates and advances base offset" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 8,
        .rows = 2,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    const chunk = "1234567890";
    var index: usize = 0;
    while (index < max_raw_buffer_bytes + 100) : (index += chunk.len) {
        try session.feed(chunk);
    }

    try std.testing.expect(session.base_offset > 0);
    const read = try session.readRaw(std.testing.allocator, 0, 32);
    defer std.testing.allocator.free(read.data);

    try std.testing.expect(read.truncated);
    try std.testing.expectEqual(session.base_offset, read.base_offset);
}

test "readRaw from midpoint returns exact bytes and offsets" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 16,
        .rows = 4,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    try session.feed("hello\nworld\n");

    const read = try session.readRaw(std.testing.allocator, 6, 5);
    defer std.testing.allocator.free(read.data);

    try std.testing.expectEqualStrings("world", read.data);
    try std.testing.expectEqual(@as(u64, 11), read.offset);
    try std.testing.expectEqual(@as(u64, 0), read.base_offset);
    try std.testing.expect(!read.truncated);
}

test "readRaw after truncation returns the retained prefix and updated offsets" {
    var session = try TerminalSession.init(std.testing.allocator, .{
        .cols = 16,
        .rows = 4,
        .max_scrollback = 1024,
    });
    defer session.deinit();

    const chunk = "abcdefghijklmnopqrstuvwxyz012345";
    var index: usize = 0;
    while (index < max_raw_buffer_bytes + chunk.len) : (index += chunk.len) {
        try session.feed(chunk);
    }

    const read = try session.readRaw(std.testing.allocator, 0, 32);
    defer std.testing.allocator.free(read.data);

    try std.testing.expect(read.truncated);
    try std.testing.expectEqual(session.base_offset, read.base_offset);
    try std.testing.expectEqualStrings(session.raw_buffer.items[0..32], read.data);
    try std.testing.expectEqual(session.base_offset + 32, read.offset);
}

// Adapted from references/zmx/src/util.zig at commit
// 993b0cf6c7e7d384e8cf428e301e5e790e88c6f2.
test "serializeTerminalState excludes synchronized output replay" {
    var term = try ghostty_vt.Terminal.init(std.testing.allocator, .{
        .cols = 80,
        .rows = 24,
    });
    defer term.deinit(std.testing.allocator);

    var stream = term.vtStream();
    defer stream.deinit();

    try stream.nextSlice("\x1b[?2004h");
    try stream.nextSlice("\x1b[?2026h");
    try stream.nextSlice("hello");

    try std.testing.expect(term.modes.get(.bracketed_paste));
    try std.testing.expect(term.modes.get(.synchronized_output));

    const output = serialize.serializeTerminalState(std.testing.allocator, &term) orelse return error.TestUnexpectedNull;
    defer std.testing.allocator.free(output);

    try std.testing.expect(term.modes.get(.synchronized_output));

    var restored = try ghostty_vt.Terminal.init(std.testing.allocator, .{
        .cols = 80,
        .rows = 24,
    });
    defer restored.deinit(std.testing.allocator);

    var restored_stream = restored.vtStream();
    defer restored_stream.deinit();
    try restored_stream.nextSlice(output);

    try std.testing.expect(restored.modes.get(.bracketed_paste));
    try std.testing.expect(!restored.modes.get(.synchronized_output));
}

test "serializeTerminalState round trips visible content" {
    var term = try ghostty_vt.Terminal.init(std.testing.allocator, .{
        .cols = 80,
        .rows = 24,
    });
    defer term.deinit(std.testing.allocator);

    var stream = term.vtStream();
    defer stream.deinit();

    try stream.nextSlice("\x1b[?2004h");
    try stream.nextSlice("hello\r\nworld\r\n");

    const output = serialize.serializeTerminalState(std.testing.allocator, &term) orelse return error.TestUnexpectedNull;
    defer std.testing.allocator.free(output);

    var restored = try ghostty_vt.Terminal.init(std.testing.allocator, .{
        .cols = 80,
        .rows = 24,
    });
    defer restored.deinit(std.testing.allocator);

    var restored_stream = restored.vtStream();
    defer restored_stream.deinit();
    try restored_stream.nextSlice(output);

    try std.testing.expect(restored.modes.get(.bracketed_paste));

    const restored_plain = serialize.serializeTerminal(std.testing.allocator, &restored, .plain) orelse return error.TestUnexpectedNull;
    defer std.testing.allocator.free(restored_plain);

    try std.testing.expect(std.mem.indexOf(u8, restored_plain, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_plain, "world") != null);
}
