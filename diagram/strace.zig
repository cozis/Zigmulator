const std = @import("std");

const TraceEvent = struct {
    time: u64,
    event: []const u8,
    id: ?u64 = null,
    node: ?u32 = null,
    task: ?u64 = null,
    op: ?[]const u8 = null,
    resource: ?[]const u8 = null,
    start: ?u64 = null,
    end: ?u64 = null,
    result: ?[]const u8 = null,
};

const Start = struct {
    time: u64,
};

const Operation = struct {
    id: u64,
    start: u64,
    end: u64,
    duration: u64,
    node: u32,
    task: u64,
    op: []const u8,
    resource: []const u8,
    result: []const u8,
};

pub fn renderFile(io: std.Io, gpa: std.mem.Allocator, trace_path: []const u8, output_path: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer file.close(io);

    var writer = file.writerStreaming(io, &.{});
    try render(io, gpa, trace_path, &writer.interface);
    try writer.interface.flush();
}

pub fn render(io: std.Io, gpa: std.mem.Allocator, trace_path: []const u8, writer: *std.Io.Writer) !void {
    const trace_bytes = try std.Io.Dir.cwd().readFileAlloc(io, trace_path, gpa, .limited(64 * 1024 * 1024));
    defer gpa.free(trace_bytes);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var starts: std.AutoHashMap(u64, Start) = .init(arena.allocator());
    var operations: std.ArrayList(Operation) = .empty;

    var lines = std.mem.splitScalar(u8, trace_bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        var parsed = try std.json.parseFromSlice(TraceEvent, arena.allocator(), trimmed, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const event = parsed.value;

        if (std.mem.eql(u8, event.event, "io_start")) {
            try starts.put(event.id.?, .{ .time = event.time });
            continue;
        }

        if (std.mem.eql(u8, event.event, "io_complete")) {
            const start_entry = starts.fetchRemove(event.id.?);
            const start = event.start orelse if (start_entry) |entry| entry.value.time else event.time;
            const end = event.end orelse event.time;

            try operations.append(arena.allocator(), .{
                .id = event.id.?,
                .start = start,
                .end = end,
                .duration = end -| start,
                .node = event.node.?,
                .task = event.task.?,
                .op = try arena.allocator().dupe(u8, event.op orelse ""),
                .resource = try arena.allocator().dupe(u8, event.resource orelse ""),
                .result = try arena.allocator().dupe(u8, event.result orelse ""),
            });
        }
    }

    sortOperations(operations.items);

    for (operations.items) |operation| {
        try writer.print(
            "{d}.{d:0>3} n{d} t{d} {s} = {s}\n",
            .{
                operation.start / 1000,
                operation.start % 1000,
                operation.node,
                operation.task,
                operation.op,
                operation.result,
            },
        );
    }
}

fn sortOperations(operations: []Operation) void {
    if (operations.len < 2) return;

    var i: usize = 1;
    while (i < operations.len) : (i += 1) {
        const current = operations[i];
        var j = i;
        while (j > 0 and operationLess(current, operations[j - 1])) : (j -= 1) {
            operations[j] = operations[j - 1];
        }
        operations[j] = current;
    }
}

fn operationLess(a: Operation, b: Operation) bool {
    if (a.start != b.start) return a.start < b.start;
    return a.id < b.id;
}
