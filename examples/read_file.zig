const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn readFileProgram(init: std.process.Init) anyerror!void {
    const created_file = try Io.Dir.cwd().createFile(init.io, "message.txt", .{});
    var writer = created_file.writerStreaming(init.io, &.{});
    try writer.interface.writeAll("hello from the simulated file system");
    try writer.interface.flush();
    created_file.close(init.io);

    const opened_file = try Io.Dir.cwd().openFile(init.io, "message.txt", .{});
    defer opened_file.close(init.io);

    var buffer: [128]u8 = undefined;
    const read_len = try opened_file.readPositionalAll(init.io, &buffer, 0);

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.print("Read: {s}\n", .{buffer[0..read_len]});
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("read_file", readFileProgram);
    try sim.spawn("read_file", .{});

    while (sim.scheduleOne()) {}
}
