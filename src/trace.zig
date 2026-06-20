const std = @import("std");
const Io = std.Io;
const Node = @import("node.zig");
const Scheduler = @import("scheduler.zig");
const TaskID = Scheduler.TaskID;

pub const Trace = struct {
    pub const TaskState = enum {
        ready,
        running,
        sleeping,
        waiting_futex,
        waiting_task,
        failed,
        returned,
        crashed,

        pub fn toString(self: TaskState) []const u8 {
            return switch (self) {
                .ready => "ready",
                .running => "running",
                .sleeping => "sleeping",
                .waiting_futex => "waiting-futex",
                .waiting_task => "waiting-task",
                .failed => "failed",
                .returned => "returned",
                .crashed => "crashed",
            };
        }
    };

    const Pending = struct {
        trace_id: u64,
        start_time: u64,
        global_time: u64,
        node_id: u32,
        task_id: TaskID,
        disk: bool,
        op: []const u8,
    };

    io: Io,
    file: ?Io.File,
    scheduler: *Scheduler,
    task: ?TaskID,
    node: ?*Node,
    next_trace_id: u64,

    pub fn init(self: *Trace, scheduler: *Scheduler, io: Io) void {
        self.io = io;
        self.file = null;
        self.scheduler = scheduler;
        self.task = null;
        self.node = null;
    }

    pub fn deinit(self: *Trace) void {
        if (self.file == null) return;

        self.file.?.close(self.io);
    }

    pub fn setOutputFile(self: *Trace, path: []const u8) !void {
        self.file = try Io.Dir.cwd().createFile(self.io, path, .{});
    }

    pub fn enterTask(self: *Trace, task_id: TaskID, node: *Node) void {
        if (self.file == null) return;

        self.task = task_id;
        self.node = node;
    }

    pub fn leaveTask(self: *Trace) void {
        if (self.file == null) return;

        self.task = null;
        self.node = null;
    }

    pub fn taskSpawned(self: *Trace, task_id: TaskID, node: *Node, parent_id: ?TaskID) void {
        if (self.file == null) return;

        const global_time = self.scheduler.current_time;

        var line_buffer: [256]u8 = undefined;
        const prefix = std.fmt.bufPrint(&line_buffer,
            \\{{"time":{},"global_time":{},"event":"task_spawned","node":{},"task":{}
        , .{ global_time, global_time, node.id, task_id }) catch return;
        self.write(prefix);
        if (parent_id) |it| {
            const parent = std.fmt.bufPrint(&line_buffer, ",\"parent\":{}", .{it}) catch return;
            self.write(parent);
        }
        self.write("}\n");
    }

    pub fn taskRemoved(self: *Trace, task_id: TaskID, node: *Node) void {
        if (self.file == null) return;

        const global_time = self.scheduler.current_time;

        var line_buffer: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buffer,
            \\{{"time":{},"global_time":{},"event":"task_removed","node":{},"task":{}}}
            \\
        , .{ global_time, global_time, node.id, task_id }) catch return;
        self.write(line);
    }

    pub fn taskState(self: *Trace, task_id: TaskID, node: *Node, state: Trace.TaskState, reason: []const u8) void {
        if (self.file == null) return;

        const global_time = self.scheduler.current_time;

        var line_buffer: [256]u8 = undefined;
        const prefix = std.fmt.bufPrint(&line_buffer,
            \\{{"time":{},"global_time":{},"event":"state","node":{},"task":{},"state":
        , .{ global_time, global_time, node.id, task_id }) catch return;
        self.write(prefix);
        self.writeJsonString(state.toString());
        self.write(",\"reason\":");
        self.writeJsonString(reason);
        self.write("}\n");
    }

    pub fn timeAdvanced(self: *Trace, from: u64, to: u64) void {
        if (self.file == null) return;

        var line_buffer: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buffer,
            \\{{"time":{},"global_time":{},"event":"time_advanced","from":{},"to":{}}}
            \\
        , .{ to, to, from, to }) catch return;
        self.write(line);
    }

    pub fn beginIO(self: *Trace, disk: bool, source: std.builtin.SourceLocation) Pending {
        if (self.file == null)
            return .{
                .trace_id = 0,
                .start_time = 0,
                .global_time = 0,
                .task_id = 0,
                .node_id = 0,
                .disk = false,
                .op = &.{},
            };

        std.debug.assert(self.task != null);
        std.debug.assert(self.node != null);
        const node = self.node.?;
        const task = self.task.?;

        const global_time = self.scheduler.current_time;

        const trace_id = self.next_trace_id;
        self.next_trace_id += 1;

        var line_buffer: [256]u8 = undefined;
        const prefix = std.fmt.bufPrint(&line_buffer,
            \\{{"time":{},"global_time":{},"event":"io_start","id":{},"node":{},"task":{},"op":
        , .{ global_time, global_time, trace_id, node.id, task }) catch @panic("TODO");
        self.write(prefix);
        self.writeJsonString(source.fn_name);
        self.write(",\"resource\":");
        self.writeJsonString(if (disk) "disk" else "io");
        self.write("}\n");

        return .{
            .trace_id = trace_id,
            .start_time = global_time,
            .global_time = global_time,
            .node_id = node.id,
            .task_id = task,
            .disk = disk,
            .op = source.fn_name,
        };
    }

    pub fn failIO(self: *Trace, pending_trace: Pending, e: anyerror) void {
        if (self.file == null) return;

        var result_buffer: [96]u8 = undefined;
        const result = std.fmt.bufPrint(&result_buffer, "error.{s}", .{@errorName(e)}) catch "error";
        self.completeIO(pending_trace, result);
    }

    pub fn completeIO(self: *Trace, pending_trace: Pending, result: anytype) void {
        if (self.file == null) return;

        const global_time = self.scheduler.current_time;

        var line_buffer: [256]u8 = undefined;
        const prefix = std.fmt.bufPrint(&line_buffer,
            \\{{"time":{},"global_time":{},"event":"io_complete","id":{},"node":{},"task":{},"op":
        , .{ global_time, global_time, pending_trace.trace_id, pending_trace.node_id, pending_trace.task_id }) catch return;
        self.write(prefix);
        self.writeJsonString(pending_trace.op);
        self.write(",\"resource\":");
        self.writeJsonString(if (pending_trace.disk) "disk" else "io");
        const suffix = std.fmt.bufPrint(&line_buffer,
            \\,"start":{},"end":{},"result":
        , .{ pending_trace.start_time, global_time }) catch return;
        self.write(suffix);
        var result_buffer: [96]u8 = undefined;
        self.writeJsonString(resultText(&result_buffer, result));
        self.write("}\n");

        if (pending_trace.disk) {
            var disk_line_buffer: [256]u8 = undefined;
            const disk_prefix = std.fmt.bufPrint(&disk_line_buffer,
                \\{{"time":{},"global_time":{},"event":"disk","node":{},"op":
            , .{ pending_trace.start_time, global_time, pending_trace.node_id }) catch return;
            self.write(disk_prefix);
            self.writeJsonString(pending_trace.op);
            const middle = std.fmt.bufPrint(&disk_line_buffer,
                \\,"start":{},"end":{},"detail":
            , .{ pending_trace.start_time, global_time }) catch return;
            self.write(middle);
            self.writeJsonString(resultText(&result_buffer, result));
            self.write("}\n");
        }
    }

    fn writeJsonString(self: *Trace, text: []const u8) void {
        self.write("\"");
        for (text) |byte| {
            switch (byte) {
                '"' => self.write("\\\""),
                '\\' => self.write("\\\\"),
                '\n' => self.write("\\n"),
                '\r' => self.write("\\r"),
                '\t' => self.write("\\t"),
                else => self.write((&byte)[0..1]),
            }
        }
        self.write("\"");
    }

    fn write(self: *Trace, bytes: []const u8) void {
        const file = self.file orelse return;
        file.writeStreamingAll(self.io, bytes) catch {};
    }
};

fn resultText(buffer: []u8, result: anytype) []const u8 {
    const T = @TypeOf(result);
    return switch (@typeInfo(T)) {
        .void => "ok",
        .@"struct" => "ok",
        .pointer => |pointer| if (pointer.size == .slice and pointer.child == u8)
            result
        else
            std.fmt.bufPrint(buffer, "{any}", .{result}) catch "result",
        else => std.fmt.bufPrint(buffer, "{}", .{result}) catch "result",
    };
}
