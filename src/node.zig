const std = @import("std");
const Allocator = std.mem.Allocator;

const FileSystem  = @import("file_system.zig");
const Network     = @import("network.zig");
const Scheduler   = @import("scheduler.zig");
const ioInterface = @import("io_interface.zig");

const MAX_DESCRIPTORS = 1<<10;

const Node = @This();
const Handle = i32;

const Descriptor = struct {

    const Kind = enum {
        dir,
        file,
        listen,
        conn,
        unused,
    };

    kind  : Kind = .unused,
    dir   : FileSystem.OpenDir   = undefined,
    file  : FileSystem.OpenFile  = undefined,
    listen: Network.ListenSocket = undefined,
    conn  : Network.ConnSocket   = undefined,
};

gpa: Allocator,
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
        if (command[cursor] != ' ' and (cursor == 0 or command[cursor-1] == ' '))
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

pub fn init(
    self     : *Node,
    real_io  : std.Io,
    scheduler: *Scheduler,
    network  : *Network,
    command  : []const u8,
    addresses: []const u32,
    gpa      : Allocator
) !void {
    self.gpa = gpa;
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
    self.stdin_reader  = std.Io.File.stdin().readerStreaming(real_io, &.{});
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

fn unusedDesc(self: *Node) ?*Descriptor {
    for (&self.descriptors) |*desc| {
        if (desc.kind == .unused)
            return desc;
    }
    return null;
}

const HandleError = error {
    InvalidHandle,
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

pub fn closeDir(self: *Node, handle: Handle) HandleError!void {
    self.scheduler.sleep(10);
    const desc = try self.handleToDescOfType(handle, .dir);
    self.file_system.closeDir(&desc.dir, self.gpa);
    desc.kind = .unused;
}

pub const CreateDirError = HandleError || FileSystem.CreateError;

pub fn createDir(self: *Node, parent: ?Handle, path: []const u8) CreateDirError!void {
    self.scheduler.sleep(10);
    return self.file_system.createDir(
        path,
        try self.handleToOpenDirOrNULL(parent),
        self.gpa
    );
}

pub const OpenDirError = error {
    DescriptorLimit,
} || HandleError || FileSystem.OpenError;

pub fn openDir(self: *Node, parent: ?Handle, path: []const u8) OpenDirError!Handle {
    self.scheduler.sleep(10);
    const desc = self.unusedDesc() orelse return OpenDirError.DescriptorLimit;
    try self.file_system.openDir(path, try self.handleToOpenDirOrNULL(parent), &desc.dir);
    desc.kind = .dir;
    return self.descToHandle(desc);
}

pub fn readDir(self: *Node, handle: Handle) HandleError!FileSystem.ReadDir {
    self.scheduler.sleep(10);
    const desc = try self.handleToDescOfType(handle, .dir);
    return self.file_system.readDir(&desc.dir);
}

fn handleToOpenDirOrNULL(self: *Node, handle: ?Handle) HandleError!?*FileSystem.OpenDir {
    if (handle) |h| {
        const desc = try self.handleToDescOfType(h, .dir);
        return &desc.dir;
    } else {
        return null;
    }
}

pub const CreateFileError = HandleError || FileSystem.CreateError;

pub fn createFile(self: *Node, parent: ?Handle, path: []const u8) CreateFileError!void {
    self.scheduler.sleep(10);
    return self.file_system.createFile(
        path,
        try self.handleToOpenDirOrNULL(parent),
        self.gpa
    );
}

pub const DeleteFileError = HandleError || FileSystem.DeleteError;

pub fn deleteFile(self: *Node, parent: ?Handle, path: []const u8) DeleteFileError!void {
    self.scheduler.sleep(10);
    return self.file_system.deleteAny(
        path,
        try self.handleToOpenDirOrNULL(parent),
        self.gpa
    );
}

pub const OpenFileError = error {
    DescriptorLimit,
} || HandleError || FileSystem.OpenError;

pub fn openFile(self: *Node, parent: ?Handle, path: []const u8) OpenFileError!Handle {
    self.scheduler.sleep(10);
    const desc = self.unusedDesc() orelse return OpenFileError.DescriptorLimit;
    try self.file_system.openFile(path, try self.handleToOpenDirOrNULL(parent), &desc.file);
    desc.kind = .file;
    return self.descToHandle(desc);
}

pub fn closeFile(self: *Node, handle: Handle) HandleError!void {
    self.scheduler.sleep(10);
    const desc = try self.handleToDescOfType(handle, .file);
    self.file_system.closeFile(&desc.file, self.gpa);
    desc.kind = .unused;
}

pub fn fileSize(self: *Node, handle: Handle) HandleError!u64 {
    self.scheduler.sleep(2);
    const desc = try self.handleToDescOfType(handle, .file);
    return @intCast(self.file_system.fileSize(&desc.file));
}

pub fn readFile(self: *Node, handle: Handle, offset: ?usize, target: []u8) HandleError!usize {
    self.scheduler.sleep(100);
    if (handle == 0) {
        @panic("Not implemented yet"); // TODO: stdin
    } else if (handle == 1) {
        return HandleError.InvalidHandle;
    } else if (handle == 2) {
        return HandleError.InvalidHandle;
    } else {
        const desc = try self.handleToDescOfType(handle, .file);
        return self.file_system.readFile(&desc.file, offset, target);
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

pub const WriteFileError = HandleError || Allocator.Error;

pub fn writeFile(
    self  : *Node,
    handle: Handle,
    offset: ?usize,
    header: []const u8,
    source: []const []const u8
) WriteFileError!usize {

    self.scheduler.sleep(100);

    if (handle == 0) {
        return HandleError.InvalidHandle;
    } else if (handle == 1) {
        var copied: usize = 0;
        self.writeToStdout(header);
        copied += header.len;
        for (source) |item| {
            self.writeToStdout(item);
            copied += item.len;
        }
        return copied;
    } else if (handle == 2) {
        var copied: usize = 0;
        self.writeToStderr(header);
        copied += header.len;
        for (source) |item| {
            self.writeToStderr(item);
            copied += item.len;
        }
        return copied;
    } else {
        var copied: usize = 0;
        const desc = try self.handleToDescOfType(handle, .file);
        try self.file_system.writeFile(&desc.file, self.gpa, offset, header);
        copied += header.len;
        for (source) |item| {
            try self.file_system.writeFile(&desc.file, self.gpa, null, item);
            copied += item.len;
        }
        return copied;
    }
}

pub const Address = Network.Address;
pub const ListenError = error {
    DescriptorLimit,
} || Network.ListenError;

pub fn listen(self: *Node, address: Address) ListenError!Handle {
    self.scheduler.sleep(10);
    const desc = self.unusedDesc() orelse return ListenError.DescriptorLimit;
    try self.network_host.listen(address, &desc.listen);
    desc.kind = .listen;
    return self.descToHandle(desc);
}

pub const AcceptError = error {
    DescriptorLimit,
} || HandleError || Network.AcceptError;

pub fn accept(self: *Node, handle: Handle) AcceptError!Handle {
    self.scheduler.sleep(10);
    const old_desc = try self.handleToDescOfType(handle, .listen);
    const new_desc = self.unusedDesc() orelse return AcceptError.DescriptorLimit;
    try self.network_host.accept(&old_desc.listen, &new_desc.conn);
    new_desc.kind = .conn;
    return self.descToHandle(new_desc);
}

pub const ConnectError = error {
    DescriptorLimit,
} || Network.ConnectError;

pub fn connect(self: *Node, address: Address) ConnectError!Handle {
    self.scheduler.sleep(10);
    const desc = self.unusedDesc() orelse return ConnectError.DescriptorLimit;
    try self.network_host.connect(address, &desc.conn);
    desc.kind = .conn;
    return self.descToHandle(desc);
}

pub fn readSocket(self: *Node, handle: Handle, target: []u8) HandleError!usize {
    self.scheduler.sleep(10);
    const desc = try self.handleToDescOfType(handle, .conn);
    return self.network_host.read(&desc.conn, target);
}

pub fn writeSocket(self: *Node, handle: Handle, source: []const u8) HandleError!usize {
    self.scheduler.sleep(10);
    const desc = try self.handleToDescOfType(handle, .conn);
    return self.network_host.send(&desc.conn, source);
}

pub fn closeSocket(self: *Node, handle: Handle) HandleError!void {
    self.scheduler.sleep(10);
    const desc = try self.handleToDesc(handle);
    if (desc.kind == .conn) {
        self.network_host.closeConnSocket(&desc.conn);
    } else if (desc.kind == .listen) {
        self.network_host.closeListenSocket(&desc.listen);
    } else {
        return HandleError.InvalidHandle;
    }
    desc.kind = .unused;
}

pub fn dumpFiles(self: *Node) void {
    self.file_system.dump();
}
