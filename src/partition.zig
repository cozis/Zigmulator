const std = @import("std");

const Allocator = std.mem.Allocator;

pub const EndpointID = u32;

pub const Link = struct {
    a: EndpointID,
    b: EndpointID,

    pub fn init(a: EndpointID, b: EndpointID) Link {
        return if (a <= b)
            .{ .a = a, .b = b }
        else
            .{ .a = b, .b = a };
    }

    pub fn eql(self: Link, other: Link) bool {
        return self.a == other.a and self.b == other.b;
    }
};

gpa: Allocator,
broken_links: std.ArrayList(Link),

pub fn init(self: *@This(), gpa: Allocator) void {
    self.gpa = gpa;
    self.broken_links = .empty;
}

pub fn deinit(self: *@This()) void {
    self.broken_links.deinit(self.gpa);
}

pub fn breakLink(self: *@This(), a: EndpointID, b: EndpointID) Allocator.Error!void {
    if (a == b)
        return;

    const link = Link.init(a, b);
    if (self.contains(link))
        return;

    try self.broken_links.append(self.gpa, link);
}

pub fn healLink(self: *@This(), a: EndpointID, b: EndpointID) void {
    const link = Link.init(a, b);
    for (self.broken_links.items, 0..) |item, i| {
        if (item.eql(link)) {
            _ = self.broken_links.swapRemove(i);
            return;
        }
    }
}

pub fn clear(self: *@This()) void {
    self.broken_links.clearRetainingCapacity();
}

pub fn isBroken(self: *const @This(), a: EndpointID, b: EndpointID) bool {
    if (a == b)
        return false;

    return self.contains(Link.init(a, b));
}

pub fn links(self: *const @This()) []const Link {
    return self.broken_links.items;
}

fn contains(self: *const @This(), link: Link) bool {
    for (self.broken_links.items) |item| {
        if (item.eql(link))
            return true;
    }
    return false;
}

test "broken links are symmetric" {
    var partition: @This() = undefined;
    partition.init(std.testing.allocator);
    defer partition.deinit();

    try partition.breakLink(1, 2);

    try std.testing.expect(partition.isBroken(1, 2));
    try std.testing.expect(partition.isBroken(2, 1));
    try std.testing.expect(!partition.isBroken(1, 1));
}

test "breaking the same link twice does not duplicate it" {
    var partition: @This() = undefined;
    partition.init(std.testing.allocator);
    defer partition.deinit();

    try partition.breakLink(1, 2);
    try partition.breakLink(2, 1);

    try std.testing.expectEqual(@as(usize, 1), partition.links().len);
}

test "healing a link removes only that link" {
    var partition: @This() = undefined;
    partition.init(std.testing.allocator);
    defer partition.deinit();

    try partition.breakLink(1, 2);
    try partition.breakLink(2, 3);

    partition.healLink(2, 1);

    try std.testing.expect(!partition.isBroken(1, 2));
    try std.testing.expect(partition.isBroken(2, 3));
}

test "clear heals every link" {
    var partition: @This() = undefined;
    partition.init(std.testing.allocator);
    defer partition.deinit();

    try partition.breakLink(1, 2);
    try partition.breakLink(3, 4);

    partition.clear();

    try std.testing.expectEqual(@as(usize, 0), partition.links().len);
    try std.testing.expect(!partition.isBroken(1, 2));
    try std.testing.expect(!partition.isBroken(3, 4));
}
