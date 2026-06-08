const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

fn deleteDirProgram(init: std.process.Init) anyerror!void {
    try Io.Dir.cwd().createDir(init.io, "scratch", .default_dir);

    const scratch_dir = try Io.Dir.cwd().openDir(init.io, "scratch", .{});
    const file = try scratch_dir.createFile(init.io, "temporary.txt", .{});
    file.close(init.io);

    const non_empty_delete = Io.Dir.cwd().deleteDir(init.io, "scratch");
    const saw_non_empty = if (non_empty_delete) |_| false else |err| switch (err) {
        error.DirNotEmpty => true,
        else => return err,
    };

    try scratch_dir.deleteFile(init.io, "temporary.txt");
    scratch_dir.close(init.io);

    try Io.Dir.cwd().deleteDir(init.io, "scratch");

    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    if (saw_non_empty) {
        try stdout.interface.writeAll("scratch was deleted after emptying it\n");
    } else {
        try stdout.interface.writeAll("scratch delete did not report DirNotEmpty\n");
    }
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("delete_dir", deleteDirProgram);
    try sim.spawn("delete_dir", .{});

    while (sim.scheduleOne()) {}
}
