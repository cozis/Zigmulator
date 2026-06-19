const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");
const assertSometimes = Simulator.assertSometimes;

const Winner = enum {
    worker_a,
    worker_b,
};

var winner: ?Winner = null;

fn workerA(init: std.process.Init) anyerror!void {
    if (winner == null)
        winner = .worker_a;

    assertSometimes(winner == .worker_a, @src(), "worker A won the startup race");

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.writeAll("worker A observed the winner\n");
    try stdout.interface.flush();
}

fn workerB(init: std.process.Init) anyerror!void {
    if (winner == null)
        winner = .worker_b;

    assertSometimes(winner == .worker_b, @src(), "worker B won the startup race");

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.writeAll("worker B observed the winner\n");
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    winner = null;

    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("worker_a", workerA);
    try sim.addExecutable("worker_b", workerB);

    try sim.spawn("worker_a", .{});
    try sim.spawn("worker_b", .{});

    while (sim.scheduleOne()) {}
}
