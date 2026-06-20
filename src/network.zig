const std = @import("std");

const Network = @This();
const Allocator = std.mem.Allocator;
const Partition = @import("partition.zig");

pub const HostID = Partition.EndpointID;

pub const Address = struct {
    ipv4: u32,
    port: u16,
    pub fn eql(self: Address, other: Address) bool {
        return self.ipv4 == other.ipv4 and self.port == other.port;
    }
};

pub const ListenError = error{
    AddressNotAvailable,
    AddressAlreadyUsed,
} || Allocator.Error;

pub const AcceptError = error{
    AcceptQueueEmpty,
} || Allocator.Error;

pub const ConnectError = error{
    AddressNotAvailable,
    UnavailableHost,
    PeerNotListeningOnAddress,
} || Allocator.Error;

pub const SendError = error{
    NotConnected,
} || Allocator.Error;

pub const ReadError = error{};

pub const ListenSocket = struct {
    next: ?*ListenSocket,

    // A reference to the host is necessary as sockets from
    // other hosts need to be able to infer the host by just
    // the pointer to a socket.
    host: *Host,

    address: Address,
    accept_queue: std.ArrayList(*ConnSocket),
};

pub const ConnSocket = struct {
    next: ?*ConnSocket,

    // See comment on ListenSocket
    host: *Host,

    local_address: Address,
    remote_address: Address,
    peer_listen: ?*ListenSocket,
    peer_conn: ?*ConnSocket,

    input_buffer: std.ArrayList(u8),
    pending_output_buffer: std.ArrayList(u8),
};

pub const Host = struct {
    gpa: Allocator,
    id: HostID,

    // Parent network system
    network: *Network,

    listen_list: ?*ListenSocket,
    conn_list: ?*ConnSocket,

    available_addresses_ipv4: []const u32,

    pub fn init(self: *Host, network: *Network, addresses: []const u32, gpa: Allocator) void {
        self.gpa = gpa;
        self.id = 0;
        self.network = network;
        self.listen_list = null;
        self.conn_list = null;
        self.available_addresses_ipv4 = addresses;
    }

    pub fn deinit(self: *Host) void {
        while (self.conn_list) |s| {
            self.closeConnSocket(s);
        }

        while (self.listen_list) |s| {
            self.closeListenSocket(s);
        }

        self.network.unregisterHost(self);
    }

    fn linkConnSocket(self: *Host, socket: *ConnSocket) void {
        socket.host = self;
        socket.next = self.conn_list;
        self.conn_list = socket;
    }

    fn unlinkConnSocket(self: *Host, socket: *ConnSocket) void {
        var cursor = &self.conn_list;
        while (cursor.*) |item| {
            if (item == socket) {
                cursor.* = item.next;
                socket.next = null;
                return;
            }
            cursor = &item.next;
        }
    }

    fn linkListenSocket(self: *Host, socket: *ListenSocket) void {
        socket.host = self;
        socket.next = self.listen_list;
        self.listen_list = socket;
    }

    fn unlinkListenSocket(self: *Host, socket: *ListenSocket) void {
        var cursor = &self.listen_list;
        while (cursor.*) |item| {
            if (item == socket) {
                cursor.* = item.next;
                socket.next = null;
                return;
            }
            cursor = &item.next;
        }
    }

    fn addressCurrentlyUsed(self: *Host, address: Address) bool {
        var socket = self.listen_list;
        while (socket) |s| {
            if (s.address.eql(address))
                return true;
            socket = s.next;
        }
        return false;
    }

    pub fn isAddressAvailable(self: *Host, ipv4: u32) bool {
        for (self.available_addresses_ipv4) |item| {
            if (ipv4 == item)
                return true;
        }
        return false;
    }

    fn sourceAddress(self: *Host) ConnectError!Address {
        if (self.available_addresses_ipv4.len == 0)
            return ConnectError.AddressNotAvailable;
        return .{
            .ipv4 = self.available_addresses_ipv4[0],
            .port = 0,
        };
    }

    pub fn listen(self: *Host, address: Address, socket: *ListenSocket) ListenError!void {
        if (!self.isAddressAvailable(address.ipv4))
            return ListenError.AddressNotAvailable;

        if (self.addressCurrentlyUsed(address))
            return ListenError.AddressAlreadyUsed;

        socket.address = address;
        socket.accept_queue = .empty;

        self.linkListenSocket(socket);
    }

    pub fn accept(self: *Host, socket: *ListenSocket, new_socket: *ConnSocket) AcceptError!void {

        // Pop a connectioon from the listener's accept queue
        if (socket.accept_queue.items.len == 0)
            return AcceptError.AcceptQueueEmpty;
        const peer_socket = socket.accept_queue.orderedRemove(0);

        // Add newly created socket to the connection socket list
        self.linkConnSocket(new_socket);
        errdefer self.unlinkConnSocket(new_socket);

        // Initialize other fields
        new_socket.local_address = socket.address;
        new_socket.remote_address = peer_socket.local_address;
        new_socket.peer_listen = null;
        new_socket.input_buffer = .empty;
        new_socket.pending_output_buffer = .empty;
        try new_socket.input_buffer.appendSlice(self.gpa, peer_socket.pending_output_buffer.items);
        peer_socket.pending_output_buffer.clearRetainingCapacity();

        // Link the bound sockets and remove the reference to the listener
        new_socket.peer_conn = peer_socket;
        peer_socket.peer_conn = new_socket;
        peer_socket.peer_listen = null;
    }

    fn findListenSocket(self: *Host, address: Address) ?*ListenSocket {
        var socket = self.listen_list;
        while (socket) |s| {
            if (s.address.eql(address))
                return s;
            socket = s.next;
        }
        return null;
    }

    pub fn connect(self: *Host, address: Address, new_socket: *ConnSocket) ConnectError!void {
        const host = self.network.findHostByIPv4(address.ipv4) orelse return ConnectError.UnavailableHost;
        if (self.network.partitions.isBroken(self.id, host.id))
            return ConnectError.UnavailableHost;
        const listen_socket = host.findListenSocket(address) orelse return ConnectError.PeerNotListeningOnAddress;

        // Add newly created socket to the connection socket list
        self.linkConnSocket(new_socket);
        errdefer self.unlinkConnSocket(new_socket);

        new_socket.local_address = try self.sourceAddress();
        new_socket.remote_address = address;
        new_socket.peer_listen = listen_socket;
        new_socket.peer_conn = null;
        new_socket.input_buffer = .empty;
        new_socket.pending_output_buffer = .empty;

        // Add socket to the peer's accept queue
        //
        // Note that we're using the peer's allocator and not the local one. Very important!
        try listen_socket.accept_queue.append(host.gpa, new_socket);
    }

    pub fn closeConnSocket(self: *Host, socket: *ConnSocket) void {
        if (socket.peer_listen) |peer| {
            for (peer.accept_queue.items, 0..) |item, i| {
                if (item == socket) {
                    _ = peer.accept_queue.orderedRemove(i);
                    break;
                }
            }
        }

        if (socket.peer_conn) |peer| {
            peer.peer_conn = null;
        }

        self.unlinkConnSocket(socket);
        socket.input_buffer.deinit(self.gpa);
        socket.pending_output_buffer.deinit(self.gpa);
    }

    pub fn closeListenSocket(self: *Host, socket: *ListenSocket) void {
        for (socket.accept_queue.items) |peer| {
            peer.peer_listen = null;
        }

        self.unlinkListenSocket(socket);
        socket.accept_queue.deinit(self.gpa);
    }

    pub fn send(_: *Host, socket: *ConnSocket, source: []const u8) SendError!usize {
        if (socket.peer_conn) |peer_conn| {
            if (socket.host.network.partitions.isBroken(socket.host.id, peer_conn.host.id))
                return SendError.NotConnected;
            if (socket.pending_output_buffer.items.len > 0) {
                try peer_conn.input_buffer.appendSlice(peer_conn.host.gpa, socket.pending_output_buffer.items);
                socket.pending_output_buffer.clearRetainingCapacity();
            }
            try peer_conn.input_buffer.appendSlice(peer_conn.host.gpa, source);
        } else if (socket.peer_listen) |peer_listen| {
            if (socket.host.network.partitions.isBroken(socket.host.id, peer_listen.host.id))
                return SendError.NotConnected;
            try socket.pending_output_buffer.appendSlice(socket.host.gpa, source);
        } else {
            try socket.pending_output_buffer.appendSlice(socket.host.gpa, source);
        }
        return source.len;
    }

    pub fn read(_: *Host, socket: *ConnSocket, target: []u8) usize {
        const num = @min(target.len, socket.input_buffer.items.len);
        @memcpy(target[0..num], socket.input_buffer.items[0..num]);
        for (0..num) |_| {
            _ = socket.input_buffer.orderedRemove(0);
        }
        return num;
    }

    pub fn isConnected(_: *Host, socket: *ConnSocket) bool {
        return socket.peer_conn != null;
    }
};

gpa: Allocator,
hosts: std.ArrayList(*Host),
partitions: Partition,
next_host_id: HostID,

pub fn init(self: *Network, gpa: Allocator) void {
    self.gpa = gpa;
    self.hosts = .empty;
    self.partitions.init(gpa);
    self.next_host_id = 0;
}

pub fn deinit(self: *Network) void {
    self.partitions.deinit();
    self.hosts.deinit(self.gpa);
}

pub fn registerHost(self: *Network, host: *Host) Allocator.Error!void {
    try self.hosts.append(self.gpa, host);
    host.id = self.next_host_id;
    self.next_host_id += 1;
    host.network = self;
}

pub fn unregisterHost(self: *Network, host: *Host) void {
    for (self.hosts.items, 0..) |item, i| {
        if (item == host) {
            _ = self.hosts.swapRemove(i);
            return;
        }
    }
}

pub fn findHostByIPv4(self: *Network, ipv4: u32) ?*Host {
    for (self.hosts.items) |host| {
        if (host.isAddressAvailable(ipv4))
            return host;
    }
    return null;
}

pub fn breakLink(self: *Network, a: HostID, b: HostID) Allocator.Error!void {
    try self.partitions.breakLink(a, b);
}

pub fn healLink(self: *Network, a: HostID, b: HostID) void {
    self.partitions.healLink(a, b);
}

pub fn linkIsBroken(self: *const Network, a: HostID, b: HostID) bool {
    return self.partitions.isBroken(a, b);
}

test "partitioned connect reports unavailable host" {
    const allocator = std.testing.allocator;
    const address = Address{ .ipv4 = 1, .port = 8080 };

    var network: Network = undefined;
    network.init(allocator);
    defer network.deinit();

    var client: Host = undefined;
    client.init(&network, &.{2}, allocator);
    defer client.deinit();
    try network.registerHost(&client);

    var server: Host = undefined;
    server.init(&network, &.{address.ipv4}, allocator);
    defer server.deinit();
    try network.registerHost(&server);

    var listener: ListenSocket = undefined;
    try server.listen(address, &listener);

    try network.breakLink(client.id, server.id);

    var socket: ConnSocket = undefined;
    try std.testing.expectError(ConnectError.UnavailableHost, client.connect(address, &socket));
}

test "partitioned send fails without destroying existing connection" {
    const allocator = std.testing.allocator;
    const address = Address{ .ipv4 = 1, .port = 8080 };

    var network: Network = undefined;
    network.init(allocator);
    defer network.deinit();

    var client: Host = undefined;
    client.init(&network, &.{2}, allocator);
    defer client.deinit();
    try network.registerHost(&client);

    var server: Host = undefined;
    server.init(&network, &.{address.ipv4}, allocator);
    defer server.deinit();
    try network.registerHost(&server);

    var listener: ListenSocket = undefined;
    try server.listen(address, &listener);

    var client_socket: ConnSocket = undefined;
    try client.connect(address, &client_socket);

    var server_socket: ConnSocket = undefined;
    try server.accept(&listener, &server_socket);

    try network.breakLink(client.id, server.id);
    try std.testing.expectError(SendError.NotConnected, client.send(&client_socket, "hello"));

    network.healLink(client.id, server.id);
    try std.testing.expectEqual(@as(usize, 5), try client.send(&client_socket, "hello"));

    var buffer: [5]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 5), server.read(&server_socket, &buffer));
    try std.testing.expectEqualStrings("hello", &buffer);
}
