const std = @import("std");

const Interval = struct {
    node: u32, // Stable simulator node identifier. Intervals with the same node are grouped together.
    task: u64, // Stable scheduler task identifier. Each unique node/task pair gets one timeline lane.
    state: []const u8, // Visual state name. Must match one of the keys in the generated `colors` map.
    start: u64, // Inclusive start time of this state interval, in trace units.
    end: u64, // Exclusive end time of this state interval, in trace units.
    reason: []const u8, // Human-readable explanation shown in the hover tooltip.
};

const DiskInterval = struct {
    node: u32,
    op: []const u8,
    start: u64,
    end: u64,
    detail: []const u8,
};

const StateTick = struct {
    node: u32,
    task: u64,
    state: []const u8,
    time: u64,
    reason: []const u8,
};

const Marker = struct {
    time: u64,
    label: []const u8,
};

const TraceEvent = struct {
    time: u64,
    event: []const u8,
    node: ?u32 = null,
    task: ?u64 = null,
    state: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    from: ?u64 = null,
    to: ?u64 = null,
    op: ?[]const u8 = null,
    start: ?u64 = null,
    end: ?u64 = null,
    detail: ?[]const u8 = null,
};

const TaskKey = struct {
    node: u32,
    task: u64,
};

const ActiveState = struct {
    state: []const u8,
    start: u64,
    reason: []const u8,
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
    const arena_alloc = arena.allocator();

    var intervals: std.ArrayList(Interval) = .empty;
    var disk_intervals: std.ArrayList(DiskInterval) = .empty;
    var ticks: std.ArrayList(StateTick) = .empty;
    var markers: std.ArrayList(Marker) = .empty;
    try inferIntervals(arena_alloc, trace_bytes, &intervals, &disk_intervals, &ticks, &markers);

    try writeHtml(writer, intervals.items, disk_intervals.items, ticks.items, markers.items);
}

fn inferIntervals(
    arena: std.mem.Allocator,
    trace_bytes: []const u8,
    intervals: *std.ArrayList(Interval),
    disk_intervals: *std.ArrayList(DiskInterval),
    ticks: *std.ArrayList(StateTick),
    markers: *std.ArrayList(Marker),
) !void {
    _ = markers;
    var active: std.AutoHashMap(TaskKey, ActiveState) = .init(arena);
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
            const state = try arena.dupe(u8, event.state.?);
            const reason = try arena.dupe(u8, event.reason orelse event.state.?);

            if (try active.fetchPut(key, .{ .state = state, .start = event.time, .reason = reason })) |previous_entry| {
                try appendInterval(arena, intervals, ticks, key, previous_entry.value, event.time);
            }
        } else if (std.mem.eql(u8, event.event, "task_removed")) {
            const key = TaskKey{ .node = event.node.?, .task = event.task.? };
            if (active.fetchRemove(key)) |previous_entry| {
                try appendInterval(arena, intervals, ticks, key, previous_entry.value, event.time);
            }
        } else if (std.mem.eql(u8, event.event, "disk")) {
            try disk_intervals.append(arena, .{
                .node = event.node.?,
                .op = try arena.dupe(u8, event.op.?),
                .start = event.start.?,
                .end = event.end.?,
                .detail = try arena.dupe(u8, event.detail orelse ""),
            });
        }
    }

    const final_time = max_time + 1;
    var active_iter = active.iterator();
    while (active_iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const state = entry.value_ptr.*;
        try appendInterval(arena, intervals, ticks, key, state, final_time);
    }
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
            .reason = state.reason,
        });
        return;
    }
    try intervals.append(arena, .{
        .node = key.node,
        .task = key.task,
        .state = state.state,
        .start = state.start,
        .end = interval_end,
        .reason = state.reason,
    });
}

fn writeJsonString(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

fn writeTraceJson(writer: *std.Io.Writer, intervals: []const Interval, disk_intervals: []const DiskInterval, ticks: []const StateTick, markers: []const Marker) !void {
    try writer.writeAll(
        \\{
        \\  unit: "us",
        \\  intervals: [
        \\
    );

    for (intervals, 0..) |interval, index| {
        if (index != 0) try writer.writeAll(",\n");
        try writer.print("    {{ node: {}, task: {}, state: ", .{ interval.node, interval.task });
        try writeJsonString(writer, interval.state);
        try writer.print(", start: {}, end: {}, reason: ", .{ interval.start, interval.end });
        try writeJsonString(writer, interval.reason);
        try writer.writeAll(" }");
    }

    try writer.writeAll(
        \\
        \\  ],
        \\  disk: [
        \\
    );

    for (disk_intervals, 0..) |interval, index| {
        if (index != 0) try writer.writeAll(",\n");
        try writer.print("    {{ node: {}, op: ", .{interval.node});
        try writeJsonString(writer, interval.op);
        try writer.print(", start: {}, end: {}, detail: ", .{ interval.start, interval.end });
        try writeJsonString(writer, interval.detail);
        try writer.writeAll(" }");
    }

    try writer.writeAll(
        \\
        \\  ],
        \\  ticks: [
        \\
    );

    for (ticks, 0..) |tick, index| {
        if (index != 0) try writer.writeAll(",\n");
        try writer.print("    {{ node: {}, task: {}, state: ", .{ tick.node, tick.task });
        try writeJsonString(writer, tick.state);
        try writer.print(", time: {}, reason: ", .{tick.time});
        try writeJsonString(writer, tick.reason);
        try writer.writeAll(" }");
    }

    try writer.writeAll(
        \\
        \\  ],
        \\  markers: [
        \\
    );

    for (markers, 0..) |marker, index| {
        if (index != 0) try writer.writeAll(",\n");
        try writer.print("    {{ time: {}, label: ", .{marker.time});
        try writeJsonString(writer, marker.label);
        try writer.writeAll(" }");
    }

    try writer.writeAll(
        \\
        \\  ],
        \\}
    );
}

fn writeHtml(writer: *std.Io.Writer, intervals: []const Interval, disk_intervals: []const DiskInterval, ticks: []const StateTick, markers: []const Marker) !void {
    try writer.writeAll(
        \\<!doctype html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="utf-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1">
        \\  <title>Zigmulator Task Timeline</title>
        \\  <style>
        \\    :root { color-scheme: light; --bg: #f7f8fb; --panel: #fff; --line: #d9dee8; --line-soft: #edf0f5; --text: #172033; --muted: #61708a; --marker: #111827; }
        \\    * { box-sizing: border-box; }
        \\    body { margin: 0; background: var(--bg); color: var(--text); font: 14px/1.45 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; overflow: hidden; }
        \\    main { height: 100vh; display: grid; grid-template-rows: auto 1fr; min-height: 0; }
        \\    header { background: var(--panel); border-bottom: 1px solid var(--line); padding: 14px 20px; display: flex; gap: 18px; align-items: center; justify-content: space-between; flex-wrap: wrap; }
        \\    h1 { margin: 0; font-size: 18px; font-weight: 650; letter-spacing: 0; }
        \\    .toolbar, .legend { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
        \\    .legend { gap: 12px; color: var(--muted); font-size: 12px; }
        \\    button, select { height: 32px; border: 1px solid var(--line); background: #fff; color: var(--text); border-radius: 6px; padding: 0 10px; font: inherit; }
        \\    button { cursor: pointer; min-width: 34px; }
        \\    .legend-item { display: inline-flex; align-items: center; gap: 5px; white-space: nowrap; }
        \\    .swatch { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
        \\    .shell { min-width: 0; min-height: 0; }
        \\    .timeline-panel { background: var(--panel); border: 0; border-radius: 0; overflow: hidden; height: 100%; display: grid; grid-template-rows: auto 1fr; min-height: 0; }
        \\    .summary { border-bottom: 1px solid var(--line); padding: 10px 14px; display: flex; gap: 16px; color: var(--muted); flex-wrap: wrap; }
        \\    .summary strong { color: var(--text); font-weight: 650; }
        \\    .scroll { overflow: auto; position: relative; min-height: 0; }
        \\    svg { display: block; min-width: 980px; }
        \\    .axis, .lane-label, .marker-label, .bar-label { fill: var(--muted); font-size: 12px; dominant-baseline: middle; }
        \\    .lane-label { fill: var(--text); font-weight: 600; }
        \\    .task-label { fill: var(--muted); font-size: 12px; dominant-baseline: middle; }
        \\    .node-band { fill: #f4f7fb; }
        \\    .node-band.alt { fill: #fff; }
        \\    .node-label-bg { fill: #e8edf5; stroke: #d1d8e5; stroke-width: 1; }
        \\    .node-separator { stroke: #aeb8c8; stroke-width: 1.5; }
        \\    .grid-line { stroke: var(--line-soft); stroke-width: 1; }
        \\    .lane-line { stroke: var(--line); stroke-width: 1; }
        \\    .bar { stroke: rgba(23, 32, 51, 0.22); stroke-width: 1; cursor: pointer; }
        \\    .bar:hover { filter: brightness(0.94); stroke-width: 2; }
        \\    .bar-label { fill: #fff; font-size: 11px; pointer-events: none; font-weight: 650; }
        \\    .marker-line { stroke: var(--marker); stroke-width: 1.5; stroke-dasharray: 4 5; opacity: 0.6; }
        \\    .marker-label { fill: var(--marker); font-size: 11px; }
        \\    .tooltip { position: fixed; z-index: 5; min-width: 240px; max-width: 340px; background: #111827; color: #f9fafb; border-radius: 7px; padding: 10px 12px; box-shadow: 0 12px 30px rgba(0,0,0,.22); pointer-events: none; opacity: 0; transform: translate(10px,10px); transition: opacity 80ms linear; font-size: 12px; }
        \\    .tooltip.visible { opacity: 1; }
        \\    .tooltip-title { font-weight: 700; margin-bottom: 5px; font-size: 13px; }
        \\    .tooltip-row { display: grid; grid-template-columns: 74px 1fr; gap: 10px; color: #d1d5db; }
        \\    .tooltip-row span:last-child { color: #fff; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <main>
        \\    <header>
        \\      <h1>Zigmulator Task Timeline</h1>
        \\      <div class="toolbar">
        \\        <select id="node-filter" aria-label="Node filter"></select>
        \\        <button id="zoom-out" title="Zoom out">-</button>
        \\        <button id="zoom-in" title="Zoom in">+</button>
        \\        <button id="reset" title="Reset zoom">Reset</button>
        \\      </div>
        \\      <div id="legend" class="legend"></div>
        \\    </header>
        \\    <section class="shell">
        \\      <div class="timeline-panel">
        \\        <div id="summary" class="summary"></div>
        \\        <div class="scroll"><svg id="timeline" role="img" aria-label="Task timeline"></svg></div>
        \\      </div>
        \\    </section>
        \\  </main>
        \\  <div id="tooltip" class="tooltip"></div>
        \\  <script>
        \\    const trace =
    );

    try writeTraceJson(writer, intervals, disk_intervals, ticks, markers);

    try writer.writeAll(
        \\;
        \\
        \\    const colors = { running: "#2f855a", ready: "#d69e2e", sleeping: "#3182ce", "waiting-task": "#805ad5", "waiting-futex": "#dd6b20", polling: "#4a5568", returned: "#718096", failed: "#c53030" };
        \\    let zoom = 1;
        \\    let nodeFilter = "all";
        \\    const svg = document.getElementById("timeline");
        \\    const tooltip = document.getElementById("tooltip");
        \\    const nodeSelect = document.getElementById("node-filter");
        \\    const scrollArea = document.querySelector(".scroll");
        \\    const stateLabel = (state) => state.replace("-", " ");
        \\    function make(tag, attrs = {}, text = null) { const el = document.createElementNS("http://www.w3.org/2000/svg", tag); for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, value); if (text !== null) el.textContent = text; return el; }
        \\    function renderLegend() { const legend = document.getElementById("legend"); legend.innerHTML = ""; for (const state of Object.keys(colors)) { const item = document.createElement("span"); item.className = "legend-item"; const swatch = document.createElement("span"); swatch.className = "swatch"; swatch.style.background = colors[state]; item.append(swatch, stateLabel(state)); legend.appendChild(item); } }
        \\    function renderNodeFilter() { const nodes = [...new Set([...trace.intervals.map((item) => item.node), ...trace.ticks.map((item) => item.node)])].sort((a, b) => a - b); nodeSelect.innerHTML = ""; nodeSelect.appendChild(new Option("All nodes", "all")); for (const node of nodes) nodeSelect.appendChild(new Option(`Node ${node}`, String(node))); }
        \\    function selectedIntervals() { return nodeFilter === "all" ? trace.intervals : trace.intervals.filter((item) => String(item.node) === nodeFilter); }
        \\    function selectedTicks() { return nodeFilter === "all" ? trace.ticks : trace.ticks.filter((item) => String(item.node) === nodeFilter); }
        \\    function groupLanesByNode(laneKeys) { const groups = []; for (const key of laneKeys) { const [node] = key.split("/"); const last = groups[groups.length - 1]; if (last && last.node === node) last.keys.push(key); else groups.push({ node, keys: [key] }); } return groups; }
        \\    function showTooltip(event, item) { const title = `node ${item.node} / task ${item.task}`; const kindRow = `<div class="tooltip-row"><span>state</span><span>${stateLabel(item.state)}</span></div>`; const detailRow = `<div class="tooltip-row"><span>reason</span><span>${item.reason}</span></div>`; tooltip.innerHTML = `<div class="tooltip-title">${title}</div>${kindRow}<div class="tooltip-row"><span>time</span><span>${item.start}-${item.end} ${trace.unit}</span></div><div class="tooltip-row"><span>duration</span><span>${item.end - item.start} ${trace.unit}</span></div>${detailRow}`; tooltip.style.left = `${event.clientX}px`; tooltip.style.top = `${event.clientY}px`; tooltip.classList.add("visible"); }
        \\    function hideTooltip() { tooltip.classList.remove("visible"); }
        \\    function renderSummary(intervals, ticks) { const tasks = new Set([...intervals.map((item) => `${item.node}/${item.task}`), ...ticks.map((item) => `${item.node}/${item.task}`)]); const allStarts = [...intervals.map((item) => item.start), ...ticks.map((item) => item.time)]; const allEnds = [...intervals.map((item) => item.end), ...ticks.map((item) => item.time)]; const minTime = Math.min(...allStarts); const maxTime = Math.max(...allEnds); document.getElementById("summary").innerHTML = `<span><strong>${tasks.size}</strong> task lanes</span><span><strong>${intervals.length}</strong> task intervals</span><span><strong>${ticks.length}</strong> instant states</span><span><strong>${maxTime - minTime} ${trace.unit}</strong> span</span><span><strong>${zoom.toFixed(1)}x</strong> zoom</span>`; }
        \\    function render() {
        \\      const intervals = selectedIntervals();
        \\      const ticks = selectedTicks();
        \\      renderSummary(intervals, ticks);
        \\      const margin = { top: 44, right: 28, bottom: 36, left: 160 };
        \\      const laneHeight = 54;
        \\      const barHeight = 20;
        \\      const nodeBadge = { x: 10, width: 82 };
        \\      const nodeBadgeInsetY = 7;
        \\      const taskLabelX = 106;
        \\      const minTime = 0;
        \\      const maxTime = Math.max(...trace.intervals.map((item) => item.end), ...trace.ticks.map((item) => item.time));
        \\      const baseWidth = 1040;
        \\      const plotWidth = Math.round((baseWidth - margin.left - margin.right) * zoom);
        \\      const width = margin.left + plotWidth + margin.right;
        \\      const laneKeys = [...new Set([...intervals.map((item) => `${item.node}/task/${item.task}`), ...ticks.map((item) => `${item.node}/task/${item.task}`)])].sort((a, b) => { const aa = a.split("/"); const bb = b.split("/"); const an = Number(aa[0]); const bn = Number(bb[0]); if (an !== bn) return an - bn; return Number(aa[2] || 0) - Number(bb[2] || 0); });
        \\      const nodeGroups = groupLanesByNode(laneKeys);
        \\      const height = margin.top + laneKeys.length * laneHeight + margin.bottom;
        \\      svg.setAttribute("width", width); svg.setAttribute("height", height); svg.setAttribute("viewBox", `0 0 ${width} ${height}`); svg.innerHTML = "";
        \\      const x = (time) => margin.left + ((time - minTime) / (maxTime - minTime)) * plotWidth;
        \\      const laneY = (key) => margin.top + laneKeys.indexOf(key) * laneHeight;
        \\      nodeGroups.forEach((group, index) => {
        \\        const firstY = laneY(group.keys[0]); const groupHeight = group.keys.length * laneHeight; const bandY = firstY - 4;
        \\        svg.appendChild(make("rect", { x: 0, y: bandY, width, height: groupHeight, class: `node-band${index % 2 === 1 ? " alt" : ""}` }));
        \\        svg.appendChild(make("rect", { x: nodeBadge.x, y: bandY + nodeBadgeInsetY, width: nodeBadge.width, height: groupHeight - nodeBadgeInsetY * 2, rx: 6, class: "node-label-bg" }));
        \\        svg.appendChild(make("text", { x: nodeBadge.x + nodeBadge.width / 2, y: firstY + groupHeight / 2 - 8, "text-anchor": "middle", class: "lane-label" }, `node ${group.node}`));
        \\        const taskCount = group.keys.filter((key) => key.split("/")[1] === "task").length;
        \\        svg.appendChild(make("text", { x: nodeBadge.x + nodeBadge.width / 2, y: firstY + groupHeight / 2 + 8, "text-anchor": "middle", class: "task-label" }, `${taskCount} task${taskCount === 1 ? "" : "s"}`));
        \\        if (index > 0) svg.appendChild(make("line", { x1: 0, y1: bandY, x2: width, y2: bandY, class: "node-separator" }));
        \\      });
        \\      for (let i = 0; i <= 8; i += 1) { const time = Math.round(minTime + ((maxTime - minTime) * i) / 8); const tx = x(time); svg.appendChild(make("line", { x1: tx, y1: margin.top - 18, x2: tx, y2: height - margin.bottom + 8, class: "grid-line" })); svg.appendChild(make("text", { x: tx, y: 20, "text-anchor": "middle", class: "axis" }, `${time}${trace.unit}`)); }
        \\      for (const marker of trace.markers) { const mx = x(marker.time); svg.appendChild(make("line", { x1: mx, y1: margin.top - 8, x2: mx, y2: height - margin.bottom + 4, class: "marker-line" })); svg.appendChild(make("text", { x: mx + 4, y: margin.top - 18, class: "marker-label" }, marker.label)); }
        \\      for (const key of laneKeys) { const y = laneY(key); const parts = key.split("/"); const laneCenterY = y + laneHeight / 2; const label = `task ${parts[2]}`; svg.appendChild(make("line", { x1: taskLabelX - 8, y1: y + laneHeight - 6, x2: width, y2: y + laneHeight - 6, class: "lane-line" })); svg.appendChild(make("text", { x: taskLabelX, y: laneCenterY, class: "task-label" }, label)); }
        \\      for (const item of intervals) { const key = `${item.node}/task/${item.task}`; const y = laneY(key) + (laneHeight - barHeight) / 2; const x1 = x(item.start); const x2 = x(item.end); const rect = make("rect", { x: x1, y, width: Math.max(1, x2 - x1), height: barHeight, rx: 4, fill: colors[item.state], class: "bar" }); rect.addEventListener("mousemove", (event) => showTooltip(event, item)); rect.addEventListener("mouseleave", hideTooltip); svg.appendChild(rect); if (x2 - x1 > 58) svg.appendChild(make("text", { x: x1 + 8, y: y + barHeight / 2 + 1, class: "bar-label" }, stateLabel(item.state))); }
        \\      for (const item of ticks) { const key = `${item.node}/task/${item.task}`; const y = laneY(key) + (laneHeight - barHeight) / 2; const tx = x(item.time); const line = make("line", { x1: tx, y1: y - 3, x2: tx, y2: y + barHeight + 3, stroke: colors[item.state] || "#111827", "stroke-width": 3, "stroke-linecap": "round", class: "bar" }); const tooltipItem = { node: item.node, task: item.task, state: item.state, start: item.time, end: item.time, reason: item.reason }; line.addEventListener("mousemove", (event) => showTooltip(event, tooltipItem)); line.addEventListener("mouseleave", hideTooltip); svg.appendChild(line); }
        \\    }
        \\    function setZoom(nextZoom, anchorClientX = null) { const oldZoom = zoom; zoom = Math.max(0.75, Math.min(16, nextZoom)); if (zoom === oldZoom) return; const rect = scrollArea.getBoundingClientRect(); const anchorX = anchorClientX === null ? rect.left + rect.width / 2 : anchorClientX; const contentX = scrollArea.scrollLeft + anchorX - rect.left; const ratio = contentX / oldZoom; render(); scrollArea.scrollLeft = ratio * zoom - (anchorX - rect.left); }
        \\    document.getElementById("zoom-in").addEventListener("click", () => setZoom(zoom + 0.25));
        \\    document.getElementById("zoom-out").addEventListener("click", () => setZoom(zoom - 0.25));
        \\    scrollArea.addEventListener("wheel", (event) => { if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return; event.preventDefault(); const direction = event.deltaY < 0 ? 1 : -1; setZoom(zoom + direction * 0.2, event.clientX); }, { passive: false });
        \\    document.getElementById("reset").addEventListener("click", () => { zoom = 1; nodeFilter = "all"; nodeSelect.value = "all"; render(); });
        \\    nodeSelect.addEventListener("change", () => { nodeFilter = nodeSelect.value; render(); });
        \\    renderLegend(); renderNodeFilter(); render();
        \\  </script>
        \\</body>
        \\</html>
        \\
    );
}
