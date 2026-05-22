const std = @import("std");

const Simulator = @import("simulator.zig");

const Io = std.Io;
const Clock = Io.Clock;

fn testClockGrowsMonotonically(init: std.process.Init) anyerror!void {
    const io = init.io;

    const t1 = Clock.boot.now(io);
    const t2 = Clock.boot.now(io);
    try std.testing.expect(t1.nanoseconds <= t2.nanoseconds);

    const t3 = Clock.boot.now(io);
    try std.testing.expect(t2.nanoseconds <= t3.nanoseconds);
}

test "clock grows monotonically" {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, std.Options.debug_io);
    defer sim.deinit();

    try sim.addExecutable("program_a", testClockGrowsMonotonically);
    try sim.spawn("program_a", .{});

    while (sim.scheduleOne()) {}
}
