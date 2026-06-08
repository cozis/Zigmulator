const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn directoriesProgram(init: std.process.Init) anyerror!void {
    try Io.Dir.cwd().createDir(init.io, "logs", .default_dir);

    const logs_dir = try Io.Dir.cwd().openDir(init.io, "logs", .{});
    defer logs_dir.close(init.io);

    const created_file = try logs_dir.createFile(init.io, "message.txt", .{});
    var writer = created_file.writerStreaming(init.io, &.{});
    try writer.interface.writeAll("created inside an opened directory");
    try writer.interface.flush();
    created_file.close(init.io);

    const opened_file = try logs_dir.openFile(init.io, "message.txt", .{});
    defer opened_file.close(init.io);

    var buffer: [128]u8 = undefined;
    const read_len = try opened_file.readPositionalAll(init.io, &buffer, 0);

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.print("logs/message.txt: {s}\n", .{buffer[0..read_len]});
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("directories", directoriesProgram);
    try sim.spawn("directories", .{});

    while (sim.scheduleOne()) {}
}
