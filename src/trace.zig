const std = @import("std");
const Io = std.Io;
const Node = @import("node.zig");
const TaskID = @import("scheduler.zig").TaskID;

const PendingTrace = struct {};

pub const Trace = struct {

    pub const TaskState = enum {
        ready,
        running,
        sleeping,
        waiting_futex,
        waiting_task,
        failed,
        returned,
    };

    io: Io,
    file: ?Io.File,

    pub fn init(self: *Trace, io: Io) void {
        self.io = io;
        self.file = null;
    }

    pub fn deinit(self: *Trace) void {
        if (self.file == null) return;

        self.file.?.close(self.io);
    }

    pub fn setOutputFile(self: *Trace, path: []const u8) void {
        self.file = try Io.Dir.cwd().createFile(self.io, path, .{});
    }

    pub fn enterTask(self: *Trace, task_id: TaskID, node: *Node) void {
        if (self.file == null) return;

        _ = task_id;
        _ = node;
    }

    pub fn leaveTask(self: *Trace) void {
        if (self.file == null) return;

    }

    pub fn taskSpawned(self: *Trace, task_id: TaskID, node: *Node, parent_id: ?TaskID) void {
        if (self.file == null) return;

        _ = task_id;
        _ = node;
        _ = parent_id;
    }

    pub fn taskRemoved(self: *Trace, task_id: TaskID, node: *Node) void {
        if (self.file == null) return;

        _ = task_id;
        _ = node;
    }

    pub fn taskState(self: *Trace, task_id: TaskID, node: *Node, state: Trace.TaskState, reason: []const u8) void {
        if (self.file == null) return;

        _ = task_id;
        _ = node;
        _ = state;
        _ = reason;
    }

    pub fn timeAdvanced(self: *Trace, from: u64, to: u64) void {
        if (self.file == null) return;

        _ = from;
        _ = to;
    }

    pub fn beginIO(self: *Trace, disk: bool, source: std.builtin.SourceLocation) PendingTrace {
        if (self.file == null) return .{};

        _ = disk;
        _ = source;
        return .{};
    }

    pub fn failIO(self: *Trace, pending_trace: PendingTrace, e: anyerror) void {
        if (self.file == null) return;

        _ = pending_trace;
        _ = e catch {};
    }

    pub fn completeIO(self: *Trace, pending_trace: PendingTrace, result: anytype) void {
        if (self.file == null) return;

        _ = pending_trace;
        _ = result;
    }
};
