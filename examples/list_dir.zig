const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn listDirProgram(init: std.process.Init) anyerror!void {
    try Io.Dir.cwd().createDir(init.io, "workspace", .default_dir);

    const workspace = try Io.Dir.cwd().openDir(init.io, "workspace", .{ .iterate = true });
    defer workspace.close(init.io);

    const data_file = try workspace.createFile(init.io, "data.txt", .{});
    data_file.close(init.io);
    try workspace.createDir(init.io, "archive", .default_dir);

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    var iterator = workspace.iterate();
    while (try iterator.next(init.io)) |entry| {
        try stdout.interface.print("{s}: {s}\n", .{ entry.name, @tagName(entry.kind) });
    }
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("list_dir", listDirProgram);
    try sim.spawn("list_dir", .{});

    while (sim.scheduleOne()) {}
}
