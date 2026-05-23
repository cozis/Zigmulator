const std = @import("std");

const Simulator = @import("simulator.zig");

const Io = std.Io;
const Clock = Io.Clock;
const net = Io.net;

fn testClockGrowsMonotonically(init: std.process.Init) anyerror!void {
    const io = init.io;

    const t1 = Clock.boot.now(io);
    const t2 = Clock.boot.now(io);
    try std.testing.expect(t1.nanoseconds <= t2.nanoseconds);

    const t3 = Clock.boot.now(io);
    try std.testing.expect(t2.nanoseconds <= t3.nanoseconds);
}

test "clock grows monotonically" {
    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, std.Options.debug_io);
    defer sim.deinit();

    try sim.addExecutable("program_a", testClockGrowsMonotonically);
    try sim.spawn("program_a", .{});

    while (sim.scheduleOne()) {}
}

var networking_server_received = false;
var networking_client_received = false;

fn networkingServer(init: std.process.Init) anyerror!void {
    const address: net.IpAddress = .{ .ip4 = .loopback(8080) };

    var server = try address.listen(init.io, .{});
    defer server.deinit(init.io);

    var stream = try server.accept(init.io);
    defer stream.close(init.io);

    var reader_buffer: [16]u8 = undefined;
    var reader = stream.reader(init.io, &reader_buffer);
    var request: [4]u8 = undefined;
    try reader.interface.readSliceAll(&request);
    try std.testing.expectEqualStrings("ping", &request);
    networking_server_received = true;

    var writer_buffer: [16]u8 = undefined;
    var writer = stream.writer(init.io, &writer_buffer);
    try writer.interface.writeAll("pong");
    try writer.interface.flush();
}

fn networkingClient(init: std.process.Init) anyerror!void {
    const address: net.IpAddress = .{ .ip4 = .loopback(8080) };

    var stream = try address.connect(init.io, .{ .mode = .stream });
    defer stream.close(init.io);

    var writer_buffer: [16]u8 = undefined;
    var writer = stream.writer(init.io, &writer_buffer);
    try writer.interface.writeAll("ping");
    try writer.interface.flush();

    try Io.sleep(init.io, .fromMilliseconds(1), .awake);

    var reader_buffer: [16]u8 = undefined;
    var reader = stream.reader(init.io, &reader_buffer);
    var response: [4]u8 = undefined;
    try reader.interface.readSliceAll(&response);
    try std.testing.expectEqualStrings("pong", &response);
    networking_client_received = true;
}

test "networking mocks support tcp stream listen connect accept read write" {
    networking_server_received = false;
    networking_client_received = false;

    const loopback = net.Ip4Address.loopback(8080);
    const server_addresses = [_]u32{std.mem.readInt(u32, &loopback.bytes, .big)};

    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, std.Options.debug_io);
    defer sim.deinit();

    try sim.addExecutable("server", networkingServer);
    try sim.addExecutable("client", networkingClient);

    try sim.spawn("server", .{ .addresses = &server_addresses });
    try sim.spawn("client", .{});

    while (sim.scheduleOne()) {}

    try std.testing.expect(networking_server_received);
    try std.testing.expect(networking_client_received);
}
