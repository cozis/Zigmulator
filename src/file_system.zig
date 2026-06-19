const std = @import("std");

const FileSystem = @This();
const Allocator = std.mem.Allocator;

const ENTITY_NAME_LIMIT = 127;
const MAX_PATH_COMPONENTS = 64;

const EntityChild = struct {
    name: [ENTITY_NAME_LIMIT]u8 = undefined,
    name_len: u16 = 0,
    addr: *Entity,

    fn init(name: []const u8, addr: *Entity) !EntityChild {
        var self: EntityChild = .{ .addr = addr };
        try self.setName(name);
        return self;
    }

    fn setName(self: *EntityChild, name: []const u8) !void {
        if (name.len > self.name.len)
            return error.OutOfMemory;
        @memcpy(self.name[0..name.len], name);
        self.name_len = @intCast(name.len);
    }

    fn getName(self: *const EntityChild) []const u8 {
        return self.name[0..self.name_len];
    }
};

const Entity = struct {
    is_dir: bool,
    ref_count: u32 = 0,
    children: std.ArrayList(EntityChild) = .empty,
    bytes: std.ArrayList(u8) = .empty,

    fn initDir(gpa: Allocator) Allocator.Error!*Entity {
        const self = try gpa.create(Entity);
        self.* = .{ .is_dir = true };
        return self;
    }

    fn initFile(gpa: Allocator) Allocator.Error!*Entity {
        const self = try gpa.create(Entity);
        self.* = .{ .is_dir = false };
        return self;
    }

    fn ref(self: *Entity) void {
        self.ref_count += 1;
    }

    fn deref(self: *Entity, gpa: Allocator) void {
        std.debug.assert(self.ref_count > 0);
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            for (self.children.items) |child| {
                child.addr.deref(gpa);
            }
            self.children.deinit(gpa);
            self.bytes.deinit(gpa);
            gpa.destroy(self);
        }
    }

    // Directory only
    fn findChildIndex(self: *Entity, name: []const u8) ?usize {
        std.debug.assert(self.is_dir);
        for (self.children.items, 0..) |child, i| {
            if (std.mem.eql(u8, child.getName(), name))
                return i;
        }
        return null;
    }

    // Directory only
    fn addChild(self: *Entity, gpa: Allocator, name: []const u8, addr: *Entity) !void {
        std.debug.assert(self.is_dir);
        if (self.findChildIndex(name) != null)
            return error.ExistsAlready;
        try self.children.append(gpa, try EntityChild.init(name, addr));
        addr.ref();
    }

    // Directory only
    fn findChild(self: *Entity, name: []const u8) ?*EntityChild {
        const index = self.findChildIndex(name) orelse return null;
        return &self.children.items[index];
    }

    // Directory only
    fn removeChild(self: *Entity, gpa: Allocator, name: []const u8) !void {
        const index = self.findChildIndex(name) orelse return error.NotFound;
        const removed = self.children.swapRemove(index);
        removed.addr.deref(gpa);
    }

    fn contains(self: *Entity, maybe_descendant: *Entity) bool {
        if (self == maybe_descendant)
            return true;
        if (!self.is_dir)
            return false;
        for (self.children.items) |child| {
            if (child.addr.contains(maybe_descendant))
                return true;
        }
        return false;
    }
};

pub const OpenDir = struct {
    entity: *Entity,
    cursor: usize = 0,
    name: [ENTITY_NAME_LIMIT]u8 = undefined,

    fn init(entity: *Entity) OpenDir {
        return .{ .entity = entity };
    }
};

pub const OpenFile = struct {
    entity: *Entity,
    cursor: usize = 0,

    fn init(entity: *Entity) OpenFile {
        return .{ .entity = entity };
    }
};

pub const ReadDir = struct {
    name: []const u8,
    is_dir: bool,
};

const ParsePathError = error{
    EmptyPath,
    NoRootParent,
    TooManyComponents,
};

const ResolvePathError = error{
    ResolutionLimit,
    ComponentNotDirectory,
    ComponentNotFound,
};

const ResolveParent = struct {
    parent: *Entity,
    basename: []const u8,
};

const ResolveParentError = ParsePathError || ResolvePathError;

pub const DeleteError = ResolveParentError || error{
    NotFound,
};

pub const DeleteFileError = DeleteError || error{
    IsDirectory,
};

pub const DeleteDirError = DeleteError || error{
    NotDirectory,
    DirNotEmpty,
};

pub const RenameError = ResolveParentError || error{
    NotFound,
    IsDirectory,
    NotDirectory,
    DirNotEmpty,
    OutOfMemory,
    AccessDenied,
};

pub const OpenError = error{
    IsDirectory,
    NotDirectory,
} || ParsePathError || ResolvePathError;

pub const ReadDirError = error{
    NoMoreItems,
};

pub const CreateError = error{
    ExistsAlready,
} || ResolveParentError || Allocator.Error;

root: *Entity,

pub fn init(self: *FileSystem, gpa: Allocator) !void {
    self.root = try Entity.initDir(gpa);
    self.root.ref();
}

pub fn deinit(self: *FileSystem, gpa: Allocator) void {
    self.root.deref(gpa);
}

fn parsePath(path: []const u8, buffer: [][]const u8) ParsePathError![]const []const u8 {
    var count: usize = 0;
    var cursor: usize = 0;

    if (path.len == 0)
        return ParsePathError.EmptyPath;

    var absolute = false;
    if (path[0] == '/') {
        absolute = true;
        cursor += 1;
    }

    while (cursor < path.len) {
        const start = cursor;
        while (cursor < path.len and path[cursor] != '/')
            cursor += 1;
        const component = path[start..cursor];

        if (cursor < path.len)
            cursor += 1;

        if (std.mem.eql(u8, component, "."))
            continue;

        if (std.mem.eql(u8, component, "..")) {
            if (count == 0)
                return ParsePathError.NoRootParent;
            count -= 1;
            continue;
        }

        if (count == buffer.len)
            return ParsePathError.TooManyComponents;
        buffer[count] = component;
        count += 1;
    }

    return buffer[0..count];
}

fn resolvePath(self: *FileSystem, components: []const []const u8, root: ?*Entity, buffer: []*Entity) ResolvePathError![]const *Entity {
    var count: usize = 1;
    buffer[0] = root orelse self.root;

    for (components) |component| {
        if (count == buffer.len)
            return ResolvePathError.ResolutionLimit;
        if (!buffer[count - 1].is_dir)
            return ResolvePathError.ComponentNotDirectory;
        const child = buffer[count - 1].findChild(component) orelse return ResolvePathError.ComponentNotFound;
        buffer[count] = child.addr;
        count += 1;
    }

    return buffer[0..count];
}

fn resolveParent(self: *FileSystem, path: []const u8, root: ?*Entity) !ResolveParent {
    var component_buffer: [MAX_PATH_COMPONENTS][]const u8 = undefined;
    var resolve_buffer: [MAX_PATH_COMPONENTS]*Entity = undefined;

    const components = try parsePath(path, &component_buffer);
    if (components.len == 0)
        return ResolveParentError.EmptyPath; // TODO: This error may not be right

    const path_to_parent = try self.resolvePath(components[0 .. components.len - 1], root, &resolve_buffer);
    const parent = path_to_parent[path_to_parent.len - 1];
    if (!parent.is_dir)
        return ResolveParentError.ComponentNotDirectory;

    return .{
        .parent = parent,
        .basename = components[components.len - 1],
    };
}

fn createAny(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, is_dir: bool, gpa: Allocator) CreateError!void {
    const result = try self.resolveParent(path, if (root_dir) |r| r.entity else null);

    const entity = try if (is_dir) Entity.initDir(gpa) else Entity.initFile(gpa);
    errdefer gpa.destroy(entity);

    try result.parent.addChild(gpa, result.basename, entity);
}

pub fn createFile(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, gpa: Allocator) CreateError!void {
    return self.createAny(path, root_dir, false, gpa);
}

pub fn createDir(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, gpa: Allocator) CreateError!void {
    return self.createAny(path, root_dir, true, gpa);
}

pub fn deleteFile(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, gpa: Allocator) DeleteFileError!void {
    const result = try self.resolveParent(path, if (root_dir) |r| r.entity else null);
    const child = result.parent.findChild(result.basename) orelse return DeleteFileError.NotFound;
    if (child.addr.is_dir)
        return DeleteFileError.IsDirectory;
    try result.parent.removeChild(gpa, result.basename);
}

pub fn deleteDir(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, gpa: Allocator) DeleteDirError!void {
    const result = try self.resolveParent(path, if (root_dir) |r| r.entity else null);
    const child = result.parent.findChild(result.basename) orelse return DeleteDirError.NotFound;
    if (!child.addr.is_dir)
        return DeleteDirError.NotDirectory;
    if (child.addr.children.items.len != 0)
        return DeleteDirError.DirNotEmpty;
    try result.parent.removeChild(gpa, result.basename);
}

pub fn rename(
    self: *FileSystem,
    old_path: []const u8,
    old_root_dir: ?*OpenDir,
    new_path: []const u8,
    new_root_dir: ?*OpenDir,
    gpa: Allocator,
) RenameError!void {
    const old = try self.resolveParent(old_path, if (old_root_dir) |r| r.entity else null);
    const new = try self.resolveParent(new_path, if (new_root_dir) |r| r.entity else null);

    const old_index = old.parent.findChildIndex(old.basename) orelse return RenameError.NotFound;
    const old_child = old.parent.children.items[old_index];

    if (old.parent == new.parent and std.mem.eql(u8, old.basename, new.basename))
        return;

    if (new.basename.len > ENTITY_NAME_LIMIT)
        return RenameError.OutOfMemory;

    if (old_child.addr.is_dir and old_child.addr.contains(new.parent))
        return RenameError.AccessDenied;

    const new_index_maybe = new.parent.findChildIndex(new.basename);
    if (new_index_maybe) |new_index| {
        const new_child = new.parent.children.items[new_index];
        if (old_child.addr.is_dir and !new_child.addr.is_dir)
            return RenameError.NotDirectory;
        if (!old_child.addr.is_dir and new_child.addr.is_dir)
            return RenameError.IsDirectory;
        if (new_child.addr.is_dir and new_child.addr.children.items.len != 0)
            return RenameError.DirNotEmpty;
    }

    if (old.parent == new.parent) {
        if (new_index_maybe) |new_index| {
            const removed = old.parent.children.swapRemove(new_index);
            removed.addr.deref(gpa);
        }
        const moved = old.parent.findChild(old.basename) orelse return RenameError.NotFound;
        moved.setName(new.basename) catch return RenameError.OutOfMemory;
        return;
    }

    if (new_index_maybe == null)
        try new.parent.children.ensureUnusedCapacity(gpa, 1);

    old_child.addr.ref();
    defer old_child.addr.deref(gpa);

    if (new_index_maybe) |new_index| {
        const removed = new.parent.children.swapRemove(new_index);
        removed.addr.deref(gpa);
    }

    try old.parent.removeChild(gpa, old.basename);
    new.parent.addChild(gpa, new.basename, old_child.addr) catch |err| switch (err) {
        error.ExistsAlready => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn openAny(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, open_dir: *OpenDir, open_file: *OpenFile) !bool {
    var component_buffer: [MAX_PATH_COMPONENTS][]const u8 = undefined;
    var resolve_buffer: [MAX_PATH_COMPONENTS]*Entity = undefined;

    const components = try parsePath(path, &component_buffer);
    if (components.len == 0)
        return OpenError.EmptyPath; // TODO: This error is not right

    const resolved = try self.resolvePath(components, if (root_dir) |r| r.entity else null, &resolve_buffer);
    if (resolved.len == 0)
        return OpenError.EmptyPath; // TODO: This error is not right

    const entity = resolved[resolved.len - 1];
    if (entity.is_dir) {
        open_dir.* = .init(entity);
    } else {
        open_file.* = .init(entity);
    }

    return entity.is_dir;
}

pub fn openDir(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, open_dir: *OpenDir) OpenError!void {
    var dummy: OpenFile = undefined;
    const is_dir = try self.openAny(path, root_dir, open_dir, &dummy);
    if (!is_dir) {
        return OpenError.NotDirectory;
    }
    open_dir.entity.ref();
}

pub fn openFile(self: *FileSystem, path: []const u8, root_dir: ?*OpenDir, open_file: *OpenFile) OpenError!void {
    var dummy: OpenDir = undefined;
    const is_dir = try self.openAny(path, root_dir, &dummy, open_file);
    if (is_dir) {
        return OpenError.IsDirectory;
    }
    open_file.entity.ref();
}

pub fn closeDir(self: *FileSystem, open_dir: *OpenDir, gpa: Allocator) void {
    _ = self;
    open_dir.entity.deref(gpa);
}

pub fn closeFile(self: *FileSystem, open_file: *OpenFile, gpa: Allocator) void {
    _ = self;
    open_file.entity.deref(gpa);
}

pub fn readDir(self: *FileSystem, open_dir: *OpenDir) ReadDirError!ReadDir {
    _ = self;

    if (open_dir.cursor == 0) {
        open_dir.cursor += 1;
        return .{ .name = ".", .is_dir = true };
    }

    if (open_dir.cursor == 1) {
        open_dir.cursor += 1;
        return .{ .name = "..", .is_dir = true };
    }

    const index = open_dir.cursor - 2;
    if (index == open_dir.entity.children.items.len)
        return ReadDirError.NoMoreItems;

    const child = open_dir.entity.children.items[index];
    const name = child.getName();
    @memcpy(open_dir.name[0..name.len], name);

    open_dir.cursor += 1;
    return .{
        .name = open_dir.name[0..name.len],
        .is_dir = child.addr.is_dir,
    };
}

pub fn resetDir(self: *FileSystem, open_dir: *OpenDir) void {
    _ = self;
    open_dir.cursor = 0;
}

pub fn readFile(self: *FileSystem, open_file: *OpenFile, offset_maybe: ?usize, target: []u8) usize {
    _ = self;
    const offset = offset_maybe orelse open_file.cursor;
    const source = open_file.entity.bytes.items[offset..];
    const num = @min(source.len, target.len);
    @memcpy(target[0..num], source[0..num]);
    if (offset_maybe == null)
        open_file.cursor += num;
    return num;
}

pub fn writeFile(self: *FileSystem, open_file: *OpenFile, gpa: Allocator, offset_maybe: ?usize, source: []const u8) Allocator.Error!void {
    _ = self;

    const offset = offset_maybe orelse open_file.cursor;

    const required_capacity = offset + source.len;
    const current_capacity = open_file.entity.bytes.items.len;
    if (required_capacity > current_capacity)
        try open_file.entity.bytes.appendNTimes(gpa, 0, required_capacity - current_capacity);

    const target = open_file.entity.bytes.items[offset..required_capacity];
    @memcpy(target, source);

    if (offset_maybe == null)
        open_file.cursor = required_capacity;
}

pub fn fileSize(self: *FileSystem, open_file: *OpenFile) usize {
    _ = self;
    return open_file.entity.bytes.items.len;
}

pub const SeekError = error{
    NegativeOffset,
    Overflow,
};

pub fn seekFileTo(self: *FileSystem, open_file: *OpenFile, offset: usize) void {
    _ = self;
    open_file.cursor = offset;
}

pub fn seekFileBy(self: *FileSystem, open_file: *OpenFile, offset: i64) SeekError!void {
    _ = self;
    if (offset < 0) {
        const delta: usize = @intCast(-offset);
        if (delta > open_file.cursor)
            return SeekError.NegativeOffset;
        open_file.cursor -= delta;
    } else {
        const delta: usize = @intCast(offset);
        open_file.cursor = std.math.add(usize, open_file.cursor, delta) catch return SeekError.Overflow;
    }
}

pub fn syncFile(self: *FileSystem, open_file: *OpenFile) void {
    _ = self;
    _ = open_file;
    // TODO
}

fn dumpEntity(entity: *Entity, depth: u32) void {
    if (entity.is_dir) {
        for (entity.children.items) |item| {
            for (0..depth) |_|
                std.debug.print("  ", .{});
            std.debug.print("{s}\n", .{item.getName()});
            dumpEntity(item.addr, depth + 1);
        }
    } else {
        for (0..depth) |_|
            std.debug.print("  ", .{});
        std.debug.print("[{s}]", .{entity.bytes.items});
    }
}

pub fn dump(self: *FileSystem) void {
    if (self.root.children.items.len == 0) {
        std.debug.print("(no files)\n", .{});
    } else {
        dumpEntity(self.root, 0);
        std.debug.print("\n", .{});
    }
}
