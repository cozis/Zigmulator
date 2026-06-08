const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator");

const SelectResult = union(enum) {
    answer: u32,
};

fn computeAnswer() u32 {
    return 42;
}

fn program(init: std.process.Init) anyerror!void {
    var buffer: [1]SelectResult = undefined;
    var select = Io.Select(SelectResult).init(init.io, &buffer);

    // This calls the Io vtable's groupAsync callback.
    select.async(.answer, computeAnswer, .{});

    const result = try select.await();
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});
    try stdout.interface.print("answer: {}\n", .{result.answer});
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.addExecutable("select_group_async", program);
    try sim.spawn("select_group_async", .{});

    while (sim.scheduleOne()) {}
}
