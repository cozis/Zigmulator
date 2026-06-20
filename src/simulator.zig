const Simulator = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Trace = @import("trace.zig").Trace;
const Scheduler = @import("scheduler.zig");
const Network = @import("network.zig");
const Node = @import("node.zig");
const PartitionPolicy = @import("partition_policy.zig");
const sometimes_mod = @import("sometimes.zig");
const Sometimes = sometimes_mod.Sometimes;

pub const EntryPoint = Scheduler.MainEntryPoint;
pub const PartitionShape = PartitionPolicy.Shape;
pub const PartitionShapeWeights = PartitionPolicy.ShapeWeights;

pub const PartitionFaultOptions = struct {
    weights: PartitionShapeWeights = .{},
    min_interval_us: u64 = 1_000,
    max_interval_us: u64 = 60 * 60 * 1_000_000,
};

const CRASH_FAULT_MIN_INTERVAL_US = 1_000;
const CRASH_FAULT_MAX_INTERVAL_US = 60 * 60 * 1_000_000;

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
pub fn assertSometimes(cond: bool, comptime src: std.builtin.SourceLocation, comptime label: ?[]const u8) void {
    const site = sometimes_mod.registerSite(src, label, .assert);
    const registry = g_sometimes orelse return;
    registry.record(cond, site.*);
}

// Records that this call site was reached. This is the conditionless form of
// assertSometimes() for branches where reaching the line is the coverage signal.
pub fn reachableSometimes(comptime src: std.builtin.SourceLocation, comptime label: ?[]const u8) void {
    const site = sometimes_mod.registerSite(src, label, .reachable);
    const registry = g_sometimes orelse return;
    registry.record(true, site.*);
}

// Prints every compiled assertSometimes()/reachableSometimes() call site known
// to this binary. This is independent of whether a simulation has run.
pub fn reportSometimesSites() void {
    sometimes_mod.reportCompileTimeSites();
}

var g_events: ?*u32 = null;

pub fn event(index: u32) void {
    const word = g_events orelse return;
    word.* |= @as(u32, 1) << @intCast(index);
}

const SpawnOptions = struct {
    stack_size: usize = 64 * 1024,
    addresses: []const u32 = &[0]u32{}, // TODO: How do I make an empty slice?
    recoverable: bool = true,
};

const SpawnError = error{
    InvalidCommand,
    NoSuchProgram,
} || Allocator.Error || std.process.Environ.CreateMapError;

const ExecutableName = struct {
    name: []const u8,
    entry: EntryPoint,
};

gpa: Allocator,
trace: Trace,
prng: std.Random.DefaultPrng,
scheduler: Scheduler,
network: Network,
partition_policy: PartitionPolicy,
partition_endpoints: std.ArrayList(Network.HostID),
faults_enabled: bool,
partition_target_selected: bool,
partition_fault_options: PartitionFaultOptions,
next_partition_step_time_us: u64,
next_crash_step_time_us: u64,
nodes: std.ArrayList(*Node),
executables: std.ArrayList(ExecutableName),
real_io: std.Io,
next_node_id: u32,
sometimes: Sometimes,
events: u32,

pub fn init(self: *Simulator, gpa: Allocator, real_io: std.Io, seed: u64) void {
    self.gpa = gpa;
    self.trace.init(&self.scheduler, real_io);
    self.prng = std.Random.DefaultPrng.init(seed);
    self.scheduler.init(gpa, &self.trace, &self.prng);
    self.network.init(gpa);
    self.partition_policy.init(gpa, .{});
    self.partition_endpoints = .empty;
    self.faults_enabled = true;
    self.partition_target_selected = false;
    self.partition_fault_options = .{};
    self.next_partition_step_time_us = 0;
    self.next_crash_step_time_us = 0;
    self.nodes = .empty;
    self.executables = .empty;
    self.real_io = real_io;
    self.next_node_id = 0;
    self.sometimes.init(gpa);
    self.sometimes.seedCompileTimeSites();
    g_sometimes = &self.sometimes;
    self.events = 0;
    g_events = &self.events;
}

pub fn deinit(self: *Simulator) void {
    // Print the end-of-simulation coverage report unless the caller already
    // asked for it explicitly via reportSometimes().
    if (!self.sometimes.reported)
        self.sometimes.report();
    g_sometimes = null;
    g_events = null;
    self.sometimes.deinit();
    self.partition_policy.deinit();
    self.partition_endpoints.deinit(self.gpa);

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

// Prints which sometimes-assertions were taken and which were reached
// but never satisfied. Called automatically by deinit(); expose it so
// callers can choose exactly when the report is emitted.
pub fn reportSometimes(self: *Simulator) void {
    self.sometimes.report();
}

pub fn sometimesCovered(self: *Simulator) bool {
    return self.sometimes.allReached();
}

pub const InvalidNodeError = error{
    InvalidNode,
};

pub const BreakLinkError = InvalidNodeError || Allocator.Error;

pub fn breakLink(self: *Simulator, a: u32, b: u32) BreakLinkError!void {
    try self.network.breakLink(
        self.hostIDForNodeID(a) orelse return InvalidNodeError.InvalidNode,
        self.hostIDForNodeID(b) orelse return InvalidNodeError.InvalidNode,
    );
}

pub fn healLink(self: *Simulator, a: u32, b: u32) InvalidNodeError!void {
    self.network.healLink(
        self.hostIDForNodeID(a) orelse return InvalidNodeError.InvalidNode,
        self.hostIDForNodeID(b) orelse return InvalidNodeError.InvalidNode,
    );
}

pub fn linkIsBroken(self: *const Simulator, a: u32, b: u32) InvalidNodeError!bool {
    return self.network.linkIsBroken(
        self.hostIDForNodeID(a) orelse return InvalidNodeError.InvalidNode,
        self.hostIDForNodeID(b) orelse return InvalidNodeError.InvalidNode,
    );
}

pub fn setPartitionShapeWeights(self: *Simulator, weights: PartitionShapeWeights) void {
    self.partition_policy.weights = weights;
}

pub fn enablePartitionFaults(self: *Simulator, options: PartitionFaultOptions) void {
    std.debug.assert(options.min_interval_us > 0);
    std.debug.assert(options.min_interval_us <= options.max_interval_us);

    self.partition_fault_options = options;
    self.partition_policy.weights = options.weights;
    self.partition_target_selected = false;
    self.next_partition_step_time_us = self.scheduler.current_time;
}

pub fn disablePartitionFaults(self: *Simulator) void {
    self.enableFaults(false);
}

pub fn enableFaults(self: *Simulator, yes: bool) void {
    self.faults_enabled = yes;
    for (self.nodes.items) |node| {
        node.enableFaults(yes);
    }
    if (!yes)
        self.network.partitions.clear();
}

pub fn nowUs(self: *const Simulator) u64 {
    return self.scheduler.current_time;
}

pub fn pickPartitionTarget(self: *Simulator) Allocator.Error!PartitionShape {
    try self.refreshPartitionEndpoints();
    const shape = try self.partition_policy.pickTarget(self.partition_endpoints.items, self.prng.random());
    self.partition_target_selected = true;
    return shape;
}

pub fn setPartitionTarget(self: *Simulator, shape: PartitionShape) Allocator.Error!void {
    try self.refreshPartitionEndpoints();
    try self.partition_policy.setTarget(self.partition_endpoints.items, shape, self.prng.random());
    self.partition_target_selected = true;
}

pub fn driftPartitionOne(self: *Simulator) Allocator.Error!bool {
    try self.refreshPartitionEndpoints();
    return self.partition_policy.driftOne(&self.network.partitions, self.partition_endpoints.items, self.prng.random());
}

pub fn partitionAtTarget(self: *Simulator) Allocator.Error!bool {
    try self.refreshPartitionEndpoints();
    return self.partition_policy.atTarget(&self.network.partitions, self.partition_endpoints.items);
}

fn automaticPartitionStep(self: *Simulator) Allocator.Error!void {
    if (!self.faults_enabled)
        return;

    const now = self.scheduler.current_time;
    if (now < self.next_partition_step_time_us)
        return;

    try self.refreshPartitionEndpoints();
    if (self.partition_endpoints.items.len < 2)
        return;

    if (!self.partition_target_selected or self.partition_policy.atTarget(&self.network.partitions, self.partition_endpoints.items)) {
        _ = try self.partition_policy.pickTarget(self.partition_endpoints.items, self.prng.random());
        self.partition_target_selected = true;
    }

    _ = try self.partition_policy.driftOne(&self.network.partitions, self.partition_endpoints.items, self.prng.random());
    self.next_partition_step_time_us = std.math.add(u64, now, randomPartitionInterval(self)) catch std.math.maxInt(u64);
}

fn randomPartitionInterval(self: *Simulator) u64 {
    return self.randomIntervalUs(
        self.partition_fault_options.min_interval_us,
        self.partition_fault_options.max_interval_us,
    );
}

// Picks a live node at random and either crashes it (with cleanup decided by a
// coin flip) or, if it is already down and recoverable, restarts it. Like
// automaticPartitionStep, this is part of the unified fault system gated by
// faults_enabled and runs at randomized intervals.
fn automaticCrashStep(self: *Simulator) void {
    if (!self.faults_enabled)
        return;
    if (self.nodes.items.len == 0)
        return;

    const now = self.scheduler.current_time;
    if (now < self.next_crash_step_time_us)
        return;

    const random = self.prng.random();
    const node = self.nodes.items[random.uintLessThan(usize, self.nodes.items.len)];
    if (node.isAlive()) {
        node.crash(random.boolean());
    } else if (node.recoverable) {
        node.restart() catch {};
    }

    const interval = self.randomIntervalUs(CRASH_FAULT_MIN_INTERVAL_US, CRASH_FAULT_MAX_INTERVAL_US);
    self.next_crash_step_time_us = std.math.add(u64, now, interval) catch std.math.maxInt(u64);
}

fn randomIntervalUs(self: *Simulator, min: u64, max: u64) u64 {
    if (min == max)
        return min;

    return min + self.prng.random().uintLessThan(u64, max - min + 1);
}

fn hostIDForNodeID(self: *const Simulator, id: u32) ?Network.HostID {
    for (self.nodes.items) |node| {
        if (node.id == id) {
            if (!node.isAlive())
                return null;
            return node.runtime.?.network_host.id;
        }
    }
    return null;
}

fn refreshPartitionEndpoints(self: *Simulator) Allocator.Error!void {
    self.partition_endpoints.clearRetainingCapacity();
    for (self.nodes.items) |node| {
        if (node.isAlive())
            try self.partition_endpoints.append(self.gpa, node.runtime.?.network_host.id);
    }
}

pub fn setTraceOutputFile(self: *Simulator, path: []const u8) !void {
    try self.trace.setOutputFile(path);
}

pub fn addExecutable(self: *Simulator, name: []const u8, entry: EntryPoint) Allocator.Error!void {
    try self.executables.append(self.gpa, ExecutableName{
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

    try node.init(self.real_io, &self.trace, &self.prng, &self.scheduler, &self.network, node_id, command, options.addresses, entry, .{
        .stack_size = options.stack_size,
        .recoverable = options.recoverable,
    }, self.gpa);
    errdefer node.deinit();
    node.enableFaults(self.faults_enabled);

    try self.nodes.append(self.gpa, node);
}

pub fn scheduleOne(self: *Simulator) bool {
    self.events = 0;
    self.automaticPartitionStep() catch {};
    self.automaticCrashStep();
    if (self.scheduler.scheduleOne())
        return true;

    // No task is runnable (e.g. every node is crashed, so nothing is left to
    // advance the clock). While the crash injector could still bring a dead
    // node back, jump time forward to its next step so it fires and restarts
    // one, keeping the simulation alive.
    while (self.faults_enabled and self.hasRestartableNode()) {
        self.scheduler.advanceTimeTo(self.next_crash_step_time_us);
        self.automaticCrashStep();
        if (self.scheduler.scheduleOne())
            return true;
    }
    return false;
}

fn hasRestartableNode(self: *const Simulator) bool {
    for (self.nodes.items) |node| {
        if (!node.isAlive() and node.recoverable)
            return true;
    }
    return false;
}

pub fn eventRaised(self: *const Simulator, index: u32) bool {
    return (self.events & (@as(u32, 1) << @intCast(index))) != 0;
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
