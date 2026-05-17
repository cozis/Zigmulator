const std = @import("std");
const Io = std.Io;

const Simulator = @import("simulator.zig");

fn programA(init: std.process.Init) anyerror!void {
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    for (0..3) |_| {
        try stdout.interface.print("Hello from program A!\n", .{});
        try stdout.interface.flush();
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
    sim.init(std.heap.page_allocator, init.io);
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
