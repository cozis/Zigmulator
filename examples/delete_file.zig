const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn deleteFileProgram(init: std.process.Init) anyerror!void {
    const file = try Io.Dir.cwd().createFile(init.io, "temporary.txt", .{});
    file.close(init.io);

    try Io.Dir.cwd().deleteFile(init.io, "temporary.txt");

    const deleted = Io.Dir.cwd().openFile(init.io, "temporary.txt", .{});
    const message = if (deleted) |opened| message: {
        opened.close(init.io);
        break :message "temporary.txt still exists";
    } else |err| switch (err) {
        error.FileNotFound => "temporary.txt was deleted",
        else => return err,
    };

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.print("{s}\n", .{message});
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io);
    defer sim.deinit();

    try sim.addExecutable("delete_file", deleteFileProgram);
    try sim.spawn("delete_file", .{});

    while (sim.scheduleOne()) {}
}
