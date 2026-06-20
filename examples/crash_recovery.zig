const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");
const assertSometimes = Simulator.assertSometimes;
const reachableSometimes = Simulator.reachableSometimes;

// Each worker is a long-running process that never exits on its own: the
// simulator's automatic crash-fault injector is what stops and restarts it.
//
// A per-node counter file persists across crashes (the file system is durable
// node state, not part of the volatile runtime that is torn down on crash), so
// by reading it on startup a worker can tell a cold start from a restart and
// count how many times it has come back. The "sometimes" assertions then
// confirm that crashes and restarts actually happen and that durable state
// survives them. Coverage of every site means the crash/restart path works.

const runs_path = "runs.bin";

fn readRunCount(io: std.Io) u32 {
    const file = Io.Dir.cwd().openFile(io, runs_path, .{}) catch return 0;
    defer file.close(io);
    var buffer: [4]u8 = undefined;
    const n = file.readPositionalAll(io, &buffer, 0) catch return 0;
    if (n < buffer.len) return 0;
    return std.mem.readInt(u32, &buffer, .little);
}

// Updates the counter crash-safely: write a fresh temp file, then atomically
// rename it over the real one. Rewriting in place instead would truncate the
// file first, so a crash mid-write could reset the counter to nothing.
fn writeRunCount(io: std.Io, count: u32) void {
    const tmp_path = "runs.tmp";
    {
        const file = Io.Dir.cwd().createFile(io, tmp_path, .{}) catch return;
        defer file.close(io);
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, count, .little);
        _ = file.writePositional(io, &.{buffer[0..]}, 0) catch return;
    }
    Io.Dir.cwd().rename(tmp_path, Io.Dir.cwd(), runs_path, io) catch return;
}

fn worker(init: std.process.Init) anyerror!void {
    const io = init.io;

    const previous_runs = readRunCount(io);
    if (previous_runs == 0) {
        reachableSometimes(@src(), "worker cold start");
    } else {
        // Reaching here at all proves the node was restarted after a crash and
        // that its durable state (the counter file) survived the crash.
        reachableSometimes(@src(), "worker restarted after crash");
    }
    assertSometimes(previous_runs >= 2, @src(), "worker survived multiple restarts");
    writeRunCount(io, previous_runs + 1);

    // Long-running work loop. Only a crash ends it.
    while (true) {
        try Io.sleep(io, .fromMilliseconds(10), .awake);
        reachableSometimes(@src(), "worker made progress between crashes");
    }
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.setTraceOutputFile("crash_recovery.log");

    try sim.addExecutable("worker", worker);

    // A few independent workers. Even a single one keeps going: when every node
    // is crashed, the simulator advances the clock to the injector's next step
    // and restarts one, so the run never stalls for lack of a live node.
    for (0..3) |_|
        try sim.spawn("worker", .{});

    // Faults (including the automatic crash/restart injector) are on by default.
    // Run for a bounded number of steps so many crash/restart cycles happen.
    var steps: usize = 0;
    while (steps < 100_000 and sim.scheduleOne()) : (steps += 1) {}

    sim.reportSometimes();
    if (!sim.sometimesCovered())
        return error.CrashRestartNotExercised;
}
