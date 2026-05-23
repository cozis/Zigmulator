const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn slowProgram(init: std.process.Init) anyerror!void {
    try Io.sleep(init.io, .fromMilliseconds(20), .awake);

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.writeAll("slow woke after 20ms\n");
    try stdout.interface.flush();
}

fn fastProgram(init: std.process.Init) anyerror!void {
    try Io.sleep(init.io, .fromMilliseconds(5), .awake);

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.writeAll("fast woke after 5ms\n");
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io);
    defer sim.deinit();

    try sim.addExecutable("slow", slowProgram);
    try sim.addExecutable("fast", fastProgram);

    try sim.spawn("slow", .{});
    try sim.spawn("fast", .{});

    while (sim.scheduleOne()) {}
}
