const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Simulator = @import("zigmulator");

const server_ip = net.Ip4Address.loopback(8080);
const client_ip = net.Ip4Address{ .bytes = .{ 127, 0, 0, 2 }, .port = 0 };
const server_address: net.IpAddress = .{ .ip4 = server_ip };

fn serverProgram(init: std.process.Init) anyerror!void {
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});

    var server = try server_address.listen(init.io, .{});
    defer server.deinit(init.io);

    var stream = try server.accept(init.io);
    defer stream.close(init.io);

    try stdout.interface.writeAll("server: accepted connection on 127.0.0.1:8080\n");
    try stdout.interface.flush();

    var reader_buffer: [16]u8 = undefined;
    var reader = stream.reader(init.io, &reader_buffer);
    var request: [4]u8 = undefined;
    try reader.interface.readSliceAll(&request);

    try stdout.interface.print("server: received {s}\n", .{&request});
    try stdout.interface.flush();

    var writer_buffer: [16]u8 = undefined;
    var writer = stream.writer(init.io, &writer_buffer);
    try writer.interface.writeAll("pong");
    try writer.interface.flush();
}

fn clientProgram(init: std.process.Init) anyerror!void {
    var stdout = Io.File.stdout().writerStreaming(init.io, &.{});

    var stream = try server_address.connect(init.io, .{ .mode = .stream });
    defer stream.close(init.io);

    var writer_buffer: [16]u8 = undefined;
    var writer = stream.writer(init.io, &writer_buffer);
    try writer.interface.writeAll("ping");
    try writer.interface.flush();

    try stdout.interface.writeAll("client: sent ping\n");
    try stdout.interface.flush();

    // Give the server a deterministic scheduling point to read and respond.
    try Io.sleep(init.io, .fromMilliseconds(1), .awake);

    var reader_buffer: [16]u8 = undefined;
    var reader = stream.reader(init.io, &reader_buffer);
    var response: [4]u8 = undefined;
    try reader.interface.readSliceAll(&response);

    try stdout.interface.print("client: received {s}\n", .{&response});
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    const server_addresses = [_]u32{std.mem.readInt(u32, &server_ip.bytes, .big)};
    const client_addresses = [_]u32{std.mem.readInt(u32, &client_ip.bytes, .big)};

    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, 0);
    defer sim.deinit();

    try sim.setTraceOutputFile("simulation.log");

    try sim.addExecutable("server", serverProgram);
    try sim.addExecutable("client", clientProgram);

    try sim.spawn("server", .{ .addresses = &server_addresses });
    try sim.spawn("client", .{ .addresses = &client_addresses });

    while (sim.scheduleOne()) {}
}
