const std = @import("std");
const Node = @import("node.zig");
const TaskID = @import("scheduler.zig").TaskID;

const PendingTrace = struct {};

pub const Trace = struct {
    pub fn init(self: *Trace) void {
        _ = self;
    }

    pub fn deinit(self: *Trace) void {
        _ = self;
    }

    pub fn enterTask(self: *Trace, task_id: TaskID, node: *Node) void {
        _ = self;
        _ = task_id;
        _ = node;
    }

    pub fn leaveTask(self: *Trace) void {
        _ = self;
    }

    pub fn taskSpawned(self: *Trace, task_id: TaskID, node: *Node, parent_id: ?TaskID) void {
        _ = self;
        _ = task_id;
        _ = node;
        _ = parent_id;
    }

    pub fn taskRemoved(self: *Trace, task_id: TaskID, node: *Node) void {
        _ = self;
        _ = task_id;
        _ = node;
    }

    pub fn beginIO(self: *Trace, disk: bool, source: std.builtin.SourceLocation) PendingTrace {
        _ = self;
        _ = disk;
        _ = source;
        return .{};
    }

    pub fn failIO(self: *Trace, pending_trace: PendingTrace, e: anyerror) void {
        _ = self;
        _ = pending_trace;
        _ = e;
    }

    pub fn completeIO(self: *Trace, pending_trace: PendingTrace, result: anytype) void {
        _ = self;
        _ = pending_trace;
        _ = result;
    }
};
