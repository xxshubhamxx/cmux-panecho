const std = @import("std");
const json_rpc = @import("json_rpc.zig");
const outbound_queue = @import("outbound_queue.zig");
const proxy_streams = @import("proxy_streams.zig");
const pty_host = @import("pty_host.zig");
const pty_pump = @import("pty_pump.zig");
const serialize = @import("serialize.zig");
const session_registry = @import("session_registry.zig");
const terminal_session = @import("terminal_session.zig");
pub const workspace_registry = @import("workspace_registry.zig");

/// One client subscription to a terminal session. Pump-driven push events
/// get framed as WebSocket text frames and written to `stream` while
/// `stream_lock` is held to serialize against any RPC response writer
/// running on the connection's reader thread.
pub const TerminalSubscription = struct {
    session_id: []const u8, // borrowed: hashmap key for the runtime
    stream: *std.net.Stream,
    stream_lock: *std.Thread.Mutex,
    /// If set, push frames are enqueued (line-framed) into a per-connection
    /// writer thread. Otherwise the WS sync framing path is used.
    queue: ?*outbound_queue.OutboundQueue = null,
    last_offset: u64,
    seq: u64 = 0,
    dead: std.atomic.Value(bool) = .init(false),
    /// Last bell_count observed when we pushed to this subscriber.
    last_bell_count: u64 = 0,
    /// Last command_seq observed when we pushed to this subscriber.
    last_command_seq: u64 = 0,
    /// Last notification_seq observed when we pushed to this subscriber.
    last_notification_seq: u64 = 0,
    /// Whether we've already delivered an eof=true push to this subscriber.
    /// The dispatch decision ("do we have anything new?") has to include
    /// this, otherwise a PTY that closes after its last byte was pushed
    /// would leave the subscriber hanging on eof=false forever.
    eof_sent: bool = false,
    /// Count of in-flight `deliverTerminalPushes` iterations carrying a
    /// snapshot pointer to this sub. Incremented under `sub_mutex` while
    /// the sub was still live; decremented after the per-sub push
    /// completes. Unsubscribe marks the sub dead, drops it from
    /// `terminal_subs`, releases `sub_mutex`, then spin-waits for this
    /// to hit zero before freeing the allocation. This also keeps
    /// `sub.queue` (which points into the owning Worker's stack frame
    /// in the unix-socket transport) valid for the push duration,
    /// because `Worker.run`'s defer chain calls `unsubscribeAllForStream`
    /// which doesn't return past this wait until no push is in flight.
    in_flight: std.atomic.Value(u32) = .init(0),
};

pub const SubscribeSnapshot = struct {
    data: []u8, // owned
    offset: u64,
    base_offset: u64,
    truncated: bool,
    eof: bool,
    seq: u64,
};

pub const AttachmentResult = struct {
    attachment_id: []const u8,
    cols: u16,
    rows: u16,
};

pub const OpenTerminalResult = struct {
    status: session_registry.SessionStatus,
    attachment_id: []const u8,
    offset: u64,
};

pub const ReadTerminalResult = struct {
    data: []u8,
    offset: u64,
    base_offset: u64,
    truncated: bool,
    eof: bool,
};

const RuntimeSession = struct {
    pty: pty_host.PtyHost,
    terminal: terminal_session.TerminalSession,
    /// Serializes pump-thread access to `pty`/`terminal` against any
    /// foreground caller (read/write/history/resize/deinit).
    lock: std.Thread.Mutex = .{},
    /// Published to the pump via `pty_pump.Entry.in_flight`. The pump
    /// bumps this while it holds pointers into this RuntimeSession and
    /// `unregister` spin-waits for it to hit zero before returning, so
    /// `closeSession` can safely free the struct after unregister.
    pump_in_flight: std.atomic.Value(u32) = .init(0),
    /// True when the pump observed new PTY output while no client was
    /// subscribed. Cleared on terminal.subscribe or session.markRead.
    has_unread_output: std.atomic.Value(bool) = .init(false),
    /// Last counters observed when we dispatched a remote push for this
    /// session. Independent of the subscriber-facing counters so we only
    /// fire once per remote-visible notification event. Only touched while
    /// holding `lock`.
    last_remote_bell_count: u64 = 0,
    last_remote_command_seq: u64 = 0,
    last_remote_notification_seq: u64 = 0,

    fn init(alloc: std.mem.Allocator, command: []const u8, cols: u16, rows: u16) !RuntimeSession {
        return .{
            .pty = try pty_host.PtyHost.init(alloc, command, cols, rows),
            .terminal = try terminal_session.TerminalSession.init(alloc, .{
                .cols = cols,
                .rows = rows,
                .max_scrollback = 100_000,
            }),
        };
    }

    fn deinit(self: *RuntimeSession) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.terminal.deinit();
        self.pty.deinit();
    }

    fn resize(self: *RuntimeSession, cols: u16, rows: u16) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.pty.resize(cols, rows);
        try self.terminal.resize(cols, rows);
    }

    fn read(self: *RuntimeSession, alloc: std.mem.Allocator, offset: u64, max_bytes: usize, timeout_ms: i32) !ReadTerminalResult {
        const start_ms = std.time.milliTimestamp();

        while (true) {
            self.lock.lock();
            try self.pty.pump(&self.terminal);
            const window = self.terminal.offsetWindow();
            var effective_offset = offset;
            const truncated = effective_offset < window.base_offset;
            if (effective_offset < window.base_offset) effective_offset = window.base_offset;

            if (effective_offset < window.next_offset) {
                defer self.lock.unlock();
                const refreshed = self.terminal.offsetWindow();
                const raw = try self.terminal.readRaw(alloc, offset, max_bytes);
                return .{
                    .data = raw.data,
                    .offset = raw.offset,
                    .base_offset = raw.base_offset,
                    .truncated = raw.truncated,
                    .eof = self.pty.isClosed() and raw.offset >= refreshed.next_offset,
                };
            }

            if (self.pty.isClosed()) {
                defer self.lock.unlock();
                return .{
                    .data = try alloc.dupe(u8, ""),
                    .offset = window.next_offset,
                    .base_offset = window.base_offset,
                    .truncated = truncated,
                    .eof = true,
                };
            }
            self.lock.unlock();

            const wait_ms = if (timeout_ms <= 0) -1 else blk: {
                const elapsed = std.time.milliTimestamp() - start_ms;
                const remaining = @as(i64, timeout_ms) - elapsed;
                if (remaining <= 0) return error.ReadTimeout;
                break :blk @as(i32, @intCast(remaining));
            };
            const ready = try self.pty.waitReadable(wait_ms);
            if (!ready) return error.ReadTimeout;
        }
    }

    fn writeDraining(self: *RuntimeSession, data: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.pty.writeDraining(&self.terminal, data);
    }

    fn historyDump(self: *RuntimeSession, alloc: std.mem.Allocator, format: serialize.HistoryFormat) ![]u8 {
        self.lock.lock();
        defer self.lock.unlock();
        try self.pty.pump(&self.terminal);
        return self.terminal.history(alloc, format);
    }
};

/// Remote push config for APNs delivery through an HTTP endpoint (e.g. a
/// Next.js route on Vercel). Populated by the `daemon.configure_notifications`
/// RPC. All fields are owned by the `Service` allocator and protected by
/// `notifications_lock`.
pub const RemoteNotificationConfig = struct {
    endpoint: []const u8 = "",
    bearer_token: []const u8 = "",
    device_tokens: [][]const u8 = &.{},
};

/// Snapshot of notification state for an unread session, handed off to the
/// dispatcher thread. Fields are owned by the allocator that created the job
/// and are freed by `freePushJob` once delivery completes.
const PushJob = struct {
    service: *Service,
    endpoint: []u8,
    bearer_token: []u8,
    device_tokens: [][]u8,
    session_id: []u8,
    workspace_id: ?[]u8,
    bell: bool,
    command_finished: bool,
    exit_code: ?i32,
    notification_present: bool,
    notif_title: ?[]u8,
    notif_body: ?[]u8,
};

pub const Service = struct {
    alloc: std.mem.Allocator,
    proxies: proxy_streams.Manager,
    registry: session_registry.Registry,
    runtimes: std.StringHashMap(*RuntimeSession),
    workspace_reg: workspace_registry.Registry,
    subscriptions: workspace_registry.SubscriptionManager = .{},
    pump: ?pty_pump.Pump = null,
    sub_mutex: std.Thread.Mutex = .{},
    terminal_subs: std.ArrayListUnmanaged(*TerminalSubscription) = .empty,
    /// Optional hook invoked when an unread-state transition occurs so the
    /// transport layer can broadcast workspace.changed. Wired by serve_*.
    on_workspace_changed: ?*const fn (*Service) void = null,
    /// Guards `remote_notifications`.
    notifications_lock: std.Thread.Mutex = .{},
    remote_notifications: RemoteNotificationConfig = .{},
    /// Number of in-flight remote push dispatcher threads. Each thread
    /// increments before spawn and decrements on completion. `deinit`
    /// waits for this to reach zero (signalled via `push_cv`) so detached
    /// threads never outlive the service's allocator / config strings.
    push_inflight: std.atomic.Value(usize) = .init(0),
    push_cv_mutex: std.Thread.Mutex = .{},
    push_cv: std.Thread.Condition = .{},
    push_shutting_down: std.atomic.Value(bool) = .init(false),

    pub fn init(alloc: std.mem.Allocator) Service {
        // NOTE: we intentionally do NOT start the kqueue pump thread here.
        // Zig's result-location semantics do not guarantee that `&service`
        // inside this function equals `&caller_destination` — so a pump
        // thread started here would capture a stale pointer into a local
        // stack slot that is about to be copied and overwritten. Callers
        // must invoke `ensurePumpStarted(&service)` once the Service value
        // is in its final (stable) memory location.
        return .{
            .alloc = alloc,
            .proxies = proxy_streams.Manager.init(alloc),
            .registry = session_registry.Registry.init(alloc),
            .runtimes = std.StringHashMap(*RuntimeSession).init(alloc),
            .workspace_reg = workspace_registry.Registry.init(alloc),
        };
    }

    /// Start the kqueue PTY pump thread and wire up the notify trampoline.
    /// Safe to call multiple times; subsequent calls are no-ops. MUST be
    /// called with `self` at its final memory location — the pump thread
    /// and notify callback capture `self` by pointer.
    pub fn ensurePumpStarted(self: *Service) void {
        if (!pty_pump.supported) return;
        if (self.pump != null) return;
        if (pty_pump.Pump.init(self.alloc)) |pump| {
            self.pump = pump;
            self.pump.?.start() catch |err| {
                std.log.warn("session_service: pump start failed: {s}", .{@errorName(err)});
                self.pump.?.deinit();
                self.pump = null;
                return;
            };
            self.pump.?.setNotify(self, pumpNotifyTrampoline);
        } else |err| {
            std.log.warn("session_service: kqueue pump unavailable: {s}", .{@errorName(err)});
        }
    }

    pub fn deinit(self: *Service) void {
        // Stop the pump first so it cannot touch sessions or subscriptions
        // while we tear them down. The pump is the only producer of new
        // remote-push jobs.
        if (self.pump) |*pump| pump.deinit();
        self.pump = null;

        // Wait for any in-flight remote-push dispatcher threads to finish
        // so they never read the config/allocator after we free them.
        self.push_shutting_down.store(true, .seq_cst);
        self.push_cv_mutex.lock();
        while (self.push_inflight.load(.seq_cst) > 0) {
            self.push_cv.wait(&self.push_cv_mutex);
        }
        self.push_cv_mutex.unlock();

        self.freeRemoteConfigLocked();

        self.sub_mutex.lock();
        for (self.terminal_subs.items) |sub| self.alloc.destroy(sub);
        self.terminal_subs.deinit(self.alloc);
        self.sub_mutex.unlock();

        var iter = self.runtimes.iterator();
        while (iter.next()) |runtime| {
            self.alloc.free(runtime.key_ptr.*);
            runtime.value_ptr.*.deinit();
            self.alloc.destroy(runtime.value_ptr.*);
        }
        self.runtimes.deinit();
        self.proxies.deinit();
        self.registry.deinit();
        self.workspace_reg.deinit();
        self.subscriptions.deinit(self.alloc);
    }

    /// Frees the currently-stored remote notification config and resets it
    /// back to the empty state. Must be called with `notifications_lock`
    /// held OR while no other thread could be reading it (deinit, or a
    /// replace-under-lock path).
    fn freeRemoteConfigLocked(self: *Service) void {
        const cfg = &self.remote_notifications;
        // The initial default uses "" literals and an empty static slice;
        // those aren't allocator-owned but Allocator.free on a zero-length
        // slice is a no-op, so we only need to guard each inner free.
        if (cfg.endpoint.len > 0) self.alloc.free(cfg.endpoint);
        if (cfg.bearer_token.len > 0) self.alloc.free(cfg.bearer_token);
        if (cfg.device_tokens.len > 0) {
            for (cfg.device_tokens) |t| {
                if (t.len > 0) self.alloc.free(t);
            }
            self.alloc.free(cfg.device_tokens);
        }
        cfg.* = .{};
    }

    /// Replace the remote notification config. Internally dupes every
    /// slice so the caller can release / reuse its input buffers. Passing
    /// an empty `endpoint` ("") disables remote pushes entirely; passing
    /// a non-empty endpoint but an empty `device_tokens` slice disables
    /// pushes while retaining the endpoint/token strings (the next
    /// `configureNotifications` call can restore tokens without needing
    /// to send the endpoint again).
    pub fn configureNotifications(
        self: *Service,
        endpoint: []const u8,
        bearer_token: []const u8,
        device_tokens: []const []const u8,
    ) !void {
        const owned_endpoint = try self.alloc.dupe(u8, endpoint);
        errdefer self.alloc.free(owned_endpoint);

        const owned_bearer = try self.alloc.dupe(u8, bearer_token);
        errdefer self.alloc.free(owned_bearer);

        const owned_tokens = try self.alloc.alloc([]const u8, device_tokens.len);
        errdefer self.alloc.free(owned_tokens);

        var allocated: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < allocated) : (i += 1) self.alloc.free(owned_tokens[i]);
        }
        for (device_tokens) |tok| {
            owned_tokens[allocated] = try self.alloc.dupe(u8, tok);
            allocated += 1;
        }

        self.notifications_lock.lock();
        defer self.notifications_lock.unlock();
        self.freeRemoteConfigLocked();
        self.remote_notifications = .{
            .endpoint = owned_endpoint,
            .bearer_token = owned_bearer,
            .device_tokens = owned_tokens,
        };
    }

    pub fn openProxy(self: *Service, host: []const u8, port: u16) ![]const u8 {
        return self.proxies.open(host, port);
    }

    pub fn closeProxy(self: *Service, stream_id: []const u8) !void {
        try self.proxies.close(stream_id);
    }

    pub fn writeProxy(self: *Service, stream_id: []const u8, payload: []const u8) !usize {
        return self.proxies.write(stream_id, payload);
    }

    pub fn readProxy(self: *Service, stream_id: []const u8, max_bytes: usize, timeout_ms: i32) !proxy_streams.ReadResult {
        return self.proxies.read(self.alloc, stream_id, max_bytes, timeout_ms);
    }

    pub fn openSession(self: *Service, maybe_session_id: ?[]const u8) !session_registry.SessionStatus {
        const session_id = try self.registry.ensure(maybe_session_id);
        defer self.alloc.free(session_id);
        return self.registry.status(session_id);
    }

    pub fn closeSession(self: *Service, session_id: []const u8) !void {
        try self.registry.close(session_id);
        self.removeRuntime(session_id);
    }

    pub fn attachSession(self: *Service, session_id: []const u8, attachment_id: []const u8, cols: u16, rows: u16) !session_registry.SessionStatus {
        try self.registry.attach(session_id, attachment_id, cols, rows);
        var status = try self.registry.status(session_id);
        errdefer status.deinit(self.alloc);
        try self.resizeRuntimeIfPresent(&status);
        return status;
    }

    pub fn resizeSession(self: *Service, session_id: []const u8, attachment_id: []const u8, cols: u16, rows: u16) !session_registry.SessionStatus {
        try self.registry.resize(session_id, attachment_id, cols, rows);
        var status = try self.registry.status(session_id);
        errdefer status.deinit(self.alloc);
        try self.resizeRuntimeIfPresent(&status);
        return status;
    }

    pub fn detachSession(self: *Service, session_id: []const u8, attachment_id: []const u8) !session_registry.SessionStatus {
        try self.registry.detach(session_id, attachment_id);
        var status = try self.registry.status(session_id);
        errdefer status.deinit(self.alloc);
        try self.resizeRuntimeIfPresent(&status);
        return status;
    }

    pub fn sessionStatus(self: *Service, session_id: []const u8) !session_registry.SessionStatus {
        return self.registry.status(session_id);
    }

    pub fn listSessions(self: *Service) ![]session_registry.SessionListEntry {
        return self.registry.list();
    }

    pub fn openTerminal(self: *Service, maybe_session_id: ?[]const u8, command: []const u8, cols: u16, rows: u16) !OpenTerminalResult {
        const opened = try self.registry.open(maybe_session_id, cols, rows);
        errdefer {
            self.registry.close(opened.session_id) catch {};
            self.alloc.free(opened.session_id);
            self.alloc.free(opened.attachment_id);
        }

        var status = try self.registry.status(opened.session_id);
        errdefer status.deinit(self.alloc);

        const runtime = try self.alloc.create(RuntimeSession);
        errdefer self.alloc.destroy(runtime);
        runtime.* = try RuntimeSession.init(self.alloc, command, status.effective_cols, status.effective_rows);
        errdefer runtime.deinit();

        try self.runtimes.put(opened.session_id, runtime);

        // Register PTY master fd with the kqueue pump so output drains
        // proactively even when no client is calling terminal.read.
        if (self.pump) |*pump| {
            const entry: pty_pump.Entry = .{
                .pty = &runtime.pty,
                .terminal = &runtime.terminal,
                .lock = &runtime.lock,
                .session_id = opened.session_id,
                .in_flight = &runtime.pump_in_flight,
            };
            pump.register(runtime.pty.master_fd, entry) catch |err| {
                std.log.warn("session_service: pump.register failed: {s}", .{@errorName(err)});
            };
        }

        return .{
            .status = status,
            .attachment_id = opened.attachment_id,
            .offset = 0,
        };
    }

    pub fn readTerminal(self: *Service, session_id: []const u8, offset: u64, max_bytes: usize, timeout_ms: i32) !ReadTerminalResult {
        const runtime = self.runtimes.getPtr(session_id) orelse return error.TerminalSessionNotFound;
        return runtime.*.*.read(self.alloc, offset, max_bytes, timeout_ms);
    }

    pub fn writeTerminal(self: *Service, session_id: []const u8, data: []const u8) !usize {
        const runtime = self.runtimes.getPtr(session_id) orelse return error.TerminalSessionNotFound;
        try runtime.*.*.writeDraining(data);
        return data.len;
    }

    pub fn history(self: *Service, session_id: []const u8, format: serialize.HistoryFormat) ![]u8 {
        const runtime = self.runtimes.getPtr(session_id) orelse return error.TerminalSessionNotFound;
        return runtime.*.*.historyDump(self.alloc, format);
    }

    fn resizeRuntimeIfPresent(self: *Service, status: *const session_registry.SessionStatus) !void {
        const runtime = self.runtimes.getPtr(status.session_id) orelse return;
        // Skip the PTY resize if we don't have a real size yet. This avoids
        // spurious ResizeFailed errors during the bootstrap/restore window
        // when an attachment exists but hasn't reported geometry.
        if (status.effective_cols == 0 or status.effective_rows == 0) return;
        try runtime.*.*.resize(status.effective_cols, status.effective_rows);
    }

    fn removeRuntime(self: *Service, session_id: []const u8) void {
        const removed = self.runtimes.fetchRemove(session_id) orelse return;
        if (self.pump) |*pump| pump.unregister(removed.value.pty.master_fd);
        // Drop any subscriptions pointing at this session_id so their
        // borrowed `session_id` pointer doesn't outlive the hashmap key.
        self.removeSubscriptionsBySessionId(removed.key);
        self.alloc.free(removed.key);
        removed.value.deinit();
        self.alloc.destroy(removed.value);
    }

    /// Atomically: snapshot bytes from `requested_offset` (default = current
    /// next_offset, i.e. no replay) and register `stream` for push events.
    /// Subsequent PTY output is delivered via the `terminal.output` event.
    pub fn subscribeTerminal(
        self: *Service,
        stream: *std.net.Stream,
        stream_lock: *std.Thread.Mutex,
        session_id: []const u8,
        requested_offset: ?u64,
    ) !SubscribeSnapshot {
        return self.subscribeTerminalQueued(stream, stream_lock, null, session_id, requested_offset);
    }

    /// Same as `subscribeTerminal` but routes pushes through a per-connection
    /// outbound queue (used by serve_unix; WS callers pass null).
    pub fn subscribeTerminalQueued(
        self: *Service,
        stream: *std.net.Stream,
        stream_lock: *std.Thread.Mutex,
        queue: ?*outbound_queue.OutboundQueue,
        session_id: []const u8,
        requested_offset: ?u64,
    ) !SubscribeSnapshot {
        const runtime = self.runtimes.get(session_id) orelse return error.TerminalSessionNotFound;
        const key_entry = self.runtimes.getEntry(session_id) orelse return error.TerminalSessionNotFound;
        const canonical_session_id = key_entry.key_ptr.*;

        runtime.lock.lock();
        defer runtime.lock.unlock();

        // Best-effort: drain any pending bytes so the snapshot is fresh.
        runtime.pty.pump(&runtime.terminal) catch {};

        const window = runtime.terminal.offsetWindow();
        const start = requested_offset orelse window.next_offset;

        const max_bytes: usize = 256 * 1024;
        const raw = try runtime.terminal.readRaw(self.alloc, start, max_bytes);
        errdefer self.alloc.free(raw.data);

        const eof_now = runtime.pty.isClosed() and raw.offset >= window.next_offset;

        const sub = try self.alloc.create(TerminalSubscription);
        errdefer self.alloc.destroy(sub);
        sub.* = .{
            .session_id = canonical_session_id,
            .stream = stream,
            .stream_lock = stream_lock,
            .queue = queue,
            .last_offset = raw.offset,
            .seq = 0,
            .last_bell_count = runtime.terminal.bell_count,
            .last_command_seq = runtime.terminal.command_seq,
            .last_notification_seq = runtime.terminal.notification_seq,
        };

        self.sub_mutex.lock();
        self.terminal_subs.append(self.alloc, sub) catch |err| {
            self.sub_mutex.unlock();
            return err;
        };
        self.sub_mutex.unlock();

        // A new subscriber clears any "unread while idle" marker.
        const was_unread = runtime.has_unread_output.swap(false, .seq_cst);
        if (was_unread) self.fireWorkspaceChanged();

        return .{
            .data = raw.data,
            .offset = raw.offset,
            .base_offset = raw.base_offset,
            .truncated = raw.truncated,
            .eof = eof_now,
            .seq = 0,
        };
    }

    /// Clear the has_unread_output flag for `session_id`. Returns true iff
    /// the session exists. Fires on_workspace_changed when the flag
    /// transitioned from true to false so subscribers see the update.
    pub fn markRead(self: *Service, session_id: []const u8) bool {
        const runtime = self.runtimes.get(session_id) orelse return false;
        const was = runtime.has_unread_output.swap(false, .seq_cst);
        if (was) self.fireWorkspaceChanged();
        return true;
    }

    /// Lock-free read of a session's has_unread_output flag. Returns false
    /// when the session is unknown.
    pub fn hasUnread(self: *Service, session_id: []const u8) bool {
        const runtime = self.runtimes.get(session_id) orelse return false;
        return runtime.has_unread_output.load(.seq_cst);
    }

    /// Live count of registered terminal subscribers for a session. Useful
    /// as a deterministic readiness/quiescence signal in tests — callers
    /// can poll for this to drop to zero after a disconnect instead of
    /// sleeping a best-effort interval.
    pub fn subscriberCount(self: *Service, session_id: []const u8) usize {
        self.sub_mutex.lock();
        defer self.sub_mutex.unlock();
        var count: usize = 0;
        for (self.terminal_subs.items) |sub| {
            if (sub.dead.load(.seq_cst)) continue;
            if (std.mem.eql(u8, sub.session_id, session_id)) count += 1;
        }
        return count;
    }

    fn fireWorkspaceChanged(self: *Service) void {
        if (self.on_workspace_changed) |cb| cb(self);
    }

    pub fn unsubscribeTerminal(
        self: *Service,
        stream: *std.net.Stream,
        session_id: []const u8,
    ) bool {
        var target: ?*TerminalSubscription = null;
        self.sub_mutex.lock();
        var i: usize = 0;
        while (i < self.terminal_subs.items.len) : (i += 1) {
            const s = self.terminal_subs.items[i];
            if (s.stream == stream and std.mem.eql(u8, s.session_id, session_id)) {
                s.dead.store(true, .seq_cst);
                _ = self.terminal_subs.orderedRemove(i);
                target = s;
                break;
            }
        }
        self.sub_mutex.unlock();
        if (target) |s| {
            waitUntilQuiescent(s);
            self.alloc.destroy(s);
            return true;
        }
        return false;
    }

    /// Called by the WS handler when a connection closes.
    pub fn unsubscribeAllForStream(self: *Service, stream: *std.net.Stream) void {
        var collected: std.ArrayListUnmanaged(*TerminalSubscription) = .empty;
        defer collected.deinit(self.alloc);

        self.sub_mutex.lock();
        var i: usize = 0;
        while (i < self.terminal_subs.items.len) {
            const s = self.terminal_subs.items[i];
            if (s.stream == stream) {
                s.dead.store(true, .seq_cst);
                _ = self.terminal_subs.orderedRemove(i);
                collected.append(self.alloc, s) catch {};
            } else i += 1;
        }
        self.sub_mutex.unlock();

        for (collected.items) |s| {
            waitUntilQuiescent(s);
            self.alloc.destroy(s);
        }
    }

    fn removeSubscriptionsBySessionId(self: *Service, session_id: []const u8) void {
        var collected: std.ArrayListUnmanaged(*TerminalSubscription) = .empty;
        defer collected.deinit(self.alloc);

        self.sub_mutex.lock();
        var i: usize = 0;
        while (i < self.terminal_subs.items.len) {
            const s = self.terminal_subs.items[i];
            if (std.mem.eql(u8, s.session_id, session_id)) {
                s.dead.store(true, .seq_cst);
                _ = self.terminal_subs.orderedRemove(i);
                collected.append(self.alloc, s) catch {};
            } else i += 1;
        }
        self.sub_mutex.unlock();

        for (collected.items) |s| {
            waitUntilQuiescent(s);
            self.alloc.destroy(s);
        }
    }

    fn pumpNotifyTrampoline(ctx: ?*anyopaque, entry: pty_pump.Entry) void {
        const self: *Service = @ptrCast(@alignCast(ctx orelse return));
        self.deliverTerminalPushes(entry);
    }

    fn deliverTerminalPushes(self: *Service, entry: pty_pump.Entry) void {
        // Snapshot matching subscriber pointers so we don't hold sub_mutex
        // across PTY/terminal locking and network writes. Each snapshot
        // bumps the sub's `in_flight` counter while `sub_mutex` is held;
        // the per-sub loop below decrements it. Unsubscribe waits for
        // that counter to hit zero before freeing the allocation, so
        // the pointer we carry across the sub_mutex release can never
        // dangle.
        var matching: std.ArrayListUnmanaged(*TerminalSubscription) = .empty;
        defer matching.deinit(self.alloc);

        self.sub_mutex.lock();
        for (self.terminal_subs.items) |sub| {
            if (sub.dead.load(.seq_cst)) continue;
            if (std.mem.eql(u8, sub.session_id, entry.session_id)) {
                matching.append(self.alloc, sub) catch break;
                _ = sub.in_flight.fetchAdd(1, .seq_cst);
            }
        }
        self.sub_mutex.unlock();

        if (matching.items.len == 0) {
            // No live subscriber for this session: mark unread so the next
            // workspace.list / workspace.changed reflects it. Notify only on
            // the false→true transition to avoid spamming change events.
            if (self.runtimes.get(entry.session_id)) |runtime| {
                const was = runtime.has_unread_output.swap(true, .seq_cst);
                if (!was) self.fireWorkspaceChanged();
            }
            // If a remote endpoint is configured and an actual notification
            // event fired (bell / command_finished / OSC 99), dispatch an
            // APNs push so the owner still learns about this session.
            self.maybePushRemoteNotification(entry);
            return;
        }

        for (matching.items) |sub| {
            defer _ = sub.in_flight.fetchSub(1, .seq_cst);
            if (sub.dead.load(.seq_cst)) continue;
            self.pushOneSubscriber(entry, sub) catch {
                sub.dead.store(true, .seq_cst);
            };
        }
    }

    /// Spin-wait for a retiring subscription's `in_flight` counter to
    /// drop to zero. Called by `unsubscribeTerminal` and friends after
    /// removing the sub from `terminal_subs` (so no new push can see
    /// it) and before freeing the allocation. Free-standing (not a
    /// method on Service) because it does not need the service itself.
    fn waitUntilQuiescent(sub: *TerminalSubscription) void {
        while (sub.in_flight.load(.seq_cst) > 0) {
            std.atomic.spinLoopHint();
        }
    }

    /// Called from the pump's notify callback when a session just pumped
    /// and has no live subscribers. Dispatches a remote APNs push if the
    /// stored config is non-empty AND a notification-relevant counter
    /// advanced since the last remote push.
    fn maybePushRemoteNotification(self: *Service, entry: pty_pump.Entry) void {
        if (self.push_shutting_down.load(.seq_cst)) return;

        const runtime = self.runtimes.get(entry.session_id) orelse return;

        // Snapshot terminal state + advance per-session remote counters
        // atomically under the runtime lock.
        entry.lock.lock();
        const cur_bell = entry.terminal.bell_count;
        const cur_cmd_seq = entry.terminal.command_seq;
        const cur_notif_seq = entry.terminal.notification_seq;

        const new_bell = cur_bell != runtime.last_remote_bell_count;
        const new_command = cur_cmd_seq != runtime.last_remote_command_seq;
        const new_notification = cur_notif_seq != runtime.last_remote_notification_seq;

        if (!new_bell and !new_command and !new_notification) {
            entry.lock.unlock();
            return;
        }

        const exit_code_snapshot: ?i32 = if (new_command) entry.terminal.last_command_exit_code else null;
        var notif_title_copy: ?[]u8 = null;
        var notif_body_copy: ?[]u8 = null;
        if (new_notification) {
            if (entry.terminal.last_notification) |n| {
                if (n.title) |t| notif_title_copy = self.alloc.dupe(u8, t) catch null;
                if (n.body) |b| notif_body_copy = self.alloc.dupe(u8, b) catch null;
            }
        }

        runtime.last_remote_bell_count = cur_bell;
        runtime.last_remote_command_seq = cur_cmd_seq;
        runtime.last_remote_notification_seq = cur_notif_seq;
        entry.lock.unlock();

        // Must free any borrowed title/body copies if we bail early.
        var free_title: bool = true;
        var free_body: bool = true;
        defer if (free_title) {
            if (notif_title_copy) |t| self.alloc.free(t);
        };
        defer if (free_body) {
            if (notif_body_copy) |b| self.alloc.free(b);
        };

        // Build the push job via a fallible inner helper so we can use
        // `errdefer` for cleanup. The wrapper translates any allocation
        // failure into a silent drop — we already advanced the remote
        // counters, so we won't re-dispatch the same event.
        const maybe_job = self.buildPushJob(
            entry.session_id,
            new_bell,
            new_command,
            exit_code_snapshot,
            new_notification,
            notif_title_copy,
            notif_body_copy,
        ) catch |err| {
            std.log.warn(
                "session_service: build push job failed for {s}: {s}",
                .{ entry.session_id, @errorName(err) },
            );
            return;
        };
        const job = maybe_job orelse return;
        // Ownership of title/body has been transferred into the job.
        free_title = false;
        free_body = false;

        // Increment the in-flight counter BEFORE spawn. If spawn fails,
        // decrement and drop. `pushDispatchEntry` decrements+signals on
        // completion so `deinit` can wait us out.
        _ = self.push_inflight.fetchAdd(1, .seq_cst);
        const thread = std.Thread.spawn(.{}, pushDispatchEntry, .{job}) catch {
            _ = self.push_inflight.fetchSub(1, .seq_cst);
            self.pushCvBroadcast();
            freePushJob(job);
            return;
        };
        thread.detach();
    }

    /// Snapshot the remote notification config + session identity into an
    /// owned `PushJob` that the dispatcher thread can consume. Returns
    /// null when the config is currently empty (callers treat that as a
    /// "nothing to do" result, not an error). Any allocation failure
    /// along the way propagates and is logged by the caller.
    fn buildPushJob(
        self: *Service,
        session_id: []const u8,
        bell: bool,
        command_finished: bool,
        exit_code: ?i32,
        notification_present: bool,
        notif_title_in: ?[]u8,
        notif_body_in: ?[]u8,
    ) !?*PushJob {
        self.notifications_lock.lock();
        defer self.notifications_lock.unlock();

        const cfg = self.remote_notifications;
        if (cfg.endpoint.len == 0 or cfg.device_tokens.len == 0) return null;

        const endpoint_copy = try self.alloc.dupe(u8, cfg.endpoint);
        errdefer self.alloc.free(endpoint_copy);

        const bearer_copy = try self.alloc.dupe(u8, cfg.bearer_token);
        errdefer self.alloc.free(bearer_copy);

        const tokens_copy = try self.alloc.alloc([]u8, cfg.device_tokens.len);
        var tokens_filled: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < tokens_filled) : (i += 1) self.alloc.free(tokens_copy[i]);
            self.alloc.free(tokens_copy);
        }
        for (cfg.device_tokens) |tok| {
            tokens_copy[tokens_filled] = try self.alloc.dupe(u8, tok);
            tokens_filled += 1;
        }

        const session_id_copy = try self.alloc.dupe(u8, session_id);
        errdefer self.alloc.free(session_id_copy);

        const workspace_id_copy: ?[]u8 = self.findWorkspaceIdForSession(session_id);
        errdefer if (workspace_id_copy) |w| self.alloc.free(w);

        const job = try self.alloc.create(PushJob);
        job.* = .{
            .service = self,
            .endpoint = endpoint_copy,
            .bearer_token = bearer_copy,
            .device_tokens = tokens_copy,
            .session_id = session_id_copy,
            .workspace_id = workspace_id_copy,
            .bell = bell,
            .command_finished = command_finished,
            .exit_code = exit_code,
            .notification_present = notification_present,
            .notif_title = notif_title_in,
            .notif_body = notif_body_in,
        };
        return job;
    }

    fn pushCvBroadcast(self: *Service) void {
        self.push_cv_mutex.lock();
        self.push_cv.broadcast();
        self.push_cv_mutex.unlock();
    }

    /// Best-effort reverse lookup from `session_id` to the workspace that
    /// contains it. Returns a newly-allocated owned slice, or null if no
    /// workspace currently references the session (the daemon can still
    /// have a terminal without any workspace binding during bootstrap).
    fn findWorkspaceIdForSession(self: *Service, session_id: []const u8) ?[]u8 {
        const reg = &self.workspace_reg;
        var iter = reg.workspaces.iterator();
        while (iter.next()) |entry| {
            const ws = entry.value_ptr;
            const leaves = ws.root_pane.collectLeaves(self.alloc) catch continue;
            defer self.alloc.free(leaves);
            for (leaves) |leaf| {
                if (leaf.session_id) |sid| {
                    if (std.mem.eql(u8, sid, session_id)) {
                        return self.alloc.dupe(u8, ws.id) catch null;
                    }
                }
            }
        }
        return null;
    }

    fn pushOneSubscriber(self: *Service, entry: pty_pump.Entry, sub: *TerminalSubscription) !void {
        entry.lock.lock();
        const window = entry.terminal.offsetWindow();
        const eof_flag = entry.pty.isClosed();

        // Snapshot notification-related state under lock.
        const cur_bell = entry.terminal.bell_count;
        const cur_cmd_seq = entry.terminal.command_seq;
        const cur_notif_seq = entry.terminal.notification_seq;
        const new_bell = cur_bell != sub.last_bell_count;
        const new_command = cur_cmd_seq != sub.last_command_seq;
        const new_notification = cur_notif_seq != sub.last_notification_seq;

        const exit_code_snapshot: ?i32 = if (new_command) entry.terminal.last_command_exit_code else null;
        var notif_title: ?[]u8 = null;
        var notif_body: ?[]u8 = null;
        if (new_notification) {
            if (entry.terminal.last_notification) |n| {
                if (n.title) |t| notif_title = self.alloc.dupe(u8, t) catch null;
                if (n.body) |b| notif_body = self.alloc.dupe(u8, b) catch null;
            }
        }
        defer if (notif_title) |t| self.alloc.free(t);
        defer if (notif_body) |b| self.alloc.free(b);

        var start = sub.last_offset;
        var truncated = false;
        if (start < window.base_offset) {
            start = window.base_offset;
            truncated = true;
        }
        const has_new_bytes = start < window.next_offset;
        const has_new_notifications = new_bell or new_command or new_notification;
        // Emit exactly one eof=true push after the PTY closes and all
        // bytes have been delivered. Tracked via `sub.eof_sent` so
        // subsequent pumps don't spam empty eof frames.
        const eof_to_announce = eof_flag and !sub.eof_sent and start >= window.next_offset;

        if (!has_new_bytes and !has_new_notifications and !eof_to_announce) {
            entry.lock.unlock();
            return;
        }

        var raw_data_owned: ?[]u8 = null;
        var raw_offset = sub.last_offset;
        var raw_base_offset = window.base_offset;
        var raw_truncated_flag = false;
        if (has_new_bytes) {
            const want = window.next_offset - start;
            const max_chunk: usize = 256 * 1024;
            const take: usize = if (want > max_chunk) max_chunk else @as(usize, @intCast(want));
            const raw = entry.terminal.readRaw(self.alloc, start, take) catch |err| {
                entry.lock.unlock();
                return err;
            };
            raw_data_owned = raw.data;
            raw_offset = raw.offset;
            raw_base_offset = raw.base_offset;
            raw_truncated_flag = raw.truncated;
        }

        sub.last_offset = raw_offset;
        sub.last_bell_count = cur_bell;
        sub.last_command_seq = cur_cmd_seq;
        sub.last_notification_seq = cur_notif_seq;
        sub.seq += 1;
        const seq_now = sub.seq;
        const eof_now = eof_flag and raw_offset >= window.next_offset;
        if (eof_now) sub.eof_sent = true;
        entry.lock.unlock();

        defer if (raw_data_owned) |d| self.alloc.free(d);

        const data_bytes: []const u8 = if (raw_data_owned) |d| d else "";
        const enc_len = std.base64.standard.Encoder.calcSize(data_bytes.len);
        const enc = try self.alloc.alloc(u8, enc_len);
        defer self.alloc.free(enc);
        _ = std.base64.standard.Encoder.encode(enc, data_bytes);

        const NotificationsPayload = struct {
            bell: bool,
            command_finished: ?struct { exit_code: ?i32 },
            notification: ?struct { title: ?[]const u8, body: ?[]const u8 },
        };

        const notifications_payload: ?NotificationsPayload = if (has_new_notifications) .{
            .bell = new_bell,
            .command_finished = if (new_command) .{ .exit_code = exit_code_snapshot } else null,
            .notification = if (new_notification) .{
                .title = if (notif_title) |t| t else null,
                .body = if (notif_body) |b| b else null,
            } else null,
        } else null;

        const event = try json_rpc.encodeResponse(self.alloc, .{
            .event = "terminal.output",
            .seq = seq_now,
            .session_id = sub.session_id,
            .data = enc,
            .offset = raw_offset,
            .base_offset = raw_base_offset,
            .truncated = truncated or raw_truncated_flag,
            .eof = eof_now,
            .notifications = notifications_payload,
        });

        if (sub.queue) |q| {
            // Newline-frame for line-delimited Unix transport. enqueue takes
            // ownership of `line` on success.
            const line = try self.alloc.alloc(u8, event.len + 1);
            @memcpy(line[0..event.len], event);
            line[event.len] = '\n';
            self.alloc.free(event);
            q.enqueueTerminal(line) catch |err| {
                self.alloc.free(line);
                return err;
            };
            return;
        }

        defer self.alloc.free(event);
        sub.stream_lock.lock();
        defer sub.stream_lock.unlock();
        try sendWsTextFrame(sub.stream, event);
    }
};

fn sendWsTextFrame(stream: *std.net.Stream, data: []const u8) !void {
    var header: [10]u8 = undefined;
    header[0] = 0x81; // FIN + text
    var header_len: usize = 2;
    if (data.len <= 125) {
        header[1] = @intCast(data.len);
    } else if (data.len <= 65535) {
        header[1] = 126;
        std.mem.writeInt(u16, header[2..4], @intCast(data.len), .big);
        header_len = 4;
    } else {
        header[1] = 127;
        std.mem.writeInt(u64, header[2..10], @intCast(data.len), .big);
        header_len = 10;
    }
    _ = try stream.write(header[0..header_len]);
    if (data.len > 0) _ = try stream.write(data);
}

fn freePushJob(job: *PushJob) void {
    const alloc = job.service.alloc;
    alloc.free(job.endpoint);
    alloc.free(job.bearer_token);
    for (job.device_tokens) |t| alloc.free(t);
    alloc.free(job.device_tokens);
    alloc.free(job.session_id);
    if (job.workspace_id) |w| alloc.free(w);
    if (job.notif_title) |t| alloc.free(t);
    if (job.notif_body) |b| alloc.free(b);
    alloc.destroy(job);
}

/// Encode the push payload as a single JSON object matching the contract
/// documented in `docs/daemon-push-protocol.md` phase 4.3. Caller owns the
/// returned bytes.
fn encodePushBody(alloc: std.mem.Allocator, job: *const PushJob) ![]u8 {
    const CommandFinished = struct { exit_code: ?i32 };
    const NotificationFields = struct { title: ?[]const u8, body: ?[]const u8 };
    const Notifications = struct {
        bell: bool,
        command_finished: ?CommandFinished,
        notification: ?NotificationFields,
    };

    // Convert the job's owned `[][]u8` tokens into the `[]const []const u8`
    // shape that std.json.Stringify expects for an array-of-strings field.
    const tokens_const = try alloc.alloc([]const u8, job.device_tokens.len);
    defer alloc.free(tokens_const);
    for (job.device_tokens, 0..) |t, i| tokens_const[i] = t;

    const notifications: Notifications = .{
        .bell = job.bell,
        .command_finished = if (job.command_finished) .{ .exit_code = job.exit_code } else null,
        .notification = if (job.notification_present) .{
            .title = if (job.notif_title) |t| t else null,
            .body = if (job.notif_body) |b| b else null,
        } else null,
    };

    const payload = .{
        .device_tokens = tokens_const,
        .session_id = @as([]const u8, job.session_id),
        .workspace_id = if (job.workspace_id) |w| @as(?[]const u8, w) else @as(?[]const u8, null),
        .notifications = notifications,
    };

    var out: std.io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    try std.json.Stringify.value(payload, .{}, &out.writer);
    return try out.toOwnedSlice();
}

/// Detached worker: runs on its own thread, posts the push body, frees
/// the job, decrements the service's in-flight counter, and signals any
/// waiter in `deinit`. Errors are logged and dropped (no retry — the
/// endpoint is responsible for APNs retry).
fn pushDispatchEntry(job: *PushJob) void {
    const service = job.service;
    defer {
        _ = service.push_inflight.fetchSub(1, .seq_cst);
        service.pushCvBroadcast();
    }
    defer freePushJob(job);

    postPushBody(job) catch |err| {
        std.log.warn(
            "session_service: remote push to {s} failed: {s}",
            .{ job.endpoint, @errorName(err) },
        );
    };
}

fn postPushBody(job: *PushJob) !void {
    const alloc = job.service.alloc;
    const body = try encodePushBody(alloc, job);
    defer alloc.free(body);

    // Scheme dispatch:
    //   http://   -> hand-rolled HTTP/1.1 over std.net.Stream (in-process,
    //                no fork, fastest path; see `simpleHttpPost`).
    //   https://  -> shell out to `curl`. zig 0.15.2's std.http.Client
    //                cannot be cleanly time-boxed: its ConnectionPool.resize
    //                helper has a latent compile-time error (DoublyLinkedList
    //                .Node.data) that trips whenever any code path
    //                instantiates it, making the usual std.http path
    //                unbuildable, and std.crypto.tls + root-store loading
    //                is more plumbing than this push path warrants. `curl`
    //                handles both TLS and the 5s timeout via --max-time.
    //                See `curlHttpsPost`.
    //   anything else: log + drop.
    const uri = std.Uri.parse(job.endpoint) catch {
        std.log.warn(
            "session_service: remote push dropped, invalid endpoint URI: {s}",
            .{job.endpoint},
        );
        return error.InvalidUri;
    };
    const scheme = uri.scheme;
    if (std.ascii.eqlIgnoreCase(scheme, "http")) {
        return simpleHttpPost(alloc, job.endpoint, uri, job.bearer_token, body);
    }
    if (std.ascii.eqlIgnoreCase(scheme, "https")) {
        return curlHttpsPost(alloc, job.endpoint, job.bearer_token, body);
    }
    std.log.warn(
        "session_service: remote push dropped, unsupported scheme '{s}' (endpoint={s})",
        .{ scheme, job.endpoint },
    );
    return error.UnsupportedScheme;
}

/// Latched-on first miss so we don't spam logs every push when curl is
/// missing on PATH. HTTPS pushes still get dropped on every attempt; we
/// just stop logging after the first one.
var curl_missing_logged: std.atomic.Value(bool) = .init(false);

/// HTTPS push path: pipe the JSON body to `curl --data-binary @-` and let
/// curl handle TLS, redirects (we don't follow), and the 5s timeout via
/// `--max-time 5`. Stderr is inherited so curl's diagnostics surface in
/// daemon logs in dev. Stdout is discarded; we only care about the exit
/// code (0 on 2xx + transport success).
fn curlHttpsPost(
    alloc: std.mem.Allocator,
    endpoint: []const u8,
    bearer_token: []const u8,
    body: []const u8,
) !void {
    const auth_header = try std.fmt.allocPrint(
        alloc,
        "Authorization: Bearer {s}",
        .{bearer_token},
    );
    defer alloc.free(auth_header);

    const argv = [_][]const u8{
        "curl",
        "-sS",
        "--fail",
        "--max-time",
        "5",
        "-X",
        "POST",
        "-H",
        auth_header,
        "-H",
        "Content-Type: application/json",
        "--data-binary",
        "@-",
        endpoint,
    };

    var child = std.process.Child.init(&argv, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Inherit;

    child.spawn() catch |err| switch (err) {
        error.FileNotFound => {
            const already = curl_missing_logged.swap(true, .seq_cst);
            if (!already) {
                std.log.warn(
                    "session_service: remote push dropped, `curl` not found on PATH; HTTPS pushes will be silently dropped (endpoint={s})",
                    .{endpoint},
                );
            }
            return error.CurlNotFound;
        },
        else => return err,
    };

    // Stream the body in. If curl exits early (e.g. resolution failure),
    // writes hit EPIPE; treat that as a soft error and proceed to wait()
    // so we still observe the real exit code.
    if (child.stdin) |stdin| {
        stdin.writeAll(body) catch |err| {
            std.log.warn(
                "session_service: remote push curl stdin write failed: {s}",
                .{@errorName(err)},
            );
        };
        stdin.close();
        child.stdin = null;
    }

    const term = child.wait() catch |err| {
        std.log.warn(
            "session_service: remote push curl wait failed: {s}",
            .{@errorName(err)},
        );
        return err;
    };

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn(
                    "session_service: remote push to {s} failed, curl exit {d}",
                    .{ endpoint, code },
                );
                return error.RemotePushNon2xx;
            }
        },
        .Signal => |sig| {
            std.log.warn(
                "session_service: remote push to {s} failed, curl killed by signal {d}",
                .{ endpoint, sig },
            );
            return error.RemotePushCurlSignaled;
        },
        else => {
            std.log.warn(
                "session_service: remote push to {s} failed, curl terminated abnormally",
                .{endpoint},
            );
            return error.RemotePushCurlAbnormal;
        },
    }
}

/// Minimal HTTP/1.1 POST helper with a 5-second total timeout. Only handles
/// the path the daemon needs: POST `application/json` + bearer auth, body
/// via Content-Length, status-only response parsing. Plain `http://` only;
/// `https://` is routed through `curlHttpsPost` upstream.
fn simpleHttpPost(
    alloc: std.mem.Allocator,
    endpoint: []const u8,
    uri: std.Uri,
    bearer_token: []const u8,
    body: []const u8,
) !void {
    const host_component = uri.host orelse return error.InvalidUri;
    const host = switch (host_component) {
        .raw => |s| s,
        .percent_encoded => |s| s,
    };
    const port: u16 = uri.port orelse 80;

    var path_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer path_buf.deinit(alloc);
    const path_component = uri.path;
    switch (path_component) {
        .raw => |s| try path_buf.appendSlice(alloc, if (s.len == 0) "/" else s),
        .percent_encoded => |s| try path_buf.appendSlice(alloc, if (s.len == 0) "/" else s),
    }
    if (uri.query) |q| {
        const q_str = switch (q) {
            .raw => |s| s,
            .percent_encoded => |s| s,
        };
        if (q_str.len > 0) {
            try path_buf.append(alloc, '?');
            try path_buf.appendSlice(alloc, q_str);
        }
    }

    const addr_list = try std.net.getAddressList(alloc, host, port);
    defer addr_list.deinit();
    if (addr_list.addrs.len == 0) return error.HostNotFound;

    const stream = try std.net.tcpConnectToAddress(addr_list.addrs[0]);
    defer stream.close();

    // Apply SO_RCVTIMEO / SO_SNDTIMEO = 5s. Both sides of the socket get a
    // deterministic upper bound independent of the HTTP client state.
    const tv = std.posix.timeval{ .sec = 5, .usec = 0 };
    std.posix.setsockopt(
        stream.handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&tv),
    ) catch {};
    std.posix.setsockopt(
        stream.handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.SNDTIMEO,
        std.mem.asBytes(&tv),
    ) catch {};

    const request = try std.fmt.allocPrint(
        alloc,
        "POST {s} HTTP/1.1\r\nHost: {s}\r\nAuthorization: Bearer {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ path_buf.items, host, bearer_token, body.len },
    );
    defer alloc.free(request);

    try writeAll(stream, request);
    try writeAll(stream, body);

    // Read just enough to find the status line; discard the rest.
    var head_buf: [1024]u8 = undefined;
    var total: usize = 0;
    while (total < head_buf.len) {
        const n = stream.read(head_buf[total..]) catch |err| switch (err) {
            error.WouldBlock => return error.RemotePushTimeout,
            else => return err,
        };
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, head_buf[0..total], "\r\n") != null) break;
    }
    if (total == 0) return error.RemotePushEmptyResponse;

    const slice = head_buf[0..total];
    const first_space = std.mem.indexOfScalar(u8, slice, ' ') orelse return error.RemotePushBadResponse;
    const tail = slice[first_space + 1 ..];
    const second_space = std.mem.indexOfScalar(u8, tail, ' ') orelse tail.len;
    const status_str = tail[0..second_space];
    const status = std.fmt.parseInt(u16, status_str, 10) catch return error.RemotePushBadResponse;
    if (status < 200 or status >= 300) {
        std.log.warn(
            "session_service: remote push to {s} returned status {d}",
            .{ endpoint, status },
        );
        return error.RemotePushNon2xx;
    }
}

fn writeAll(stream: std.net.Stream, bytes: []const u8) !void {
    var remaining = bytes;
    while (remaining.len > 0) {
        const n = stream.write(remaining) catch |err| switch (err) {
            error.WouldBlock => return error.RemotePushTimeout,
            else => return err,
        };
        if (n == 0) return error.RemotePushShortWrite;
        remaining = remaining[n..];
    }
}

test "open terminal returns named session when requested" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("dev", "printf READY", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    try std.testing.expectEqualStrings("dev", opened.status.session_id);
    try std.testing.expectEqualStrings("att-1", opened.attachment_id);
}

test "terminal read returns subprocess output" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal(null, "printf READY", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    const read = try service.readTerminal(opened.status.session_id, 0, 32, 1000);
    defer std.testing.allocator.free(read.data);

    try std.testing.expect(std.mem.indexOf(u8, read.data, "READY") != null);
}

test "list sessions retains last known size after final detach" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("dev", "printf READY", 120, 40);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    const initial = try service.listSessions();
    defer {
        for (initial) |*entry| entry.deinit(std.testing.allocator);
        std.testing.allocator.free(initial);
    }

    try std.testing.expectEqual(@as(usize, 1), initial.len);
    try std.testing.expectEqual(@as(usize, 1), initial[0].attachment_count);
    try std.testing.expectEqual(@as(u16, 120), initial[0].effective_cols);
    try std.testing.expectEqual(@as(u16, 40), initial[0].effective_rows);

    var detached = try service.detachSession("dev", opened.attachment_id);
    defer detached.deinit(std.testing.allocator);

    const listed = try service.listSessions();
    defer {
        for (listed) |*entry| entry.deinit(std.testing.allocator);
        std.testing.allocator.free(listed);
    }

    try std.testing.expectEqual(@as(usize, 1), listed.len);
    try std.testing.expectEqual(@as(usize, 0), listed[0].attachment_count);
    try std.testing.expectEqual(@as(u16, 120), listed[0].effective_cols);
    try std.testing.expectEqual(@as(u16, 40), listed[0].effective_rows);
}

test "terminal.subscribe snapshot + pump pushes terminal.output" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal(
        "sub-smoke",
        "printf INITIAL; sleep 0.2; printf LATER",
        80,
        24,
    );
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    // Give the first printf time to land before subscribing so we can verify
    // subscribing at the current offset returns no replay (snap.data empty).
    std.Thread.sleep(80 * std.time.ns_per_ms);

    var fds: [2]std.c.fd_t = undefined;
    if (std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &fds) != 0) {
        return error.SocketPairFailed;
    }
    defer std.posix.close(fds[1]);
    var stream = std.net.Stream{ .handle = fds[0] };
    // Make the read side non-blocking so the polling loop below doesn't wedge.
    const flags = try std.posix.fcntl(fds[1], std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(fds[1], std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));

    var write_mutex: std.Thread.Mutex = .{};

    const snap = try service.subscribeTerminal(&stream, &write_mutex, "sub-smoke", null);
    std.testing.allocator.free(snap.data);

    // Wait until the pump pushes a terminal.output frame containing LATER.
    var buf: [4096]u8 = undefined;
    var accum: std.ArrayListUnmanaged(u8) = .empty;
    defer accum.deinit(std.testing.allocator);

    const deadline = std.time.milliTimestamp() + 3000;
    var got_event = false;
    var got_later = false;
    while (std.time.milliTimestamp() < deadline) {
        const n = std.posix.read(fds[1], &buf) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(15 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
        if (n == 0) break;
        try accum.appendSlice(std.testing.allocator, buf[0..n]);
        if (std.mem.indexOf(u8, accum.items, "\"event\":\"terminal.output\"") != null) {
            got_event = true;
        }
        if (std.mem.indexOf(u8, accum.items, "TEFURVI=") != null or // base64("LATER")
            std.mem.indexOf(u8, accum.items, "TEFURVI") != null)
        {
            got_later = true;
        }
        if (got_event and got_later) break;
    }
    try std.testing.expect(got_event);
    try std.testing.expect(got_later);

    _ = service.unsubscribeTerminal(&stream, "sub-smoke");
}

test "queued terminal.subscribe routes pushes through OutboundQueue" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal(
        "queued-smoke",
        "printf INITIAL; sleep 0.2; printf LATER",
        80,
        24,
    );
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    std.Thread.sleep(80 * std.time.ns_per_ms);

    var fds: [2]std.c.fd_t = undefined;
    if (std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &fds) != 0) {
        return error.SocketPairFailed;
    }
    defer std.posix.close(fds[1]);
    var stream = std.net.Stream{ .handle = fds[0] };
    const flags = try std.posix.fcntl(fds[1], std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(fds[1], std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));

    var queue = outbound_queue.OutboundQueue.init(std.testing.allocator, fds[0]);
    try queue.start();
    defer queue.shutdown();

    var write_mutex: std.Thread.Mutex = .{};
    const snap = try service.subscribeTerminalQueued(&stream, &write_mutex, &queue, "queued-smoke", null);
    std.testing.allocator.free(snap.data);

    var buf: [4096]u8 = undefined;
    var accum: std.ArrayListUnmanaged(u8) = .empty;
    defer accum.deinit(std.testing.allocator);

    const deadline = std.time.milliTimestamp() + 3000;
    var got_event = false;
    var got_later = false;
    var got_newline = false;
    while (std.time.milliTimestamp() < deadline) {
        const n = std.posix.read(fds[1], &buf) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(15 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
        if (n == 0) break;
        try accum.appendSlice(std.testing.allocator, buf[0..n]);
        if (std.mem.indexOf(u8, accum.items, "\"event\":\"terminal.output\"") != null) got_event = true;
        if (std.mem.indexOf(u8, accum.items, "TEFURVI") != null) got_later = true;
        if (std.mem.indexOfScalar(u8, accum.items, '\n') != null) got_newline = true;
        if (got_event and got_later and got_newline) break;
    }
    try std.testing.expect(got_event);
    try std.testing.expect(got_later);
    try std.testing.expect(got_newline);

    _ = service.unsubscribeTerminal(&stream, "queued-smoke");
}

test "kqueue pump drains PTY without explicit read" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();
    service.ensurePumpStarted();

    var opened = try service.openTerminal("pump-smoke", "printf 'hello-from-pump\\n'", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    // Spin briefly waiting for the pump thread to drain output. We never
    // call readTerminal/history; if next_offset grows the pump did its job.
    const runtime_ptr = service.runtimes.get("pump-smoke") orelse return error.MissingRuntime;
    const deadline = std.time.milliTimestamp() + 2000;
    var grew = false;
    while (std.time.milliTimestamp() < deadline) {
        runtime_ptr.lock.lock();
        const window = runtime_ptr.terminal.offsetWindow();
        runtime_ptr.lock.unlock();
        if (window.next_offset > 0) {
            grew = true;
            break;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(grew);
}

test "close session removes terminal runtime" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("dev", "printf READY", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    try service.closeSession("dev");

    try std.testing.expectError(error.SessionNotFound, service.sessionStatus("dev"));
    try std.testing.expectError(error.TerminalSessionNotFound, service.readTerminal("dev", 0, 32, 0));
    try std.testing.expectError(error.TerminalSessionNotFound, service.writeTerminal("dev", "hello"));
    try std.testing.expectError(error.TerminalSessionNotFound, service.history("dev", .plain));
}

test "terminal.output carries notifications:{bell:true} once then null" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("notif-smoke", "sleep 5", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    var fds: [2]std.c.fd_t = undefined;
    if (std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &fds) != 0) {
        return error.SocketPairFailed;
    }
    defer std.posix.close(fds[1]);
    var stream = std.net.Stream{ .handle = fds[0] };
    const flags = try std.posix.fcntl(fds[1], std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(fds[1], std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));

    var write_mutex: std.Thread.Mutex = .{};

    const snap = try service.subscribeTerminal(&stream, &write_mutex, "notif-smoke", null);
    std.testing.allocator.free(snap.data);

    const runtime = service.runtimes.get("notif-smoke") orelse return error.MissingRuntime;
    const entry: pty_pump.Entry = .{
        .pty = &runtime.pty,
        .terminal = &runtime.terminal,
        .lock = &runtime.lock,
        .session_id = "notif-smoke",
        .in_flight = &runtime.pump_in_flight,
    };

    // Inject a BEL + printable byte, so the push has both a notification and new bytes.
    runtime.lock.lock();
    try runtime.terminal.feed("\x07x");
    runtime.lock.unlock();

    service.deliverTerminalPushes(entry);

    var buf: [4096]u8 = undefined;
    var accum: std.ArrayListUnmanaged(u8) = .empty;
    defer accum.deinit(std.testing.allocator);

    const deadline = std.time.milliTimestamp() + 1000;
    while (std.time.milliTimestamp() < deadline) {
        const n = std.posix.read(fds[1], &buf) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(5 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
        if (n == 0) break;
        try accum.appendSlice(std.testing.allocator, buf[0..n]);
        if (std.mem.indexOf(u8, accum.items, "\"bell\":true") != null) break;
    }
    try std.testing.expect(std.mem.indexOf(u8, accum.items, "\"bell\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, accum.items, "\"notifications\":null") == null);

    accum.clearRetainingCapacity();
    runtime.lock.lock();
    try runtime.terminal.feed("y");
    runtime.lock.unlock();

    service.deliverTerminalPushes(entry);

    const deadline2 = std.time.milliTimestamp() + 1000;
    while (std.time.milliTimestamp() < deadline2) {
        const n = std.posix.read(fds[1], &buf) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(5 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
        if (n == 0) break;
        try accum.appendSlice(std.testing.allocator, buf[0..n]);
        if (std.mem.indexOf(u8, accum.items, "\"notifications\":null") != null) break;
    }
    try std.testing.expect(std.mem.indexOf(u8, accum.items, "\"notifications\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, accum.items, "\"bell\":true") == null);

    _ = service.unsubscribeTerminal(&stream, "notif-smoke");
}

test "session has_unread_output flips true when pump fires without subscribers" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("unread-smoke", "printf hi", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    // Wait for the pump to drain output and notify with no subscribers.
    const deadline = std.time.milliTimestamp() + 2000;
    while (std.time.milliTimestamp() < deadline) {
        if (service.hasUnread("unread-smoke")) break;
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(service.hasUnread("unread-smoke"));
}

test "markRead clears has_unread_output" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("markread-smoke", "printf hi", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    const deadline = std.time.milliTimestamp() + 2000;
    while (std.time.milliTimestamp() < deadline) {
        if (service.hasUnread("markread-smoke")) break;
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(service.hasUnread("markread-smoke"));

    try std.testing.expect(service.markRead("markread-smoke"));
    try std.testing.expect(!service.hasUnread("markread-smoke"));
    try std.testing.expect(!service.markRead("no-such-session"));
}

test "subscribeTerminal clears has_unread_output" {
    if (!pty_pump.supported) return error.SkipZigTest;

    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    var opened = try service.openTerminal("sub-clears", "printf hi; sleep 5", 80, 24);
    defer opened.status.deinit(std.testing.allocator);
    defer std.testing.allocator.free(opened.attachment_id);

    const deadline = std.time.milliTimestamp() + 2000;
    while (std.time.milliTimestamp() < deadline) {
        if (service.hasUnread("sub-clears")) break;
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(service.hasUnread("sub-clears"));

    var fds: [2]std.c.fd_t = undefined;
    if (std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &fds) != 0) {
        return error.SocketPairFailed;
    }
    defer std.posix.close(fds[1]);
    var stream = std.net.Stream{ .handle = fds[0] };
    var write_mutex: std.Thread.Mutex = .{};

    const snap = try service.subscribeTerminal(&stream, &write_mutex, "sub-clears", null);
    std.testing.allocator.free(snap.data);

    try std.testing.expect(!service.hasUnread("sub-clears"));

    _ = service.unsubscribeTerminal(&stream, "sub-clears");
}

const RemotePushTestCapture = struct {
    server: *std.net.Server,
    alloc: std.mem.Allocator,
    received: std.ArrayListUnmanaged(u8) = .empty,
    got_request: std.atomic.Value(bool) = .init(false),
    done: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},

    fn run(self: *RemotePushTestCapture) void {
        const conn = self.server.accept() catch {
            self.done.store(true, .seq_cst);
            return;
        };
        defer conn.stream.close();

        var buf: [8192]u8 = undefined;
        var total: usize = 0;
        var saw_headers_end: ?usize = null;
        var content_length: ?usize = null;

        while (total < buf.len) {
            const n = conn.stream.read(buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (saw_headers_end == null) {
                if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n")) |idx| {
                    saw_headers_end = idx + 4;
                    // Parse content-length from the header block.
                    const header_block = buf[0..idx];
                    var it = std.mem.splitSequence(u8, header_block, "\r\n");
                    while (it.next()) |line| {
                        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
                        const name = std.mem.trim(u8, line[0..colon], " ");
                        const value = std.mem.trim(u8, line[colon + 1 ..], " ");
                        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                            content_length = std.fmt.parseInt(usize, value, 10) catch null;
                        }
                    }
                }
            }
            if (saw_headers_end) |hdr_end| {
                if (content_length) |cl| {
                    if (total - hdr_end >= cl) break;
                } else break;
            }
        }

        self.mutex.lock();
        self.received.appendSlice(self.alloc, buf[0..total]) catch {};
        self.mutex.unlock();
        self.got_request.store(true, .seq_cst);

        // Reply with 204 No Content so the daemon sees a 2xx.
        const reply = "HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
        _ = conn.stream.write(reply) catch {};
        self.done.store(true, .seq_cst);
    }
};

test "daemon.configure_notifications + bell with no subscribers POSTs to endpoint" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;

    // Bind a local TCP listener on an ephemeral port.
    const any_addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var server = try any_addr.listen(.{ .reuse_address = true });
    const listen_port = server.listen_address.getPort();

    var capture = RemotePushTestCapture{
        .server = &server,
        .alloc = alloc,
    };
    capture.thread = try std.Thread.spawn(.{}, RemotePushTestCapture.run, .{&capture});

    // Teardown order: close the listener first (unblocks any still-blocked
    // accept() with an error), then join the capture thread, then free
    // buffers. Declaring in reverse here gets us that order.
    defer {
        capture.mutex.lock();
        capture.received.deinit(alloc);
        capture.mutex.unlock();
    }
    defer if (capture.thread) |t| t.join();
    defer server.deinit();

    var service = Service.init(alloc);
    defer service.deinit();

    const endpoint = try std.fmt.allocPrint(
        alloc,
        "http://127.0.0.1:{d}/push",
        .{listen_port},
    );
    defer alloc.free(endpoint);

    const token_a: []const u8 = "abc123";
    const token_b: []const u8 = "deadbeef";
    const tokens = [_][]const u8{ token_a, token_b };

    try service.configureNotifications(endpoint, "shhh-secret", &tokens);

    var opened = try service.openTerminal("remote-smoke", "sleep 5", 80, 24);
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);

    // Inject a BEL byte into the runtime's terminal state machine so
    // bell_count advances. We do NOT subscribe; this is the whole point.
    const runtime = service.runtimes.get("remote-smoke") orelse return error.MissingRuntime;
    runtime.lock.lock();
    try runtime.terminal.feed("\x07");
    runtime.lock.unlock();

    // Simulate the pump's notify callback firing for this session.
    const entry: pty_pump.Entry = .{
        .pty = &runtime.pty,
        .terminal = &runtime.terminal,
        .lock = &runtime.lock,
        .session_id = "remote-smoke",
        .in_flight = &runtime.pump_in_flight,
    };
    service.deliverTerminalPushes(entry);

    // Wait up to 2 seconds for the capture thread to receive the POST.
    const deadline = std.time.milliTimestamp() + 2_000;
    while (std.time.milliTimestamp() < deadline) {
        if (capture.got_request.load(.seq_cst)) break;
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    try std.testing.expect(capture.got_request.load(.seq_cst));

    capture.mutex.lock();
    const got = try alloc.dupe(u8, capture.received.items);
    capture.mutex.unlock();
    defer alloc.free(got);

    // Request line.
    try std.testing.expect(std.mem.indexOf(u8, got, "POST /push HTTP/1.1") != null);
    // Bearer header, case-insensitive match on the header name.
    try std.testing.expect(
        std.mem.indexOf(u8, got, "Authorization: Bearer shhh-secret") != null or
            std.mem.indexOf(u8, got, "authorization: Bearer shhh-secret") != null,
    );
    // Content-Type + body assertions.
    try std.testing.expect(
        std.mem.indexOf(u8, got, "Content-Type: application/json") != null or
            std.mem.indexOf(u8, got, "content-type: application/json") != null,
    );
    try std.testing.expect(std.mem.indexOf(u8, got, "\"session_id\":\"remote-smoke\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "\"bell\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "\"device_tokens\":[\"abc123\",\"deadbeef\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "\"notifications\":") != null);
    // Session has no binding workspace, so workspace_id should be null.
    try std.testing.expect(std.mem.indexOf(u8, got, "\"workspace_id\":null") != null);
}

test "daemon.configure_notifications disables remote push on empty endpoint" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var service = Service.init(alloc);
    defer service.deinit();

    // Start with a valid-looking config, then overwrite with endpoint="".
    const tokens = [_][]const u8{"abcd"};
    try service.configureNotifications("http://127.0.0.1:1/push", "x", &tokens);
    try service.configureNotifications("", "", &[_][]const u8{});

    var opened = try service.openTerminal("disabled-smoke", "sleep 5", 80, 24);
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);

    const runtime = service.runtimes.get("disabled-smoke") orelse return error.MissingRuntime;
    runtime.lock.lock();
    try runtime.terminal.feed("\x07");
    runtime.lock.unlock();

    const entry: pty_pump.Entry = .{
        .pty = &runtime.pty,
        .terminal = &runtime.terminal,
        .lock = &runtime.lock,
        .session_id = "disabled-smoke",
    };
    // Should return fast without spawning a push thread. We can't easily
    // observe "no push" other than the test completing and deinit not
    // blocking on any in-flight dispatcher.
    service.deliverTerminalPushes(entry);

    // Give any (non-)thread time to land before deinit.
    std.Thread.sleep(50 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 0), service.push_inflight.load(.seq_cst));
}

test "https remote push spawns curl, fails fast on unreachable, releases push_inflight" {
    if (!pty_pump.supported) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    var service = Service.init(alloc);
    defer service.deinit();

    // Point at an unreachable HTTPS endpoint. Port 1 is in the IANA
    // reserved range and almost universally closed, so curl gets
    // connection-refused (or fails the TLS handshake) well within
    // --max-time 5 and exits non-zero. We only care that the dispatcher
    // path went through curlHttpsPost (push_inflight bumped) and that
    // the worker thread cleaned up (push_inflight back to zero, deinit
    // doesn't hang).
    const tokens = [_][]const u8{"abcd"};
    try service.configureNotifications(
        "https://127.0.0.1:1/never",
        "shhh-secret",
        &tokens,
    );

    var opened = try service.openTerminal("https-smoke", "sleep 5", 80, 24);
    defer opened.status.deinit(alloc);
    defer alloc.free(opened.attachment_id);

    const runtime = service.runtimes.get("https-smoke") orelse return error.MissingRuntime;
    runtime.lock.lock();
    try runtime.terminal.feed("\x07");
    runtime.lock.unlock();

    const entry: pty_pump.Entry = .{
        .pty = &runtime.pty,
        .terminal = &runtime.terminal,
        .lock = &runtime.lock,
        .session_id = "https-smoke",
    };
    service.deliverTerminalPushes(entry);

    // Wait for the dispatcher worker to finish. Cap at 6s to account for
    // the worst-case curl --max-time 5 plus spawn/wait overhead. Most
    // platforms drop port-1 connection attempts in under a millisecond.
    const deadline = std.time.milliTimestamp() + 6_000;
    while (std.time.milliTimestamp() < deadline) {
        if (service.push_inflight.load(.seq_cst) == 0) break;
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    try std.testing.expectEqual(@as(usize, 0), service.push_inflight.load(.seq_cst));
    return error.SanityTempFailure; // SANITY-temp
}
