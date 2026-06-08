const std = @import("std");

const Interval = struct {
    node: u32,
    task: u64,
    state: []const u8,
    start: u64,
    end: u64,
};

const StateTick = struct {
    node: u32,
    task: u64,
    state: []const u8,
    time: u64,
};

const TraceEvent = struct {
    time: u64,
    event: []const u8,
    node: ?u32 = null,
    task: ?u64 = null,
    state: ?[]const u8 = null,
};

const TaskKey = struct {
    node: u32,
    task: u64,
};

const ActiveState = struct {
    state: []const u8,
    start: u64,
};

pub fn renderFile(io: std.Io, gpa: std.mem.Allocator, trace_path: []const u8, output_path: []const u8, tick_us: u64) !void {
    try validateTickSize(tick_us);

    const file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer file.close(io);

    var writer = file.writerStreaming(io, &.{});
    try render(io, gpa, trace_path, tick_us, &writer.interface);
    try writer.interface.flush();
}

pub fn render(io: std.Io, gpa: std.mem.Allocator, trace_path: []const u8, tick_us: u64, writer: *std.Io.Writer) !void {
    try validateTickSize(tick_us);

    const trace_bytes = try std.Io.Dir.cwd().readFileAlloc(io, trace_path, gpa, .limited(64 * 1024 * 1024));
    defer gpa.free(trace_bytes);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var intervals: std.ArrayList(Interval) = .empty;
    var ticks: std.ArrayList(StateTick) = .empty;
    var lanes: std.ArrayList(TaskKey) = .empty;
    const max_time = try inferIntervals(arena_alloc, trace_bytes, &intervals, &ticks, &lanes);
    sortLanes(lanes.items);

    try writeAscii(gpa, writer, intervals.items, ticks.items, lanes.items, max_time, tick_us);
}

fn validateTickSize(tick_us: u64) !void {
    if (tick_us == 0) return error.InvalidTickSize;
}

fn inferIntervals(
    arena: std.mem.Allocator,
    trace_bytes: []const u8,
    intervals: *std.ArrayList(Interval),
    ticks: *std.ArrayList(StateTick),
    lanes: *std.ArrayList(TaskKey),
) !u64 {
    var active: std.AutoHashMap(TaskKey, ActiveState) = .init(arena);
    var seen_lanes: std.AutoHashMap(TaskKey, void) = .init(arena);
    var max_time: u64 = 0;

    var lines = std.mem.splitScalar(u8, trace_bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        var parsed = try std.json.parseFromSlice(TraceEvent, arena, trimmed, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const event = parsed.value;
        max_time = @max(max_time, event.time);

        if (std.mem.eql(u8, event.event, "state")) {
            const key = TaskKey{ .node = event.node.?, .task = event.task.? };
            try rememberLane(arena, lanes, &seen_lanes, key);

            const state = try arena.dupe(u8, event.state.?);
            if (try active.fetchPut(key, .{ .state = state, .start = event.time })) |previous_entry| {
                try appendInterval(arena, intervals, ticks, key, previous_entry.value, event.time);
            }
        } else if (std.mem.eql(u8, event.event, "task_removed")) {
            const key = TaskKey{ .node = event.node.?, .task = event.task.? };
            try rememberLane(arena, lanes, &seen_lanes, key);

            if (active.fetchRemove(key)) |previous_entry| {
                try appendInterval(arena, intervals, ticks, key, previous_entry.value, event.time);
            }
        }
    }

    const final_time = max_time + 1;
    var active_iter = active.iterator();
    while (active_iter.next()) |entry| {
        try appendInterval(arena, intervals, ticks, entry.key_ptr.*, entry.value_ptr.*, final_time);
    }
    return final_time;
}

fn rememberLane(arena: std.mem.Allocator, lanes: *std.ArrayList(TaskKey), seen_lanes: *std.AutoHashMap(TaskKey, void), key: TaskKey) !void {
    if (seen_lanes.contains(key)) return;
    try seen_lanes.put(key, {});
    try lanes.append(arena, key);
}

fn appendInterval(
    arena: std.mem.Allocator,
    intervals: *std.ArrayList(Interval),
    ticks: *std.ArrayList(StateTick),
    key: TaskKey,
    state: ActiveState,
    end: u64,
) !void {
    var interval_end = end;
    if (state.start == interval_end and (std.mem.eql(u8, state.state, "returned") or std.mem.eql(u8, state.state, "failed"))) {
        interval_end += 1;
    }

    if (state.start >= interval_end) {
        try ticks.append(arena, .{
            .node = key.node,
            .task = key.task,
            .state = state.state,
            .time = state.start,
        });
        return;
    }

    try intervals.append(arena, .{
        .node = key.node,
        .task = key.task,
        .state = state.state,
        .start = state.start,
        .end = interval_end,
    });
}

fn sortLanes(lanes: []TaskKey) void {
    if (lanes.len < 2) return;

    var i: usize = 1;
    while (i < lanes.len) : (i += 1) {
        const current = lanes[i];
        var j = i;
        while (j > 0 and laneLess(current, lanes[j - 1])) : (j -= 1) {
            lanes[j] = lanes[j - 1];
        }
        lanes[j] = current;
    }
}

fn laneLess(a: TaskKey, b: TaskKey) bool {
    if (a.node != b.node) return a.node < b.node;
    return a.task < b.task;
}

fn writeAscii(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    intervals: []const Interval,
    ticks: []const StateTick,
    lanes: []const TaskKey,
    max_time: u64,
    tick_us: u64,
) !void {
    try writer.writeAll("legend: x=running r=ready b=blocked/sleeping w=waiting R=returned f=failed .=idle\n");
    try writer.print("tick: {}us; duplicate rows suppressed\n", .{tick_us});
    try writer.writeAll("columns:\n");
    for (lanes, 0..) |lane, index| {
        try writer.print("  {}: node {} task {}\n", .{ index, lane.node, lane.task });
    }
    try writer.writeAll("\n");

    try writer.writeAll("time_us  | ");
    for (lanes, 0..) |_, index| {
        try writer.writeByte(indexChar(index));
    }
    try writer.writeAll("\n");
    try writer.writeAll("---------+-");
    for (lanes) |_| {
        try writer.writeByte('-');
    }
    try writer.writeAll("\n");

    const previous = try allocator.alloc(u8, lanes.len);
    defer allocator.free(previous);
    const current = try allocator.alloc(u8, lanes.len);
    defer allocator.free(current);
    @memset(previous, 0);

    var have_previous = false;
    var row_start: u64 = 0;
    while (row_start <= max_time) : (row_start += tick_us) {
        const row_end = row_start + tick_us;
        for (lanes, 0..) |lane, index| {
            current[index] = stateAt(intervals, ticks, lane, row_start, row_end);
        }

        if (!have_previous or !std.mem.eql(u8, previous, current)) {
            try writeRow(writer, row_start, current);
            @memcpy(previous, current);
            have_previous = true;
        }
    }
}

fn writeRow(writer: *std.Io.Writer, row_start: u64, states: []const u8) !void {
    try writer.print("{d: >8} | ", .{row_start});
    try writer.writeAll(states);
    try writer.writeAll("\n");
}

fn stateAt(intervals: []const Interval, ticks: []const StateTick, lane: TaskKey, row_start: u64, row_end: u64) u8 {
    for (intervals) |interval| {
        if (interval.node != lane.node or interval.task != lane.task)
            continue;
        if (interval.start < row_end and interval.end > row_start)
            return stateChar(interval.state);
    }

    for (ticks) |tick| {
        if (tick.node == lane.node and tick.task == lane.task and tick.time >= row_start and tick.time < row_end)
            return stateChar(tick.state);
    }

    return '.';
}

fn stateChar(state: []const u8) u8 {
    if (std.mem.eql(u8, state, "running")) return 'x';
    if (std.mem.eql(u8, state, "ready")) return 'r';
    if (std.mem.eql(u8, state, "sleeping") or std.mem.eql(u8, state, "blocked")) return 'b';
    if (std.mem.startsWith(u8, state, "waiting")) return 'w';
    if (std.mem.eql(u8, state, "returned")) return 'R';
    if (std.mem.eql(u8, state, "failed")) return 'f';
    if (std.mem.eql(u8, state, "polling")) return 'p';
    return '?';
}

fn indexChar(index: usize) u8 {
    const alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return alphabet[index % alphabet.len];
}
