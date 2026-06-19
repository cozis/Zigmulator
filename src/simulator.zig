const Simulator = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Trace = @import("trace.zig").Trace;
const Scheduler = @import("scheduler.zig");
const Network   = @import("network.zig");
const Node      = @import("node.zig");
const Sometimes = @import("sometimes.zig").Sometimes;

pub const EntryPoint = Scheduler.MainEntryPoint;

// Process-global pointer to the active simulation's sometimes-assertion
// registry. Programs under test only receive an `std.Io` and have no handle to
// the Simulator, so assertSometimes() reaches the registry through this global.
// Everything runs single-threaded in userspace, so a plain global is
// deterministic. It is set in init() and cleared in deinit(), giving each
// simulation a fresh, per-run registry.
var g_sometimes: ?*Sometimes = null;

// Records that `cond` was observed at this point of the simulation. The call
// site (@src()) is the identity; `label` is an optional human-readable name
// shown in the end-of-simulation report. Pass null when no label is wanted:
//     assertSometimes(x > 0, @src(), null);
//
// This never changes the behaviour of the program under test: if no simulation
// is active the call is a no-op.
pub fn assertSometimes(cond: bool, src: std.builtin.SourceLocation, label: ?[]const u8) void {
    const registry = g_sometimes orelse return;
    registry.record(cond, src, label);
}

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
trace: Trace,
prng: std.Random.DefaultPrng,
scheduler: Scheduler,
network: Network,
nodes: std.ArrayList(*Node),
executables: std.ArrayList(ExecutableName),
real_io: std.Io,
next_node_id: u32,
sometimes: Sometimes,

pub fn init(self: *Simulator, gpa: Allocator, real_io: std.Io, seed: u64) void {
    self.gpa = gpa;
    self.trace.init(&self.scheduler, real_io);
    self.prng = std.Random.DefaultPrng.init(seed);
    self.scheduler.init(gpa, &self.trace, &self.prng);
    self.network.init(gpa);
    self.nodes = .empty;
    self.executables = .empty;
    self.real_io = real_io;
    self.next_node_id = 0;
    self.sometimes.init(gpa);
    g_sometimes = &self.sometimes;
}

pub fn deinit(self: *Simulator) void {
    // Print the end-of-simulation coverage report unless the caller already
    // asked for it explicitly via reportSometimes().
    if (!self.sometimes.reported)
        self.sometimes.report();
    g_sometimes = null;
    self.sometimes.deinit();

    for (self.nodes.items) |node| {
        node.deinit();
        self.gpa.destroy(node);
    }
    self.executables.deinit(self.gpa);
    self.nodes.deinit(self.gpa);
    self.network.deinit();
    self.scheduler.deinit();
    self.trace.deinit();
}

// Prints which sometimes-assertions were taken (✓) and which were reached
// but never satisfied (✗). Called automatically by deinit(); expose it so
// callers can choose exactly when the report is emitted.
pub fn reportSometimes(self: *Simulator) void {
    self.sometimes.report();
}

pub fn setTraceOutputFile(self: *Simulator, path: []const u8) !void {
    try self.trace.setOutputFile(path);
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

    const node_id = self.next_node_id;
    self.next_node_id += 1;

    const node = try self.gpa.create(Node);
    errdefer self.gpa.destroy(node);

    try node.init(self.real_io, &self.trace, &self.prng, &self.scheduler, &self.network, node_id, command, options.addresses, self.gpa);

    try self.nodes.append(self.gpa, node);
    errdefer _ = self.nodes.swapRemove(self.nodes.items.len-1);

    try self.scheduler.spawn(node, entry, options.stack_size);
}

pub fn scheduleOne(self: *Simulator) bool {
    return self.scheduler.scheduleOne();
}

pub fn dumpFiles(self: *Simulator) void {
    for (self.nodes.items) |node| {
        node.dumpFiles();
    }
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
