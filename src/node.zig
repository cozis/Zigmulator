const std = @import("std");
const Allocator = std.mem.Allocator;

const FileSystem = @import("file_system.zig");
const Network = @import("network.zig");
const Scheduler = @import("scheduler.zig");
const Trace = @import("trace.zig").Trace;
const ioInterface = @import("io_interface.zig");

const MAX_DESCRIPTORS = 1 << 10;

const Node = @This();
const Handle = i32;

const DelayRange = struct {
    min_us: u64,
    max_us: u64,
};

const Delay = struct {
    const dir_close = DelayRange{ .min_us = 2, .max_us = 10 };
    const dir_create = DelayRange{ .min_us = 20, .max_us = 80 };
    const dir_delete = DelayRange{ .min_us = 20, .max_us = 80 };
    const dir_open = DelayRange{ .min_us = 20, .max_us = 80 };
    const dir_rename = DelayRange{ .min_us = 20, .max_us = 100 };
    const dir_reset = DelayRange{ .min_us = 1, .max_us = 5 };
    const dir_read = DelayRange{ .min_us = 10, .max_us = 40 };

    const file_create = DelayRange{ .min_us = 20, .max_us = 100 };
    const file_delete = DelayRange{ .min_us = 20, .max_us = 100 };
    const file_open = DelayRange{ .min_us = 20, .max_us = 80 };
    const file_close = DelayRange{ .min_us = 2, .max_us = 15 };
    const file_size = DelayRange{ .min_us = 2, .max_us = 10 };
    const file_sync = DelayRange{ .min_us = 150, .max_us = 500 };
    const file_read = DelayRange{ .min_us = 60, .max_us = 220 };
    const file_write = DelayRange{ .min_us = 80, .max_us = 300 };
    const file_seek = DelayRange{ .min_us = 1, .max_us = 8 };

    const socket_listen = DelayRange{ .min_us = 10, .max_us = 40 };
    const socket_accept_poll = DelayRange{ .min_us = 10, .max_us = 40 };
    const socket_connect = DelayRange{ .min_us = 50, .max_us = 200 };
    const socket_read_poll = DelayRange{ .min_us = 10, .max_us = 60 };
    const socket_write = DelayRange{ .min_us = 20, .max_us = 100 };
    const socket_close = DelayRange{ .min_us = 5, .max_us = 30 };
};

pub const TaskID = Scheduler.TaskID;
const NestedEntryPoint = Scheduler.NestedEntryPoint;

const Descriptor = struct {
    const Kind = enum {
        dir,
        file,
        listen,
        conn,
        unused,
    };

    kind: Kind = .unused,
    dir: FileSystem.OpenDir = undefined,
    file: FileSystem.OpenFile = undefined,
    listen: Network.ListenSocket = undefined,
    conn: Network.ConnSocket = undefined,
};

gpa: Allocator,
trace: *Trace,
prng: *std.Random.DefaultPrng,
id: u32,
local_time: u64,
arena: std.heap.ArenaAllocator,
argv: [][*:0]const u8,
environ_map: std.process.Environ.Map,
scheduler: *Scheduler,
file_system: FileSystem,
network_host: Network.Host,
descriptors: [MAX_DESCRIPTORS]Descriptor,
real_io: std.Io,
stdin_reader: std.Io.File.Reader,
stderr_writer: std.Io.File.Writer,
stdout_writer: std.Io.File.Writer,
stderr_buffer: [1024]u8,
stdout_buffer: [1024]u8,

fn splitCommandArguments(command: []const u8, arena: Allocator) Allocator.Error![][*:0]const u8 {
    var cursor: usize = 0;

    // Count how many arguments there are
    var count: usize = 0;
    while (cursor < command.len) {
        if (command[cursor] != ' ' and (cursor == 0 or command[cursor - 1] == ' '))
            count += 1;
        cursor += 1;
    }

    const result = try arena.alloc([*:0]const u8, count);

    count = 0;
    cursor = 0;
    while (true) {
        while (cursor < command.len and command[cursor] == ' ')
            cursor += 1;

        if (cursor == command.len)
            break;

        const offset = cursor;
        while (cursor < command.len and command[cursor] != ' ')
            cursor += 1;
        const arg = command[offset..cursor];

        result[count] = (try arena.dupeZ(u8, arg)).ptr;
        count += 1;
    }

    return result;
}

pub fn init(self: *Node, real_io: std.Io, trace: *Trace, prng: *std.Random.DefaultPrng, scheduler: *Scheduler, network: *Network, node_id: u32, command: []const u8, addresses: []const u32, gpa: Allocator) !void {
    self.gpa = gpa;
    self.trace = trace;
    self.prng = prng;
    self.id = node_id;
    self.local_time = 0;
    self.arena = .init(gpa);
    self.scheduler = scheduler;
    try self.file_system.init(gpa);

    self.network_host.init(network, addresses, gpa);
    try network.registerHost(&self.network_host);

    for (&self.descriptors) |*desc| {
        desc.kind = .unused;
    }

    self.argv = try splitCommandArguments(command, self.arena.allocator());
    self.environ_map = try std.process.Environ.createMap(.empty, gpa);

    self.real_io = real_io;
    self.stdin_reader = std.Io.File.stdin().readerStreaming(real_io, &.{});
    self.stdout_writer = std.Io.File.stdout().writerStreaming(real_io, &self.stdout_buffer);
    self.stderr_writer = std.Io.File.stderr().writerStreaming(real_io, &self.stderr_buffer);
}

pub fn deinit(self: *Node) void {
    self.environ_map.deinit();
    self.network_host.deinit();
    self.file_system.deinit(self.gpa);
    self.arena.deinit();
}

pub fn io(self: *Node) std.Io {
    return ioInterface.buildIOInterfaceForNode(self);
}

pub fn processInit(self: *Node) std.process.Init {
    return .{
        .minimal = .{
            .environ = .empty,
            .args = .{ .vector = self.argv },
        },
        .arena = &self.arena,
        .gpa = self.gpa, // TODO: Should use a per-task allocator
        .io = self.io(),
        .environ_map = &self.environ_map,
        .preopens = .empty,
    };
}

pub fn sleep(self: *Node, delta_us: u64) !void {
    return self.scheduler.sleep(delta_us);
}

fn fakeDelay(self: *Node, range: DelayRange) !void {
    std.debug.assert(range.min_us <= range.max_us);

    const delay_us = if (range.min_us == range.max_us) range.min_us else blk: {
        const random = self.prng.random();
        break :blk range.min_us + random.uintLessThan(u64, range.max_us - range.min_us + 1);
    };
    return self.scheduler.sleep(delay_us);
}

pub fn spawn(self: *Node, entry: NestedEntryPoint, context: *const anyopaque) !TaskID {
    return self.scheduler.spawnNested(self, entry, context);
}

pub fn despawn(self: *Node, id: TaskID) void {
    self.scheduler.despawnNested(id);
}

pub fn cancel(self: *Node, id: TaskID) void {
    self.scheduler.cancel(id);
}

pub fn checkCancel(self: *Node) !void {
    try self.scheduler.checkCancel();
}

pub fn recancel(self: *Node) void {
    self.scheduler.recancel();
}

pub fn wait(self: *Node, ids: []const TaskID) !TaskID {
    return self.scheduler.wait(ids);
}

pub fn futexWait(self: *Node, ptr: *const u32, expected: u32) !void {
    return self.scheduler.futexWait(ptr, expected);
}

pub fn futexWaitUncancelable(self: *Node, ptr: *const u32, expected: u32) void {
    self.scheduler.futexWaitUncancelable(ptr, expected);
}

pub fn futexWake(self: *Node, ptr: *const u32, max_waiters: u32) void {
    self.scheduler.futexWake(ptr, max_waiters);
}

fn unusedDesc(self: *Node) ?*Descriptor {
    for (&self.descriptors) |*desc| {
        if (desc.kind == .unused)
            return desc;
    }
    return null;
}

const HandleError = error{
    InvalidHandle,
};

pub const CancelError = error{
    Canceled,
};

const NUM_SPECIAL_HANDLES = 3;

fn handleToDesc(self: *Node, handle: Handle) HandleError!*Descriptor {

    // Any special handle (stdin, stdout, stderr) must be handled
    // as special cases before this point.
    std.debug.assert(handle >= NUM_SPECIAL_HANDLES);
    const index = handle - NUM_SPECIAL_HANDLES;

    if (index < 0 or index >= MAX_DESCRIPTORS)
        return HandleError.InvalidHandle;
    const desc = &self.descriptors[@intCast(index)];
    if (desc.kind == .unused)
        return HandleError.InvalidHandle;
    return desc;
}

fn handleToDescOfType(self: *Node, handle: Handle, kind: Descriptor.Kind) HandleError!*Descriptor {
    const desc = try self.handleToDesc(handle);
    if (desc.kind != kind)
        return HandleError.InvalidHandle;
    return desc;
}

fn descToHandle(self: *Node, desc: *Descriptor) Handle {
    // TODO: This loop is extremely dumb
    for (&self.descriptors, 0..) |*item, i| {
        if (item == desc)
            return @intCast(i + NUM_SPECIAL_HANDLES);
    }
    unreachable;
}

pub const CloseDirError = HandleError || CancelError;

pub fn closeDir(self: *Node, handle: Handle) CloseDirError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_close);
    const desc = self.handleToDescOfType(handle, .dir) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.closeDir(&desc.dir, self.gpa);
    desc.kind = .unused;
    self.trace.completeIO(pending_trace, .{});
}

pub const CreateDirError = HandleError || FileSystem.CreateError || CancelError;

pub fn createDir(self: *Node, parent: ?Handle, path: []const u8) CreateDirError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_create);
    const parent_dir = self.handleToOpenDirOrNULL(parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.createDir(path, parent_dir, self.gpa) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, .{});
}

pub const OpenDirError = error{
    DescriptorLimit,
} || HandleError || FileSystem.OpenError || CancelError;

pub fn openDir(self: *Node, parent: ?Handle, path: []const u8) OpenDirError!Handle {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_open);
    const desc = self.unusedDesc() orelse {
        const e = OpenDirError.DescriptorLimit;
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const parent_dir = self.handleToOpenDirOrNULL(parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.openDir(path, parent_dir, &desc.dir) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    desc.kind = .dir;
    const handle = self.descToHandle(desc);
    self.trace.completeIO(pending_trace, handle);
    return handle;
}

pub const ResetDirError = HandleError || CancelError;

pub fn resetDir(self: *Node, handle: Handle) ResetDirError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_reset);
    const desc = self.handleToDescOfType(handle, .dir) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.resetDir(&desc.dir);
    self.trace.completeIO(pending_trace, .{});
}

pub const ReadDirError = HandleError || FileSystem.ReadDirError || CancelError;

pub fn readDir(self: *Node, handle: Handle) ReadDirError!FileSystem.ReadDir {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_read);
    const desc = self.handleToDescOfType(handle, .dir) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const result = self.file_system.readDir(&desc.dir) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, result.name);
    return result;
}

fn handleToOpenDirOrNULL(self: *Node, handle: ?Handle) HandleError!?*FileSystem.OpenDir {
    if (handle) |h| {
        const desc = try self.handleToDescOfType(h, .dir);
        return &desc.dir;
    } else {
        return null;
    }
}

fn fakeDelayForIo(self: *Node, pending_trace: anytype, range: DelayRange) CancelError!void {
    self.fakeDelay(range) catch |err| {
        self.trace.failIO(pending_trace, err);
        return err;
    };
}

pub const CreateFileError = HandleError || FileSystem.CreateError || CancelError;

pub fn createFile(self: *Node, parent: ?Handle, path: []const u8) CreateFileError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_create);
    const parent_dir = self.handleToOpenDirOrNULL(parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.createFile(path, parent_dir, self.gpa) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, .{});
}

pub const DeleteFileError = HandleError || FileSystem.DeleteFileError || CancelError;

pub fn deleteFile(self: *Node, parent: ?Handle, path: []const u8) DeleteFileError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_delete);
    const parent_dir = self.handleToOpenDirOrNULL(parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.deleteFile(path, parent_dir, self.gpa) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, .{});
}

pub const DeleteDirError = HandleError || FileSystem.DeleteDirError || CancelError;

pub fn deleteDir(self: *Node, parent: ?Handle, path: []const u8) DeleteDirError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_delete);
    const parent_dir = self.handleToOpenDirOrNULL(parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.deleteDir(path, parent_dir, self.gpa) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, .{});
}

pub const RenameError = HandleError || FileSystem.RenameError || CancelError;

pub fn rename(self: *Node, old_parent: ?Handle, old_path: []const u8, new_parent: ?Handle, new_path: []const u8) RenameError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.dir_rename);
    const old_parent_dir = self.handleToOpenDirOrNULL(old_parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const new_parent_dir = self.handleToOpenDirOrNULL(new_parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.rename(old_path, old_parent_dir, new_path, new_parent_dir, self.gpa) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, .{});
}

pub const OpenFileError = error{
    DescriptorLimit,
} || HandleError || FileSystem.OpenError || CancelError;

pub fn openFile(self: *Node, parent: ?Handle, path: []const u8) OpenFileError!Handle {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_open);
    const desc = self.unusedDesc() orelse {
        const e = OpenFileError.DescriptorLimit;
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const parent_dir = self.handleToOpenDirOrNULL(parent) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.openFile(path, parent_dir, &desc.file) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    desc.kind = .file;
    const handle = self.descToHandle(desc);
    self.trace.completeIO(pending_trace, handle);
    return handle;
}

pub const CloseFileError = HandleError || CancelError;

pub fn closeFile(self: *Node, handle: Handle) CloseFileError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_close);
    const desc = self.handleToDescOfType(handle, .file) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.closeFile(&desc.file, self.gpa);
    desc.kind = .unused;
    self.trace.completeIO(pending_trace, .{});
}

pub const FileSizeError = HandleError || CancelError;

pub fn fileSize(self: *Node, handle: Handle) FileSizeError!u64 {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_size);
    const desc = self.handleToDescOfType(handle, .file) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const result: u64 = @intCast(self.file_system.fileSize(&desc.file));
    self.trace.completeIO(pending_trace, result);
    return result;
}

pub const SyncFileError = HandleError || CancelError;

pub fn syncFile(self: *Node, handle: Handle) SyncFileError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_sync);
    const desc = self.handleToDescOfType(handle, .file) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.syncFile(&desc.file);
    self.trace.completeIO(pending_trace, .{});
}

pub const ReadFileError = HandleError || CancelError;

pub fn readFile(self: *Node, handle: Handle, offset: ?usize, target: []u8) ReadFileError!usize {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_read);
    if (handle == 0) {
        @panic("Not implemented yet"); // TODO: stdin
    } else if (handle == 1) {
        const e = HandleError.InvalidHandle;
        self.trace.failIO(pending_trace, e);
        return e;
    } else if (handle == 2) {
        const e = HandleError.InvalidHandle;
        self.trace.failIO(pending_trace, e);
        return e;
    } else {
        const desc = self.handleToDescOfType(handle, .file) catch |e| {
            self.trace.failIO(pending_trace, e);
            return e;
        };
        const result = self.file_system.readFile(&desc.file, offset, target);
        self.trace.completeIO(pending_trace, result);
        return result;
    }
}

// It's important this function and the stderr version do not
// return a value back to the simulation or determinism would
// be broken.
fn writeToStdout(self: *Node, source: []const u8) void {
    self.stdout_writer.interface.writeAll(source) catch {};
    self.stdout_writer.interface.flush() catch {};
}

// See comment on writeToStdout
fn writeToStderr(self: *Node, source: []const u8) void {
    self.stderr_writer.interface.writeAll(source) catch {};
    self.stderr_writer.interface.flush() catch {};
}

pub const WriteFileError = HandleError || Allocator.Error || CancelError;

pub fn writeFile(self: *Node, handle: Handle, offset: ?usize, header: []const u8, source: []const []const u8) WriteFileError!usize {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_write);

    if (handle == 0) {
        const e = HandleError.InvalidHandle;
        self.trace.failIO(pending_trace, e);
        return e;
    } else if (handle == 1) {
        var copied: usize = 0;
        self.writeToStdout(header);
        copied += header.len;
        for (source) |item| {
            self.writeToStdout(item);
            copied += item.len;
        }
        self.trace.completeIO(pending_trace, copied);
        return copied;
    } else if (handle == 2) {
        var copied: usize = 0;
        self.writeToStderr(header);
        copied += header.len;
        for (source) |item| {
            self.writeToStderr(item);
            copied += item.len;
        }
        self.trace.completeIO(pending_trace, copied);
        return copied;
    } else {
        var copied: usize = 0;
        const desc = self.handleToDescOfType(handle, .file) catch |e| {
            self.trace.failIO(pending_trace, e);
            return e;
        };
        self.file_system.writeFile(&desc.file, self.gpa, offset, header) catch |e| {
            self.trace.failIO(pending_trace, e);
            return e;
        };
        copied += header.len;
        for (source) |item| {
            self.file_system.writeFile(&desc.file, self.gpa, null, item) catch |e| {
                self.trace.failIO(pending_trace, e);
                return e;
            };
            copied += item.len;
        }
        self.trace.completeIO(pending_trace, copied);
        return copied;
    }
}

pub const SeekFileError = HandleError || FileSystem.SeekError || CancelError;

pub fn seekFileTo(self: *Node, handle: Handle, offset: usize) SeekFileError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_seek);
    const desc = self.handleToDescOfType(handle, .file) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.seekFileTo(&desc.file, offset);
    self.trace.completeIO(pending_trace, .{});
}

pub fn seekFileBy(self: *Node, handle: Handle, offset: i64) SeekFileError!void {
    const pending_trace = self.trace.beginIO(true, @src());

    try self.fakeDelayForIo(pending_trace, Delay.file_seek);
    const desc = self.handleToDescOfType(handle, .file) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.file_system.seekFileBy(&desc.file, offset) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, .{});
}

pub const Address = Network.Address;
pub const ListenError = error{
    DescriptorLimit,
} || Network.ListenError || CancelError;

pub fn listen(self: *Node, address: Address) ListenError!Handle {
    const pending_trace = self.trace.beginIO(false, @src());

    try self.fakeDelayForIo(pending_trace, Delay.socket_listen);
    const desc = self.unusedDesc() orelse {
        const e = ListenError.DescriptorLimit;
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.network_host.listen(address, &desc.listen) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    desc.kind = .listen;
    const handle = self.descToHandle(desc);
    self.trace.completeIO(pending_trace, handle);
    return handle;
}

pub const AcceptError = error{
    DescriptorLimit,
} || HandleError || Network.AcceptError || CancelError;

pub fn accept(self: *Node, handle: Handle) AcceptError!Handle {
    const pending_trace = self.trace.beginIO(false, @src());

    const old_desc = self.handleToDescOfType(handle, .listen) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const new_desc = self.unusedDesc() orelse {
        const e = AcceptError.DescriptorLimit;
        self.trace.failIO(pending_trace, e);
        return e;
    };

    while (true) {
        try self.fakeDelayForIo(pending_trace, Delay.socket_accept_poll);
        self.network_host.accept(&old_desc.listen, &new_desc.conn) catch |e| switch (e) {
            error.AcceptQueueEmpty => continue,
            else => {
                self.trace.failIO(pending_trace, e);
                return e;
            },
        };
        new_desc.kind = .conn;
        const accepted_handle = self.descToHandle(new_desc);
        self.trace.completeIO(pending_trace, accepted_handle);
        return accepted_handle;
    }
}

pub const ConnectError = error{
    DescriptorLimit,
} || Network.ConnectError || CancelError;

pub fn connect(self: *Node, address: Address) ConnectError!Handle {
    const pending_trace = self.trace.beginIO(false, @src());

    try self.fakeDelayForIo(pending_trace, Delay.socket_connect);
    const desc = self.unusedDesc() orelse {
        const e = ConnectError.DescriptorLimit;
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.network_host.connect(address, &desc.conn) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    desc.kind = .conn;
    const handle = self.descToHandle(desc);
    self.trace.completeIO(pending_trace, handle);
    return handle;
}

pub const ReadSocketError = HandleError || CancelError;

pub fn readSocket(self: *Node, handle: Handle, target: []u8, block: bool) ReadSocketError!usize {
    const pending_trace = self.trace.beginIO(false, @src());

    if (target.len == 0) {
        self.trace.completeIO(pending_trace, 0);
        return 0;
    }

    const desc = self.handleToDescOfType(handle, .conn) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };

    if (block) {
        while (true) {
            try self.fakeDelayForIo(pending_trace, Delay.socket_read_poll);

            const num = self.network_host.read(&desc.conn, target);

            if (num > 0) {
                self.trace.completeIO(pending_trace, num);
                return num;
            }

            if (num == 0) {
                if (!self.network_host.isConnected(&desc.conn)) {
                    self.trace.completeIO(pending_trace, "eof");
                    return 0;
                }
            }
        }
        unreachable;
    } else {
        const num = self.network_host.read(&desc.conn, target);
        self.trace.completeIO(pending_trace, num);
        return num;
    }
}

pub const WriteSocketError = HandleError || Network.SendError || CancelError;

pub fn writeSocket(self: *Node, handle: Handle, source: []const u8) WriteSocketError!usize {
    const pending_trace = self.trace.beginIO(false, @src());

    try self.fakeDelayForIo(pending_trace, Delay.socket_write);
    const desc = self.handleToDescOfType(handle, .conn) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    const result = self.network_host.send(&desc.conn, source) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    self.trace.completeIO(pending_trace, result);
    return result;
}

pub const CloseSocketError = HandleError || CancelError;

pub fn closeSocket(self: *Node, handle: Handle) CloseSocketError!void {
    const pending_trace = self.trace.beginIO(false, @src());

    try self.fakeDelayForIo(pending_trace, Delay.socket_close);
    const desc = self.handleToDesc(handle) catch |e| {
        self.trace.failIO(pending_trace, e);
        return e;
    };
    if (desc.kind == .conn) {
        self.network_host.closeConnSocket(&desc.conn);
    } else if (desc.kind == .listen) {
        self.network_host.closeListenSocket(&desc.listen);
    } else {
        const e = HandleError.InvalidHandle;
        self.trace.failIO(pending_trace, e);
        return e;
    }
    desc.kind = .unused;
    self.trace.completeIO(pending_trace, .{});
}

pub fn dumpFiles(self: *Node) void {
    self.file_system.dump();
}
