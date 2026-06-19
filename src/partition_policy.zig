const std = @import("std");

const Allocator = std.mem.Allocator;
const Partition = @import("partition.zig");

const PartitionPolicy = @This();

pub const EndpointID = Partition.EndpointID;

pub const Shape = enum {
    none,
    isolate_one,
    split_two_groups,
};

pub const ShapeWeights = struct {
    none: u32 = 50,
    isolate_one: u32 = 30,
    split_two_groups: u32 = 20,
};

gpa: Allocator,
target: Partition,
scratch: std.ArrayList(EndpointID),
weights: ShapeWeights,

pub fn init(self: *PartitionPolicy, gpa: Allocator, weights: ShapeWeights) void {
    self.gpa = gpa;
    self.target.init(gpa);
    self.scratch = .empty;
    self.weights = weights;
}

pub fn deinit(self: *PartitionPolicy) void {
    self.target.deinit();
    self.scratch.deinit(self.gpa);
}

pub fn pickTarget(self: *PartitionPolicy, endpoints: []const EndpointID, random: std.Random) Allocator.Error!Shape {
    const shape = pickShape(self.weights, random);
    try self.setTarget(endpoints, shape, random);
    return shape;
}

pub fn setTarget(self: *PartitionPolicy, endpoints: []const EndpointID, shape: Shape, random: std.Random) Allocator.Error!void {
    self.target.clear();

    switch (shape) {
        .none => {},
        .isolate_one => try self.targetIsolateOne(endpoints, random),
        .split_two_groups => try self.targetSplitTwoGroups(endpoints, random),
    }
}

pub fn driftOne(self: *PartitionPolicy, active: *Partition, endpoints: []const EndpointID, random: std.Random) Allocator.Error!bool {
    const differing_count = self.countDifferingLinks(active, endpoints);
    if (differing_count == 0)
        return false;

    var chosen = random.uintLessThan(usize, differing_count);
    for (endpoints, 0..) |a, i| {
        for (endpoints[i + 1 ..]) |b| {
            const should_be_broken = self.target.isBroken(a, b);
            const is_broken = active.isBroken(a, b);
            if (should_be_broken == is_broken)
                continue;

            if (chosen == 0) {
                if (should_be_broken) {
                    try active.breakLink(a, b);
                } else {
                    active.healLink(a, b);
                }
                return true;
            }
            chosen -= 1;
        }
    }

    unreachable;
}

pub fn atTarget(self: *const PartitionPolicy, active: *const Partition, endpoints: []const EndpointID) bool {
    return self.countDifferingLinks(active, endpoints) == 0;
}

pub fn targetLinks(self: *const PartitionPolicy) []const Partition.Link {
    return self.target.links();
}

fn pickShape(weights: ShapeWeights, random: std.Random) Shape {
    const total = weights.none + weights.isolate_one + weights.split_two_groups;
    if (total == 0)
        return .none;

    var pick = random.uintLessThan(u32, total);
    if (pick < weights.none)
        return .none;
    pick -= weights.none;

    if (pick < weights.isolate_one)
        return .isolate_one;

    return .split_two_groups;
}

fn targetIsolateOne(self: *PartitionPolicy, endpoints: []const EndpointID, random: std.Random) Allocator.Error!void {
    if (endpoints.len < 2)
        return;

    const isolated = endpoints[random.uintLessThan(usize, endpoints.len)];
    for (endpoints) |endpoint| {
        if (endpoint != isolated)
            try self.target.breakLink(isolated, endpoint);
    }
}

fn targetSplitTwoGroups(self: *PartitionPolicy, endpoints: []const EndpointID, random: std.Random) Allocator.Error!void {
    if (endpoints.len < 2)
        return;

    self.scratch.clearRetainingCapacity();
    try self.scratch.appendSlice(self.gpa, endpoints);
    shuffle(EndpointID, self.scratch.items, random);

    const split_index = 1 + random.uintLessThan(usize, endpoints.len - 1);
    const left = self.scratch.items[0..split_index];
    const right = self.scratch.items[split_index..];

    for (left) |a| {
        for (right) |b| {
            try self.target.breakLink(a, b);
        }
    }
}

fn countDifferingLinks(self: *const PartitionPolicy, active: *const Partition, endpoints: []const EndpointID) usize {
    var count: usize = 0;
    for (endpoints, 0..) |a, i| {
        for (endpoints[i + 1 ..]) |b| {
            if (self.target.isBroken(a, b) != active.isBroken(a, b))
                count += 1;
        }
    }
    return count;
}

fn shuffle(comptime T: type, items: []T, random: std.Random) void {
    if (items.len < 2)
        return;

    var i = items.len - 1;
    while (i > 0) : (i -= 1) {
        const j = random.uintLessThan(usize, i + 1);
        std.mem.swap(T, &items[i], &items[j]);
    }
}

test "none target has no broken links" {
    var prng = std.Random.DefaultPrng.init(0);
    const endpoints = [_]EndpointID{ 1, 2, 3 };

    var policy: PartitionPolicy = undefined;
    policy.init(std.testing.allocator, .{});
    defer policy.deinit();

    try policy.setTarget(&endpoints, .none, prng.random());

    try std.testing.expectEqual(@as(usize, 0), policy.targetLinks().len);
}

test "isolate one target breaks exactly one node away from the others" {
    var prng = std.Random.DefaultPrng.init(0);
    const endpoints = [_]EndpointID{ 1, 2, 3, 4 };

    var policy: PartitionPolicy = undefined;
    policy.init(std.testing.allocator, .{});
    defer policy.deinit();

    try policy.setTarget(&endpoints, .isolate_one, prng.random());

    try std.testing.expectEqual(@as(usize, endpoints.len - 1), policy.targetLinks().len);
}

test "split two groups target is neither empty nor fully disconnected" {
    var prng = std.Random.DefaultPrng.init(1);
    const endpoints = [_]EndpointID{ 1, 2, 3, 4 };

    var policy: PartitionPolicy = undefined;
    policy.init(std.testing.allocator, .{});
    defer policy.deinit();

    try policy.setTarget(&endpoints, .split_two_groups, prng.random());

    try std.testing.expect(policy.targetLinks().len > 0);
    try std.testing.expect(policy.targetLinks().len < 6);
}

test "drift one flips one differing link toward the target" {
    var prng = std.Random.DefaultPrng.init(2);
    const endpoints = [_]EndpointID{ 1, 2, 3 };

    var policy: PartitionPolicy = undefined;
    policy.init(std.testing.allocator, .{});
    defer policy.deinit();

    try policy.setTarget(&endpoints, .isolate_one, prng.random());

    var active: Partition = undefined;
    active.init(std.testing.allocator);
    defer active.deinit();

    try std.testing.expect(try policy.driftOne(&active, &endpoints, prng.random()));
    try std.testing.expectEqual(@as(usize, 1), active.links().len);
}
