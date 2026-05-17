
const std = @import("std");

const Network = @This();
const Allocator = std.mem.Allocator;

pub const Address = struct {
    ipv4: u32,
    port: u16,
    pub fn eql(self: Address, other: Address) bool {
        return self.ipv4 == other.ipv4
            and self.port == other.port;
    }
};

pub const ListenError = error {
    AddressNotAvailable,
    AddressAlreadyUsed,
} || Allocator.Error;

pub const AcceptError = error {
    AcceptQueueEmpty,
} || Allocator.Error;

pub const ConnectError = error {
    UnavailableHost,
    PeerNotListeningOnAddress,
} || Allocator.Error;

pub const SendError = Allocator.Error;
pub const ReadError = error {};

pub const ListenSocket = struct {

    next: ?*ListenSocket,

    address: Address,
    accept_queue: std.ArrayList(*ConnSocket),
};

pub const ConnSocket = struct {

    next: ?*ConnSocket,

    peer_listen: ?*ListenSocket,
    peer_conn  : ?*ConnSocket,

    input_buffer: std.ArrayList(u8),
    output_buffer: std.ArrayList(u8),
};

pub const Host = struct {

    gpa: Allocator,

    // Parent network system
    network: *Network,

    listen_list: ?*ListenSocket,
    conn_list: ?*ConnSocket,

    available_addresses_ipv4: []const u32,

    pub fn init(self: *Host, network: *Network, addresses: []const u32, gpa: Allocator) void {
        self.gpa = gpa;
        self.network = network;
        self.listen_list = null;
        self.conn_list = null;
        self.available_addresses_ipv4 = addresses;
    }

    pub fn deinit(self: *Host) void {
        _ = self;
    }

    fn linkConnSocket(self: *Host, socket: *ConnSocket) void {
        socket.next = self.conn_list;
        self.conn_list = socket;
    }

    fn unlinkConnSocket(self: *Host, socket: *ConnSocket) void {
        var cursor = self.conn_list.*; // Note that the list can't be empty or we wouldn't be unlinking
        if (cursor == socket) {
            self.conn_list = null;
        } else {
            while (cursor.next != socket)
                cursor = cursor.next.*;
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

    pub fn listen(self: *Host, address: Address, socket: *ListenSocket) ListenError!void {

        if (!self.isAddressAvailable(address.ipv4))
            return ListenError.AddressNotAvailable;

        if (self.addressCurrentlyUsed(address))
            return ListenError.AddressAlreadyUsed;

        socket.address = address;
        socket.accept_queue = .empty;

        // Add listen socket to the list
        socket.next = self.listen_list;
        self.listen_list = socket;
    }

    pub fn accept(self: *Host, socket: *ListenSocket, new_socket: *ConnSocket) AcceptError!void {

        // Pop a connectioon from the listener's accept queue
        if (socket.accept_queue.items.len == 0)
            return AcceptError.AcceptQueueEmpty;
        const peer_socket = socket.accept_queue.orderedRemove(0);

        // Add newly created socket to the connection socket list
        self.linkConnSocket(new_socket);
        errdefer self.unlinkConnSocket(new_socket);

        // Link the bound sockets and remove the reference to the listener
        new_socket.peer_conn = peer_socket;
        peer_socket.peer_conn = new_socket;
        peer_socket.peer_listen = null;

        // Initialize other fields
        new_socket.peer_listen = null;
        new_socket.input_buffer = .empty;
        new_socket.output_buffer = .empty;
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
        const listen_socket = host.findListenSocket(address) orelse return ConnectError.PeerNotListeningOnAddress;

        // Add newly created socket to the connection socket list
        self.linkConnSocket(new_socket);
        errdefer self.unlinkConnSocket(new_socket);

        new_socket.peer_listen = listen_socket;
        new_socket.peer_conn = null;
        new_socket.input_buffer = .empty;
        new_socket.output_buffer = .empty;

        // Add socket to the peer's accept queue
        try listen_socket.accept_queue.append(self.gpa, new_socket);
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
        socket.output_buffer.deinit(self.gpa);
    }

    pub fn closeListenSocket(self: *Host, socket: *ListenSocket) void {

        for (socket.accept_queue.items) |peer| {
            peer.peer_listen = null;
        }

        self.unlinkListenSocket(socket);
        socket.accept_queue.deinit(self.gpa);
    }

    pub fn send(self: *Host, socket: *ConnSocket, source: []const u8) usize {
        var n: usize = 0;
        for (source) |c| {
            socket.output_buffer.append(self.gpa, c) catch break;
            n += 1;
        }
        return n;
    }

    pub fn read(_: *Host, socket: *ConnSocket, target: []u8) usize {
        const num = @min(target.len, socket.input_buffer.items.len);
        @memcpy(target[0..num], socket.input_buffer.items[0..num]);
        for (0..num) |_| {
            socket.input_buffer.orderedRemove(0);
        }
        return num;
    }
};

gpa: Allocator,
hosts: std.ArrayList(*Host),

pub fn init(self: *Network, gpa: Allocator) void {
    self.gpa = gpa;
    self.hosts = .empty;
}

pub fn deinit(self: *Network) void {
    self.hosts.deinit(self.gpa);
}

pub fn registerHost(self: *Network, host: *Host) Allocator.Error!void {
    try self.hosts.append(self.gpa, host);
    host.network = self;
}

pub fn findHostByIPv4(self: *Network, ipv4: u32) ?*Host {
    for (self.hosts.items) |host| {
        if (host.isAddressAvailable(ipv4))
            return host;
    }
    return null;
}
