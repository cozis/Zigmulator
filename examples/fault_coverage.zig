const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Simulator = @import("zigmulator");
const assertSometimes = Simulator.assertSometimes;

const server_ip = net.Ip4Address.loopback(9090);
const server_address: net.IpAddress = .{ .ip4 = server_ip };
const payload = "payload:v1:write-sync-rename-send";
const ack = "ack";

fn serverProgram(init: std.process.Init) anyerror!void {
    var server = try server_address.listen(init.io, .{});
    defer server.deinit(init.io);

    var stream = try server.accept(init.io);
    defer stream.close(init.io);

    var reader_buffer: [5]u8 = undefined;
    var reader = stream.reader(init.io, &reader_buffer);

    var received: [payload.len]u8 = undefined;
    var copied: usize = 0;
    while (copied < received.len) {
        const n = try reader.interface.readSliceShort(received[copied..]);
        assertSometimes(n < received.len - copied, @src(), "server saw short socket read");
        if (n == 0) {
            assertSometimes(true, @src(), "server saw EOF before full request");
            return error.UnexpectedEof;
        }
        copied += n;
    }

    assertSometimes(!std.mem.eql(u8, &received, payload), @src(), "server saw corrupted request");

    var writer_buffer: [0]u8 = undefined;
    var writer = stream.writer(init.io, &writer_buffer);
    const written = try writer.interface.write(ack);
    assertSometimes(written < ack.len, @src(), "server saw short socket write");
    try writer.interface.flush();
    assertSometimes(true, @src(), "server completed happy path");
}

fn connectWithRetry(init: std.process.Init) !net.Stream {
    var attempt: usize = 0;
    while (attempt < 8) : (attempt += 1) {
        if (server_address.connect(init.io, .{ .mode = .stream })) |stream| {
            assertSometimes(attempt > 0, @src(), "client connected after retry");
            return stream;
        } else |err| switch (err) {
            error.ConnectionRefused, error.HostUnreachable => {
                assertSometimes(true, @src(), "client saw transient connect failure");
                try Io.sleep(init.io, .fromMilliseconds(1), .awake);
            },
            else => return err,
        }
    }

    return error.ConnectionRefused;
}

fn clientProgram(init: std.process.Init) anyerror!void {
    try Io.Dir.cwd().createDir(init.io, "spool", .default_dir);

    const spool = try Io.Dir.cwd().openDir(init.io, "spool", .{});
    defer spool.close(init.io);

    const staged = try spool.createFile(init.io, "message.tmp", .{});
    defer staged.close(init.io);

    const file_written = try staged.writePositional(init.io, &.{payload}, 0);
    assertSometimes(file_written < payload.len, @src(), "client saw short file write");

    try staged.sync(init.io);

    try spool.rename("message.tmp", spool, "message.ready", init.io);

    const ready = try spool.openFile(init.io, "message.ready", .{});
    defer ready.close(init.io);

    var buffer: [payload.len]u8 = undefined;
    const read_len = try ready.readPositionalAll(init.io, &buffer, 0);
    assertSometimes(read_len < payload.len, @src(), "client saw short file read");
    assertSometimes(!std.mem.eql(u8, buffer[0..read_len], payload), @src(), "client saw corrupted file data");

    var stream = try connectWithRetry(init);
    defer stream.close(init.io);

    var writer_buffer: [0]u8 = undefined;
    var writer = stream.writer(init.io, &writer_buffer);
    const socket_written = try writer.interface.write(buffer[0..read_len]);
    assertSometimes(socket_written < read_len, @src(), "client saw short socket write");
    try writer.interface.flush();

    var reader_buffer: [1]u8 = undefined;
    var reader = stream.reader(init.io, &reader_buffer);
    var response: [ack.len]u8 = undefined;
    var copied: usize = 0;
    while (copied < response.len) {
        const n = try reader.interface.readSliceShort(response[copied..]);
        assertSometimes(n < response.len - copied, @src(), "client saw short socket read");
        if (n == 0) {
            assertSometimes(true, @src(), "client saw EOF before full ack");
            return error.UnexpectedEof;
        }
        copied += n;
    }

    assertSometimes(!std.mem.eql(u8, &response, ack), @src(), "client saw corrupted ack");

    try spool.deleteFile(init.io, "message.ready");
    assertSometimes(true, @src(), "client completed happy path");
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();

    const first_seed_text = args.next() orelse "0";
    const first_seed = try std.fmt.parseInt(u64, first_seed_text, 10);
    const count_text = args.next() orelse "1";
    const count = try std.fmt.parseInt(u64, count_text, 10);

    for (0..count) |offset| {
        try runSimulation(init, first_seed + offset);
    }
}

fn runSimulation(init: std.process.Init, seed: u64) !void {
    const server_addresses = [_]u32{std.mem.readInt(u32, &server_ip.bytes, .big)};

    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io, seed);
    defer sim.deinit();

    sim.enablePartitionFaults(.{
        .weights = .{
            .none = 40,
            .isolate_one = 60,
            .split_two_groups = 0,
        },
        .min_interval_us = 500,
        .max_interval_us = 2_000,
    });

    try sim.setTraceOutputFile("fault_coverage.log");

    try sim.addExecutable("server", serverProgram);
    try sim.addExecutable("client", clientProgram);

    try sim.spawn("server", .{ .addresses = &server_addresses });
    try sim.spawn("client", .{});

    while (sim.scheduleOne()) {}
}
