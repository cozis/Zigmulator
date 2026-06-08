const std = @import("std");

const PendingTrace = struct {};

pub const Trace = struct {
    pub fn init(self: *Trace) void {
        _ = self;
    }

    pub fn deinit(self: *Trace) void {
        _ = self;
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
