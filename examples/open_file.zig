const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn createFileProgram(init: std.process.Init) anyerror!void {
    const file = try Io.Dir.cwd().createFile(init.io, "message.txt", .{});

    var writer = file.writerStreaming(init.io, &.{});
    try writer.interface.writeAll("created through dirCreateFile");
    try writer.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("create_file", createFileProgram);
    try sim.spawn("create_file", .{});

    while (sim.scheduleOne()) {}

    sim.dumpFiles();
}
