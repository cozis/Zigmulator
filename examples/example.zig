const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");
const assertSometimes = Simulator.assertSometimes;
const reachableSometimes = Simulator.reachableSometimes;

fn programA(init: std.process.Init) anyerror!void {
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    for (0..3) |i| {
        try stdout.interface.print("Hello from program A!\n", .{});
        try stdout.interface.flush();

        // Taken on the last iteration, so it shows up as taken in the report.
        assertSometimes(i == 2, @src(), "program A reached its last iteration");

        // Reaching this line is enough to mark this branch as taken.
        reachableSometimes(@src(), "program A entered its loop body");

        // Never satisfied in this run, so it shows up as missing in the report.
        assertSometimes(i > 100, @src(), "program A looped more than 100 times");
    }
}

fn programB(init: std.process.Init) anyerror!void {
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    for (0..3) |_| {
        try stdout.interface.print("Hello from program B!\n", .{});
        try stdout.interface.flush();
    }
}

fn programC(init: std.process.Init) anyerror!void {
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    for (0..3) |_| {
        try stdout.interface.print("Hello from program C!\n", .{});
        try stdout.interface.flush();
    }
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    // Associate executable names to zig entry functions
    try sim.addExecutable("program_a", programA);
    try sim.addExecutable("program_b", programB);
    try sim.addExecutable("program_c", programC);

    // Now run commands in the form:
    //     program_name arg1 arg2 arg3 ...
    // where program_name is one of the registered functions.
    try sim.spawn("program_a", .{});
    try sim.spawn("program_b", .{});
    try sim.spawn("program_c", .{});

    // Advance the cluster's state by advancing the program's
    // states one by one. Exits when all programs have returned
    // or failed.
    while (sim.scheduleOne()) {}

    std.debug.print("Simulation ended\n", .{});
}
