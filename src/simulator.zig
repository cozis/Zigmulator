const Simulator = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Scheduler = @import("scheduler.zig");
const Network   = @import("network.zig");
const Node      = @import("node.zig");

pub const EntryPoint = Scheduler.EntryPoint;

const SpawnOptions = struct {
    stack_size: usize = 64 * 1024,
    addresses: []const u32 = &[0]u32 {}, // TODO: How do I make an empty slice?
};

const SpawnError = error {
    InvalidCommand,
    NoSuchProgram,
} || Allocator.Error ||  std.process.Environ.CreateMapError;

const ExecutableName = struct {
    name : []const u8,
    entry: EntryPoint,
};

gpa: Allocator,
scheduler: Scheduler,
network: Network,
nodes: std.ArrayList(*Node),
executables: std.ArrayList(ExecutableName),
real_io: std.Io,

pub fn init(self: *Simulator, gpa: Allocator, real_io: std.Io) void {
    self.gpa = gpa;
    self.scheduler.init(gpa);
    self.network.init(gpa);
    self.nodes = .empty;
    self.executables = .empty;
    self.real_io = real_io;
}

pub fn deinit(self: *Simulator) void {
    for (self.nodes.items) |node| {
        node.deinit();
        self.gpa.destroy(node);
    }
    self.executables.deinit(self.gpa);
    self.nodes.deinit(self.gpa);
    self.network.deinit();
    self.scheduler.deinit();
}

pub fn addExecutable(self: *Simulator, name: []const u8, entry: EntryPoint) Allocator.Error!void {
    try self.executables.append(self.gpa, ExecutableName {
        .name = name,
        .entry = entry,
    });
}

pub fn spawn(self: *Simulator, command: []const u8, options: SpawnOptions) SpawnError!void {
    const name = extractProgramNameFromCommand(command) orelse return SpawnError.InvalidCommand;
    const entry = self.getExecutableEntryPoint(name) orelse return SpawnError.NoSuchProgram;

    const node = try self.gpa.create(Node);
    errdefer self.gpa.destroy(node);

    try node.init(self.real_io, &self.scheduler, &self.network, command, options.addresses, self.gpa);

    try self.nodes.append(self.gpa, node);
    errdefer _ = self.nodes.swapRemove(self.nodes.items.len-1);

    try self.scheduler.spawn(node, entry, options.stack_size);
}

pub fn scheduleOne(self: *Simulator) bool {
    return self.scheduler.scheduleOne();
}

// Reads the first word of a command
//     "program arg1 arg2 arg3" -> "program"
fn extractProgramNameFromCommand(command: []const u8) ?[]const u8 {
    var cur: usize = 0;
    while (cur < command.len and command[cur] != ' ')
        cur += 1;

    if (cur == 0)
        return null;
    return command[0..cur];
}

fn getExecutableEntryPoint(self: *Simulator, name: []const u8) ?EntryPoint {
    for (self.executables.items) |executable| {
        if (std.mem.eql(u8, executable.name, name))
            return executable.entry;
    }
    return null;
}
