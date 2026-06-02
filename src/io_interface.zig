const std = @import("std");
const Node = @import("node.zig");

const Io = std.Io;
const net = Io.net;

const Dir               = Io.Dir;
const File              = Io.File;
const Group             = Io.Group;
const AnyFuture         = Io.AnyFuture;
const ConcurrentError   = Io.ConcurrentError;
const CancelProtection  = Io.CancelProtection;
const Cancelable        = Io.Cancelable;
const Timeout           = Io.Timeout;
const Operation         = Io.Operation;
const Batch             = Io.Batch;
const Terminal          = Io.Terminal;
const LockedStderr      = Io.LockedStderr;
const Clock             = Io.Clock;
const Timestamp         = Io.Timestamp;
const Duration          = Io.Duration;
const RandomSecureError = Io.RandomSecureError;
const Queue             = Io.Queue;
const Allocator         = std.mem.Allocator;

pub fn buildIOInterfaceForNode(node: *Node) Io {
    return .{
        .userdata = node,
        .vtable = &.{
            .crashHandler = crashHandler,

            .async = async,
            .concurrent = concurrent,
            .await = await,
            .cancel = cancel,

            .groupAsync = groupAsync,
            .groupConcurrent = groupConcurrent,
            .groupAwait = groupAwait,
            .groupCancel = groupCancel,

            .recancel = recancel,
            .swapCancelProtection = swapCancelProtection,
            .checkCancel = checkCancel,

            .futexWait = futexWait,
            .futexWaitUncancelable = futexWaitUncancelable,
            .futexWake = futexWake,

            .operate = operate,
            .batchAwaitAsync = batchAwaitAsync,
            .batchAwaitConcurrent = batchAwaitConcurrent,
            .batchCancel = batchCancel,

            .dirCreateDir = dirCreateDir,
            .dirCreateDirPath = dirCreateDirPath,
            .dirCreateDirPathOpen = dirCreateDirPathOpen,
            .dirOpenDir = dirOpenDir,
            .dirStat = dirStat,
            .dirStatFile = dirStatFile,
            .dirAccess = dirAccess,
            .dirCreateFile = dirCreateFile,
            .dirCreateFileAtomic = dirCreateFileAtomic,
            .dirOpenFile = dirOpenFile,
            .dirClose = dirClose,
            .dirRead = dirRead,
            .dirRealPath = dirRealPath,
            .dirRealPathFile = dirRealPathFile,
            .dirDeleteFile = dirDeleteFile,
            .dirDeleteDir = dirDeleteDir,
            .dirRename = dirRename,
            .dirRenamePreserve = dirRenamePreserve,
            .dirSymLink = dirSymLink,
            .dirReadLink = dirReadLink,
            .dirSetOwner = dirSetOwner,
            .dirSetFileOwner = dirSetFileOwner,
            .dirSetPermissions = dirSetPermissions,
            .dirSetFilePermissions = dirSetFilePermissions,
            .dirSetTimestamps = dirSetTimestamps,
            .dirHardLink = dirHardLink,

            .fileStat = fileStat,
            .fileLength = fileLength,
            .fileClose = fileClose,
            .fileWritePositional = fileWritePositional,
            .fileWriteFileStreaming = fileWriteFileStreaming,
            .fileWriteFilePositional = fileWriteFilePositional,
            .fileReadPositional = fileReadPositional,
            .fileSeekBy = fileSeekBy,
            .fileSeekTo = fileSeekTo,
            .fileSync = fileSync,
            .fileIsTty = fileIsTty,
            .fileEnableAnsiEscapeCodes = fileEnableAnsiEscapeCodes,
            .fileSupportsAnsiEscapeCodes = fileSupportsAnsiEscapeCodes,
            .fileSetLength = fileSetLength,
            .fileSetOwner = fileSetOwner,
            .fileSetPermissions = fileSetPermissions,
            .fileSetTimestamps = fileSetTimestamps,
            .fileLock = fileLock,
            .fileTryLock = fileTryLock,
            .fileUnlock = fileUnlock,
            .fileDowngradeLock = fileDowngradeLock,
            .fileRealPath = fileRealPath,
            .fileHardLink = fileHardLink,

            .fileMemoryMapCreate = fileMemoryMapCreate,
            .fileMemoryMapDestroy = fileMemoryMapDestroy,
            .fileMemoryMapSetLength = fileMemoryMapSetLength,
            .fileMemoryMapRead = fileMemoryMapRead,
            .fileMemoryMapWrite = fileMemoryMapWrite,

            .processExecutableOpen = processExecutableOpen,
            .processExecutablePath = processExecutablePath,
            .lockStderr = lockStderr,
            .tryLockStderr = tryLockStderr,
            .unlockStderr = unlockStderr,
            .processCurrentPath = processCurrentPath,
            .processSetCurrentDir = processSetCurrentDir,
            .processSetCurrentPath = processSetCurrentPath,
            .processReplace = processReplace,
            .processReplacePath = processReplacePath,
            .processSpawn = processSpawn,
            .processSpawnPath = processSpawnPath,
            .childWait = childWait,
            .childKill = childKill,

            .progressParentFile = progressParentFile,

            .random = random,
            .randomSecure = randomSecure,

            .now = now,
            .clockResolution = clockResolution,
            .sleep = sleep,

            .netListenIp = netListenIp,
            .netAccept = netAccept,
            .netBindIp = netBindIp,
            .netConnectIp = netConnectIp,
            .netListenUnix = netListenUnix,
            .netConnectUnix = netConnectUnix,
            .netSocketCreatePair = netSocketCreatePair,
            .netSend = netSend,
            .netRead = netRead,
            .netWrite = netWrite,
            .netWriteFile = netWriteFile,
            .netClose = netClose,
            .netShutdown = netShutdown,
            .netInterfaceNameResolve = netInterfaceNameResolve,
            .netInterfaceName = netInterfaceName,
            .netLookup = netLookup,
        },
    };
}

fn crashHandler(userdata: ?*anyopaque) void {
    _ = userdata;
    @panic("Not implemented yet");
}

fn async(
    userdata: ?*anyopaque,
    result: []u8,
    result_alignment: std.mem.Alignment,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*AnyFuture {
    _ = userdata;
    _ = result;
    _ = result_alignment;
    _ = context;
    _ = context_alignment;
    _ = start;
    @panic("Not implemented yet");
}

fn concurrent(
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: std.mem.Alignment,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ConcurrentError!*AnyFuture {
    _ = userdata;
    _ = result_len;
    _ = result_alignment;
    _ = context;
    _ = context_alignment;
    _ = start;
    @panic("Not implemented yet");
}

fn await(
    userdata: ?*anyopaque,
    future: *AnyFuture,
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = userdata;
    _ = future;
    _ = result;
    _ = result_alignment;
    @panic("Not implemented yet");
}

fn cancel(
    userdata: ?*anyopaque,
    future: *AnyFuture,
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = userdata;
    _ = future;
    _ = result;
    _ = result_alignment;
    @panic("Not implemented yet");
}

fn groupAsync(
    userdata: ?*anyopaque,
    type_erased: *Group,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque) void,
) void {
    _ = userdata;
    _ = type_erased;
    _ = context_alignment;
    start(context.ptr);
}

fn groupConcurrent(
    userdata: ?*anyopaque,
    type_erased: *Group,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque) void,
) ConcurrentError!void {
    _ = userdata;
    _ = type_erased;
    _ = context;
    _ = context_alignment;
    _ = start;
    @panic("Not implemented yet");
}

fn groupAwait(userdata: ?*anyopaque, type_erased: *Group, initial_token: *anyopaque) Cancelable!void {
    _ = userdata;
    _ = type_erased;
    _ = initial_token;
    @panic("Not implemented yet");
}

fn groupCancel(userdata: ?*anyopaque, type_erased: *Group, initial_token: *anyopaque) void {
    _ = userdata;
    _ = type_erased;
    _ = initial_token;
    @panic("Not implemented yet");
}

fn recancel(userdata: ?*anyopaque) void {
    _ = userdata;
    @panic("Not implemented yet");
}

fn swapCancelProtection(userdata: ?*anyopaque, new: CancelProtection) CancelProtection {
    _ = userdata;
    _ = new;
    @panic("Not implemented yet");
}

fn checkCancel(userdata: ?*anyopaque) Cancelable!void {
    _ = userdata;
    @panic("Not implemented yet");
}

fn futexWait(userdata: ?*anyopaque, ptr: *const u32, expected: u32, timeout: Timeout) Cancelable!void {
    _ = userdata;
    _ = ptr;
    _ = expected;
    _ = timeout;
    @panic("Not implemented yet");
}

fn futexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
    _ = userdata;
    _ = ptr;
    _ = expected;
    @panic("Not implemented yet");
}

fn futexWake(userdata: ?*anyopaque, ptr: *const u32, max_waiters: u32) void {
    _ = userdata;
    _ = ptr;
    _ = max_waiters;
    @panic("Not implemented yet");
}

fn operate(userdata: ?*anyopaque, operation: Operation) Cancelable!Operation.Result {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    return switch (operation) {
        .file_write_streaming => |op| .{
            .file_write_streaming = fileWriteStreaming(node, op),
        },
        else => @panic("Not implemented yet"),
    };
}

fn fileWriteStreaming(node: *Node, op: Operation.FileWriteStreaming) Operation.FileWriteStreaming.Result {
    var copied: usize = 0;
    copied += writeFile(node, op.file, null, op.header, op.data[0 .. op.data.len - 1]) catch |err| return err;

    const pattern = op.data[op.data.len - 1];
    for (0..op.splat) |_| {
        copied += writeFile(node, op.file, null, &.{}, &.{pattern}) catch |err| return err;
    }
    return copied;
}

fn writeFile(node: *Node, file: File, offset: ?usize, header: []const u8, data: []const []const u8) Operation.FileWriteStreaming.Error!usize {
    return node.writeFile(file.handle, offset, header, data) catch |err| switch (err) {
        error.InvalidHandle => error.NotOpenForWriting,
        error.OutOfMemory => error.SystemResources,
    };
}

fn batchAwaitAsync(userdata: ?*anyopaque, batch: *Batch) Cancelable!void {
    _ = userdata;
    _ = batch;
    @panic("Not implemented yet");
}

fn batchAwaitConcurrent(userdata: ?*anyopaque, batch: *Batch, timeout: Timeout) Batch.AwaitConcurrentError!void {
    _ = userdata;
    _ = batch;
    _ = timeout;
    @panic("Not implemented yet");
}

fn batchCancel(userdata: ?*anyopaque, batch: *Batch) void {
    _ = userdata;
    _ = batch;
    @panic("Not implemented yet");
}

fn dirCreateDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirError!void {
    _ = permissions; // TODO: Use permissions

    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const parent = if (dir.handle == Dir.cwd().handle) null else dir.handle;

    node.createDir(parent, sub_path) catch |e| {
        return switch (e) {
            Node.CreateDirError.InvalidHandle          => unreachable,
            Node.CreateDirError.ExistsAlready          => Dir.CreateDirError.PathAlreadyExists,
            Node.CreateDirError.EmptyPath              => Dir.CreateDirError.BadPathName,
            Node.CreateDirError.NoRootParent           => Dir.CreateDirError.FileNotFound,
            Node.CreateDirError.TooManyComponents      => Dir.CreateDirError.NameTooLong,
            Node.CreateDirError.ResolutionLimit        => Dir.CreateDirError.NameTooLong,
            Node.CreateDirError.ComponentNotDirectory  => Dir.CreateDirError.NotDir,
            Node.CreateDirError.ComponentNotFound      => Dir.CreateDirError.FileNotFound,
            Node.CreateDirError.OutOfMemory            => Dir.CreateDirError.SystemResources,
        };
    };
}

fn dirCreateDirPath(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirPathError!Dir.CreatePathStatus {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = permissions;
    @panic("Not implemented yet");
}

fn dirCreateDirPathOpen(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions, options: Dir.OpenOptions) Dir.CreateDirPathOpenError!Dir {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = permissions;
    _ = options;
    @panic("Not implemented yet");
}

fn dirOpenDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.OpenOptions) Dir.OpenError!Dir {
    _ = options; // TODO: Use options

    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const parent = if (dir.handle == Dir.cwd().handle) null else dir.handle;

    const handle = node.openDir(parent, sub_path) catch |e| {
        return switch (e) {
            Node.OpenDirError.InvalidHandle            => unreachable,
            Node.OpenDirError.DescriptorLimit          => Dir.OpenError.ProcessFdQuotaExceeded,
            Node.OpenDirError.IsDirectory              => unreachable,
            Node.OpenDirError.NotDirectory             => Dir.OpenError.NotDir,
            Node.OpenDirError.EmptyPath                => Dir.OpenError.BadPathName,
            Node.OpenDirError.NoRootParent             => Dir.OpenError.FileNotFound,
            Node.OpenDirError.TooManyComponents        => Dir.OpenError.NameTooLong,
            Node.OpenDirError.ResolutionLimit          => Dir.OpenError.NameTooLong,
            Node.OpenDirError.ComponentNotDirectory    => Dir.OpenError.NotDir,
            Node.OpenDirError.ComponentNotFound        => Dir.OpenError.FileNotFound,
        };
    };

    return .{ .handle = handle };
}

fn dirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    _ = userdata;
    _ = dir;
    @panic("Not implemented yet");
}

fn dirStatFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.StatFileOptions) Dir.StatFileError!File.Stat {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = options;
    @panic("Not implemented yet");
}

fn dirAccess(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.AccessOptions) Dir.AccessError!void {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = options;
    @panic("Not implemented yet");
}

fn dirCreateFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, flags: Dir.CreateFileOptions) File.OpenError!File {
    _ = flags; // TODO: Use flags

    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const parent = if (dir.handle == Dir.cwd().handle) null else dir.handle;

    node.createFile(parent, sub_path) catch |e| {
        return switch (e) {
            Node.CreateFileError.InvalidHandle          => unreachable,
            Node.CreateFileError.ExistsAlready          => File.OpenError.PathAlreadyExists,
            Node.CreateFileError.EmptyPath              => File.OpenError.BadPathName,
            Node.CreateFileError.NoRootParent           => File.OpenError.FileNotFound,
            Node.CreateFileError.TooManyComponents      => File.OpenError.NameTooLong,
            Node.CreateFileError.ResolutionLimit        => File.OpenError.NameTooLong,
            Node.CreateFileError.ComponentNotDirectory  => File.OpenError.NotDir,
            Node.CreateFileError.ComponentNotFound      => File.OpenError.FileNotFound,
            Node.CreateFileError.OutOfMemory            => File.OpenError.SystemResources,
        };
    };

    const handle = node.openFile(parent, sub_path) catch |e| {
        return switch (e) {
            Node.OpenFileError.InvalidHandle            => unreachable,
            Node.OpenFileError.DescriptorLimit          => File.OpenError.ProcessFdQuotaExceeded,
            Node.OpenFileError.IsDirectory              => File.OpenError.IsDir,
            Node.OpenFileError.NotDirectory             => File.OpenError.NotDir,
            Node.OpenFileError.EmptyPath                => File.OpenError.BadPathName,
            Node.OpenFileError.NoRootParent             => File.OpenError.FileNotFound,
            Node.OpenFileError.TooManyComponents        => File.OpenError.NameTooLong,
            Node.OpenFileError.ResolutionLimit          => File.OpenError.NameTooLong,
            Node.OpenFileError.ComponentNotDirectory    => File.OpenError.NotDir,
            Node.OpenFileError.ComponentNotFound        => File.OpenError.FileNotFound,
        };
    };

    return .{
        .handle = handle,
        .flags = .{ .nonblocking = false },
    };
}

fn dirCreateFileAtomic(userdata: ?*anyopaque, dir: Dir, dest_path: []const u8, options: Dir.CreateFileAtomicOptions) Dir.CreateFileAtomicError!File.Atomic {
    _ = userdata;
    _ = dir;
    _ = dest_path;
    _ = options;
    @panic("Not implemented yet");
}

fn dirOpenFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, flags: Dir.OpenFileOptions) File.OpenError!File {
    _ = flags; // TODO: Use flags

    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const parent = if (dir.handle == Dir.cwd().handle) null else dir.handle;

    const handle = node.openFile(parent, sub_path) catch |e| {
        return switch (e) {
            Node.OpenFileError.InvalidHandle            => unreachable,
            Node.OpenFileError.DescriptorLimit          => File.OpenError.ProcessFdQuotaExceeded,
            Node.OpenFileError.IsDirectory              => File.OpenError.IsDir,
            Node.OpenFileError.NotDirectory             => File.OpenError.NotDir,
            Node.OpenFileError.EmptyPath                => File.OpenError.BadPathName,
            Node.OpenFileError.NoRootParent             => File.OpenError.FileNotFound,
            Node.OpenFileError.TooManyComponents        => File.OpenError.NameTooLong,
            Node.OpenFileError.ResolutionLimit          => File.OpenError.NameTooLong,
            Node.OpenFileError.ComponentNotDirectory    => File.OpenError.NotDir,
            Node.OpenFileError.ComponentNotFound        => File.OpenError.FileNotFound,
        };
    };

    return .{
        .handle = handle,
        .flags = .{ .nonblocking = false },
    };
}

fn dirClose(userdata: ?*anyopaque, dirs: []const Dir) void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    for (dirs) |dir| {
        if (dir.handle == Dir.cwd().handle)
            continue;
        node.closeDir(dir.handle) catch {};
    }
}

fn dirRead(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const node: *Node = @ptrCast(@alignCast(userdata.?));

    if (dr.state == .finished)
        return 0;

    if (dr.state == .reset) {
        node.resetDir(dr.dir.handle) catch |e| switch (e) {
            error.InvalidHandle => return Dir.Reader.Error.AccessDenied,
        };
        dr.state = .reading;
    }

    var count: usize = 0;
    while (count < buffer.len) {
        const entry = node.readDir(dr.dir.handle) catch |e| switch (e) {
            error.InvalidHandle => return Dir.Reader.Error.AccessDenied,
            error.NoMoreItems => {
                dr.state = .finished;
                return count;
            },
        };

        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, ".."))
            continue;

        buffer[count] = .{
            .name = entry.name,
            .kind = if (entry.is_dir) .directory else .file,
            .inode = 0,
        };
        count += 1;
    }

    return count;
}

fn dirRealPath(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize {
    _ = userdata;
    _ = dir;
    _ = out_buffer;
    @panic("Not implemented yet");
}

fn dirRealPathFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, out_buffer: []u8) Dir.RealPathFileError!usize {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = out_buffer;
    @panic("Not implemented yet");
}

fn dirDeleteFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const parent = if (dir.handle == Dir.cwd().handle) null else dir.handle;

    node.deleteFile(parent, sub_path) catch |e| {
        return switch (e) {
            Node.DeleteFileError.InvalidHandle => unreachable,
            Node.DeleteFileError.EmptyPath => Dir.DeleteFileError.BadPathName,
            Node.DeleteFileError.NoRootParent => Dir.DeleteFileError.FileNotFound,
            Node.DeleteFileError.TooManyComponents => Dir.DeleteFileError.NameTooLong,
            Node.DeleteFileError.ResolutionLimit => Dir.DeleteFileError.NameTooLong,
            Node.DeleteFileError.ComponentNotDirectory => Dir.DeleteFileError.NotDir,
            Node.DeleteFileError.ComponentNotFound => Dir.DeleteFileError.FileNotFound,
            Node.DeleteFileError.NotFound => Dir.DeleteFileError.FileNotFound,
            Node.DeleteFileError.IsDirectory => Dir.DeleteFileError.IsDir,
        };
    };
}

fn dirDeleteDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const parent = if (dir.handle == Dir.cwd().handle) null else dir.handle;

    node.deleteDir(parent, sub_path) catch |e| {
        return switch (e) {
            Node.DeleteDirError.InvalidHandle          => unreachable,
            Node.DeleteDirError.EmptyPath              => Dir.DeleteDirError.BadPathName,
            Node.DeleteDirError.NoRootParent           => Dir.DeleteDirError.FileNotFound,
            Node.DeleteDirError.TooManyComponents      => Dir.DeleteDirError.NameTooLong,
            Node.DeleteDirError.ResolutionLimit        => Dir.DeleteDirError.NameTooLong,
            Node.DeleteDirError.ComponentNotDirectory  => Dir.DeleteDirError.NotDir,
            Node.DeleteDirError.ComponentNotFound      => Dir.DeleteDirError.FileNotFound,
            Node.DeleteDirError.NotFound               => Dir.DeleteDirError.FileNotFound,
            Node.DeleteDirError.NotDirectory           => Dir.DeleteDirError.NotDir,
            Node.DeleteDirError.DirNotEmpty            => Dir.DeleteDirError.DirNotEmpty,
        };
    };
}

fn dirRename(userdata: ?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) Dir.RenameError!void {
    _ = userdata;
    _ = old_dir;
    _ = old_sub_path;
    _ = new_dir;
    _ = new_sub_path;
    @panic("Not implemented yet");
}

fn dirRenamePreserve(userdata: ?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) Dir.RenamePreserveError!void {
    _ = userdata;
    _ = old_dir;
    _ = old_sub_path;
    _ = new_dir;
    _ = new_sub_path;
    @panic("Not implemented yet");
}

fn dirSymLink(userdata: ?*anyopaque, dir: Dir, target_path: []const u8, sym_link_path: []const u8, flags: Dir.SymLinkFlags) Dir.SymLinkError!void {
    _ = userdata;
    _ = dir;
    _ = target_path;
    _ = sym_link_path;
    _ = flags;
    @panic("Not implemented yet");
}

fn dirReadLink(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = buffer;
    @panic("Not implemented yet");
}

fn dirSetOwner(userdata: ?*anyopaque, dir: Dir, owner: ?File.Uid, group: ?File.Gid) Dir.SetOwnerError!void {
    _ = userdata;
    _ = dir;
    _ = owner;
    _ = group;
    @panic("Not implemented yet");
}

fn dirSetFileOwner(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, owner: ?File.Uid, group: ?File.Gid, options: Dir.SetFileOwnerOptions) Dir.SetFileOwnerError!void {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = owner;
    _ = group;
    _ = options;
    @panic("Not implemented yet");
}

fn dirSetPermissions(userdata: ?*anyopaque, dir: Dir, permissions: Dir.Permissions) Dir.SetPermissionsError!void {
    _ = userdata;
    _ = dir;
    _ = permissions;
    @panic("Not implemented yet");
}

fn dirSetFilePermissions(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: File.Permissions, options: Dir.SetFilePermissionsOptions) Dir.SetFilePermissionsError!void {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = permissions;
    _ = options;
    @panic("Not implemented yet");
}

fn dirSetTimestamps(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.SetTimestampsOptions) Dir.SetTimestampsError!void {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = options;
    @panic("Not implemented yet");
}

fn dirHardLink(userdata: ?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8, options: Dir.HardLinkOptions) Dir.HardLinkError!void {
    _ = userdata;
    _ = old_dir;
    _ = old_sub_path;
    _ = new_dir;
    _ = new_sub_path;
    _ = options;
    @panic("Not implemented yet");
}

fn fileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    return node.fileSize(file.handle) catch |e| switch (e) {
        error.InvalidHandle => File.LengthError.Streaming,
    };
}

fn fileClose(userdata: ?*anyopaque, files: []const File) void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    for (files) |file| {
        node.closeFile(file.handle) catch {};
    }
}

fn fileWritePositional(
    userdata: ?*anyopaque,
    file    : File,
    header  : []const u8,
    data    : []const []const u8,
    splat   : usize,
    offset  : u64
) File.WritePositionalError!usize {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    var cursor = std.math.cast(usize, offset) orelse return File.WritePositionalError.FileTooBig;
    var copied: usize = 0;

    if (header.len != 0) {
        const written = node.writeFile(file.handle, cursor, header, &.{}) catch |err| switch (err) {
            error.InvalidHandle => return File.WritePositionalError.NotOpenForWriting,
            error.OutOfMemory => return File.WritePositionalError.SystemResources,
        };
        cursor = std.math.add(usize, cursor, written) catch return File.WritePositionalError.FileTooBig;
        copied += written;
    }

    if (data.len != 0) {
        for (data[0 .. data.len - 1]) |bytes| {
            if (bytes.len == 0)
                continue;
            const written = node.writeFile(file.handle, cursor, bytes, &.{}) catch |err| switch (err) {
                error.InvalidHandle => return File.WritePositionalError.NotOpenForWriting,
                error.OutOfMemory => return File.WritePositionalError.SystemResources,
            };
            cursor = std.math.add(usize, cursor, written) catch return File.WritePositionalError.FileTooBig;
            copied += written;
        }

        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            if (pattern.len == 0)
                break;
            const written = node.writeFile(file.handle, cursor, pattern, &.{}) catch |err| switch (err) {
                error.InvalidHandle => return File.WritePositionalError.NotOpenForWriting,
                error.OutOfMemory => return File.WritePositionalError.SystemResources,
            };
            cursor = std.math.add(usize, cursor, written) catch return File.WritePositionalError.FileTooBig;
            copied += written;
        }
    }

    return copied;
}

fn fileWriteFileStreaming(userdata: ?*anyopaque, file: File, header: []const u8, file_reader: *Io.File.Reader, limit: Io.Limit) File.Writer.WriteFileError!usize {
    _ = userdata;
    _ = file;
    _ = header;
    _ = file_reader;
    _ = limit;
    @panic("Not implemented yet");
}

fn fileWriteFilePositional(userdata: ?*anyopaque, file: File, header: []const u8, file_reader: *Io.File.Reader, limit: Io.Limit, offset: u64) File.WriteFilePositionalError!usize {
    _ = userdata;
    _ = file;
    _ = header;
    _ = file_reader;
    _ = limit;
    _ = offset;
    @panic("Not implemented yet");
}

fn fileReadPositional(userdata: ?*anyopaque, file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize {
    const node: *Node = @ptrCast(@alignCast(userdata.?));

    var copied: usize = 0;
    for (data) |buffer| {
        const bytes_read = node.readFile(file.handle, @intCast(offset + copied), buffer) catch |e| {
            return switch (e) {
                error.InvalidHandle => File.ReadPositionalError.NotOpenForReading,
            };
        };
        copied += bytes_read;
        if (bytes_read < buffer.len)
            break;
    }
    return copied;
}

fn fileSeekBy(userdata: ?*anyopaque, file: File, offset: i64) File.SeekError!void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    node.seekFileBy(file.handle, offset) catch |err| switch (err) {
        error.InvalidHandle => return File.SeekError.AccessDenied,
        error.NegativeOffset, error.Overflow => return File.SeekError.Unseekable,
    };
}

fn fileSeekTo(userdata: ?*anyopaque, file: File, offset: u64) File.SeekError!void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));
    const offset_usize = std.math.cast(usize, offset) orelse return File.SeekError.Unseekable;
    node.seekFileTo(file.handle, offset_usize) catch |err| switch (err) {
        error.InvalidHandle => return File.SeekError.AccessDenied,
        error.NegativeOffset, error.Overflow => return File.SeekError.Unseekable,
    };
}

fn fileSync(userdata: ?*anyopaque, file: File) File.SyncError!void {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileIsTty(userdata: ?*anyopaque, file: File) Cancelable!bool {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileEnableAnsiEscapeCodes(userdata: ?*anyopaque, file: File) File.EnableAnsiEscapeCodesError!void {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileSupportsAnsiEscapeCodes(userdata: ?*anyopaque, file: File) Cancelable!bool {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileSetLength(userdata: ?*anyopaque, file: File, length: u64) File.SetLengthError!void {
    _ = userdata;
    _ = file;
    _ = length;
    @panic("Not implemented yet");
}

fn fileSetOwner(userdata: ?*anyopaque, file: File, owner: ?File.Uid, group: ?File.Gid) File.SetOwnerError!void {
    _ = userdata;
    _ = file;
    _ = owner;
    _ = group;
    @panic("Not implemented yet");
}

fn fileSetPermissions(userdata: ?*anyopaque, file: File, permissions: File.Permissions) File.SetPermissionsError!void {
    _ = userdata;
    _ = file;
    _ = permissions;
    @panic("Not implemented yet");
}

fn fileSetTimestamps(userdata: ?*anyopaque, file: File, options: File.SetTimestampsOptions) File.SetTimestampsError!void {
    _ = userdata;
    _ = file;
    _ = options;
    @panic("Not implemented yet");
}

fn fileLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!void {
    _ = userdata;
    _ = file;
    _ = lock;
    @panic("Not implemented yet");
}

fn fileTryLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!bool {
    _ = userdata;
    _ = file;
    _ = lock;
    @panic("Not implemented yet");
}

fn fileUnlock(userdata: ?*anyopaque, file: File) void {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileDowngradeLock(userdata: ?*anyopaque, file: File) File.DowngradeLockError!void {
    _ = userdata;
    _ = file;
    @panic("Not implemented yet");
}

fn fileRealPath(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize {
    _ = userdata;
    _ = file;
    _ = out_buffer;
    @panic("Not implemented yet");
}

fn fileHardLink(userdata: ?*anyopaque, file: File, new_dir: Dir, new_sub_path: []const u8, options: File.HardLinkOptions) File.HardLinkError!void {
    _ = userdata;
    _ = file;
    _ = new_dir;
    _ = new_sub_path;
    _ = options;
    @panic("Not implemented yet");
}

fn fileMemoryMapCreate(userdata: ?*anyopaque, file: File, options: File.MemoryMap.CreateOptions) File.MemoryMap.CreateError!File.MemoryMap {
    _ = userdata;
    _ = file;
    _ = options;
    @panic("Not implemented yet");
}

fn fileMemoryMapDestroy(userdata: ?*anyopaque, mm: *File.MemoryMap) void {
    _ = userdata;
    _ = mm;
    @panic("Not implemented yet");
}

fn fileMemoryMapSetLength(userdata: ?*anyopaque, mm: *File.MemoryMap, new_len: usize) File.MemoryMap.SetLengthError!void {
    _ = userdata;
    _ = mm;
    _ = new_len;
    @panic("Not implemented yet");
}

fn fileMemoryMapRead(userdata: ?*anyopaque, mm: *File.MemoryMap) File.ReadPositionalError!void {
    _ = userdata;
    _ = mm;
    @panic("Not implemented yet");
}

fn fileMemoryMapWrite(userdata: ?*anyopaque, mm: *File.MemoryMap) File.WritePositionalError!void {
    _ = userdata;
    _ = mm;
    @panic("Not implemented yet");
}

fn processExecutableOpen(userdata: ?*anyopaque, flags: Dir.OpenFileOptions) std.process.OpenExecutableError!File {
    _ = userdata;
    _ = flags;
    @panic("Not implemented yet");
}

fn processExecutablePath(userdata: ?*anyopaque, out_buffer: []u8) std.process.ExecutablePathError!usize {
    _ = userdata;
    _ = out_buffer;
    @panic("Not implemented yet");
}

fn lockStderr(userdata: ?*anyopaque, terminal_mode: ?Terminal.Mode) Cancelable!LockedStderr {
    _ = userdata;
    _ = terminal_mode;
    @panic("Not implemented yet");
}

fn tryLockStderr(userdata: ?*anyopaque, terminal_mode: ?Terminal.Mode) Cancelable!?LockedStderr {
    _ = userdata;
    _ = terminal_mode;
    @panic("Not implemented yet");
}

fn unlockStderr(userdata: ?*anyopaque) void {
    _ = userdata;
    @panic("Not implemented yet");
}

fn processCurrentPath(userdata: ?*anyopaque, buffer: []u8) std.process.CurrentPathError!usize {
    _ = userdata;
    _ = buffer;
    @panic("Not implemented yet");
}

fn processSetCurrentDir(userdata: ?*anyopaque, dir: Dir) std.process.SetCurrentDirError!void {
    _ = userdata;
    _ = dir;
    @panic("Not implemented yet");
}

fn processSetCurrentPath(userdata: ?*anyopaque, dir_path: []const u8) std.process.SetCurrentPathError!void {
    _ = userdata;
    _ = dir_path;
    @panic("Not implemented yet");
}

fn processReplace(userdata: ?*anyopaque, options: std.process.ReplaceOptions) std.process.ReplaceError {
    _ = userdata;
    _ = options;
    @panic("Not implemented yet");
}

fn processReplacePath(userdata: ?*anyopaque, dir: Dir, options: std.process.ReplaceOptions) std.process.ReplaceError {
    _ = userdata;
    _ = dir;
    _ = options;
    @panic("Not implemented yet");
}

fn processSpawn(userdata: ?*anyopaque, options: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
    _ = userdata;
    _ = options;
    @panic("Not implemented yet");
}

fn processSpawnPath(userdata: ?*anyopaque, dir: Dir, options: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
    _ = userdata;
    _ = dir;
    _ = options;
    @panic("Not implemented yet");
}

fn childWait(userdata: ?*anyopaque, child: *std.process.Child) std.process.Child.WaitError!std.process.Child.Term {
    _ = userdata;
    _ = child;
    @panic("Not implemented yet");
}

fn childKill(userdata: ?*anyopaque, child: *std.process.Child) void {
    _ = userdata;
    _ = child;
    @panic("Not implemented yet");
}

fn progressParentFile(userdata: ?*anyopaque) std.Progress.ParentFileError!File {
    _ = userdata;
    @panic("Not implemented yet");
}

fn now(userdata: ?*anyopaque, clock: Clock) Timestamp {
    const node: *Node = @ptrCast(@alignCast(userdata.?));

    // TODO: Return an appropriate time for each clock
    _ = clock;

    return .{ .nanoseconds = node.scheduler.current_time * 1000 };
}

fn clockResolution(userdata: ?*anyopaque, clock: Clock) Clock.ResolutionError!Duration {
    _ = userdata;
    _ = clock;
    @panic("Not implemented yet");
}

fn sleep(userdata: ?*anyopaque, timeout: Timeout) Cancelable!void {
    const node: *Node = @ptrCast(@alignCast(userdata.?));

    const duration = switch (timeout) {
        .none => return,
        .duration => |d| d.raw,
        .deadline => |d| now(userdata, d.clock).durationTo(d.raw),
    };

    if (duration.nanoseconds <= 0)
        return;

    const delta_us = std.math.cast(u64, @divTrunc(duration.nanoseconds + std.time.ns_per_us - 1, std.time.ns_per_us)) orelse std.math.maxInt(u64);
    if (delta_us == 0)
        return;

    node.sleep(delta_us);
}

fn random(userdata: ?*anyopaque, buffer: []u8) void {
    _ = userdata;
    _ = buffer;
    @panic("Not implemented yet");
}

fn randomSecure(userdata: ?*anyopaque, buffer: []u8) RandomSecureError!void {
    _ = userdata;
    _ = buffer;
    @panic("Not implemented yet");
}

fn nodeFromUserdata(userdata: ?*anyopaque) *Node {
    return @ptrCast(@alignCast(userdata.?));
}

fn ipAddressToNodeAddress(address: *const net.IpAddress) ?Node.Address {
    return switch (address.*) {
        .ip4 => |ip4| .{
            .ipv4 = std.mem.readInt(u32, &ip4.bytes, .big),
            .port = ip4.port,
        },
        .ip6 => null,
    };
}

fn nodeAddressToIpAddress(address: Node.Address) net.IpAddress {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, address.ipv4, .big);
    return .{ .ip4 = .{
        .bytes = bytes,
        .port = address.port,
    } };
}

fn netListenIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.ListenOptions) net.IpAddress.ListenError!net.Socket {
    const node = nodeFromUserdata(userdata);

    if (options.mode != .stream)
        return error.SocketModeUnsupported;
    if (options.protocol != .tcp)
        return error.ProtocolUnsupportedBySystem;

    const node_address = ipAddressToNodeAddress(address) orelse return error.AddressFamilyUnsupported;
    const handle = node.listen(node_address) catch |err| switch (err) {
        error.DescriptorLimit => return error.ProcessFdQuotaExceeded,
        error.AddressNotAvailable => return error.AddressUnavailable,
        error.AddressAlreadyUsed => return error.AddressInUse,
        error.OutOfMemory => return error.SystemResources,
    };

    return .{
        .handle = handle,
        .address = nodeAddressToIpAddress(node_address),
    };
}

fn netAccept(userdata: ?*anyopaque, listen_handle: net.Socket.Handle, options: net.Server.AcceptOptions) net.Server.AcceptError!net.Socket {
    const node = nodeFromUserdata(userdata);
    _ = options;

    const handle = node.accept(listen_handle) catch |err| switch (err) {
        error.DescriptorLimit => return error.ProcessFdQuotaExceeded,
        error.InvalidHandle => return error.SocketNotListening,
        error.AcceptQueueEmpty => return error.WouldBlock,
        error.OutOfMemory => return error.SystemResources,
    };

    return .{
        .handle = handle,
        .address = .{ .ip4 = .unspecified(0) },
    };
}

fn netBindIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.BindOptions) net.IpAddress.BindError!net.Socket {
    _ = userdata;
    _ = address;
    _ = options;
    return error.OptionUnsupported;
}

fn netConnectIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.ConnectOptions) net.IpAddress.ConnectError!net.Socket {
    const node = nodeFromUserdata(userdata);

    if (options.mode != .stream)
        return error.SocketModeUnsupported;
    if (options.protocol) |protocol| {
        if (protocol != .tcp)
            return error.ProtocolUnsupportedBySystem;
    }

    const node_address = ipAddressToNodeAddress(address) orelse return error.AddressFamilyUnsupported;
    const handle = node.connect(node_address) catch |err| switch (err) {
        error.DescriptorLimit => return error.ProcessFdQuotaExceeded,
        error.UnavailableHost => return error.HostUnreachable,
        error.PeerNotListeningOnAddress => return error.ConnectionRefused,
        error.OutOfMemory => return error.SystemResources,
    };

    return .{
        .handle = handle,
        .address = nodeAddressToIpAddress(node_address),
    };
}

fn netListenUnix(userdata: ?*anyopaque, address: *const net.UnixAddress, options: net.UnixAddress.ListenOptions) net.UnixAddress.ListenError!net.Socket.Handle {
    _ = userdata;
    _ = address;
    _ = options;
    @panic("Not implemented yet");
}

fn netConnectUnix(userdata: ?*anyopaque, address: *const net.UnixAddress) net.UnixAddress.ConnectError!net.Socket.Handle {
    _ = userdata;
    _ = address;
    @panic("Not implemented yet");
}

fn netSocketCreatePair(userdata: ?*anyopaque, options: net.Socket.CreatePairOptions) net.Socket.CreatePairError![2]net.Socket {
    _ = userdata;
    _ = options;
    @panic("Not implemented yet");
}

fn netSend(userdata: ?*anyopaque, handle: net.Socket.Handle, messages: []net.OutgoingMessage, flags: net.SendFlags) struct { ?net.Socket.SendError, usize } {
    const node = nodeFromUserdata(userdata);
    _ = flags;

    for (messages, 0..) |*message, index| {
        const source = message.data_ptr[0..message.data_len];
        const written = node.writeSocket(handle, source) catch |err| switch (err) {
            error.InvalidHandle => return .{ error.SocketUnconnected, index },
            error.NotConnected => return .{ error.SocketUnconnected, index },
            error.OutOfMemory => return .{ error.SystemResources, index },
        };
        message.data_len = written;
    }

    return .{ null, messages.len };
}

/// Returns 0 on end of stream.
fn netRead(userdata: ?*anyopaque, fd: net.Socket.Handle, data: [][]u8) net.Stream.Reader.Error!usize {
    const node = nodeFromUserdata(userdata);
    var copied: usize = 0;

    for (data) |buffer| {
        if (buffer.len == 0)
            continue;

        const n = node.readSocket(fd, buffer, true) catch |err| switch (err) {
            error.InvalidHandle => return error.SocketUnconnected,
        };
        copied += n;

        if (n < buffer.len)
            break;
    }

    return copied;
}

fn netWrite(userdata: ?*anyopaque, handle: net.Socket.Handle, header: []const u8, data: []const []const u8, splat: usize) net.Stream.Writer.Error!usize {
    const node = nodeFromUserdata(userdata);
    var copied: usize = 0;

    if (header.len != 0)
        copied += node.writeSocket(handle, header) catch |err| switch (err) {
            error.InvalidHandle => return error.SocketUnconnected,
            error.NotConnected => return error.SocketUnconnected,
            error.OutOfMemory => return error.SystemResources,
        };

    if (data.len != 0) {
        for (data[0 .. data.len - 1]) |bytes| {
            if (bytes.len == 0)
                continue;
            copied += node.writeSocket(handle, bytes) catch |err| switch (err) {
                error.InvalidHandle => return error.SocketUnconnected,
                error.NotConnected => return error.SocketUnconnected,
                error.OutOfMemory => return error.SystemResources,
            };
        }

        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            if (pattern.len == 0)
                break;
            copied += node.writeSocket(handle, pattern) catch |err| switch (err) {
                error.InvalidHandle => return error.SocketUnconnected,
                error.NotConnected => return error.SocketUnconnected,
                error.OutOfMemory => return error.SystemResources,
            };
        }
    }

    return copied;
}

fn netWriteFile(userdata: ?*anyopaque, socket_handle: net.Socket.Handle, header: []const u8, file_reader: *Io.File.Reader, limit: Io.Limit) net.Stream.Writer.WriteFileError!usize {
    _ = userdata;
    _ = socket_handle;
    _ = header;
    _ = file_reader;
    _ = limit;
    @panic("Not implemented yet");
}

fn netClose(userdata: ?*anyopaque, handles: []const net.Socket.Handle) void {
    const node = nodeFromUserdata(userdata);

    for (handles) |handle| {
        node.closeSocket(handle) catch {};
    }
}

fn netShutdown(userdata: ?*anyopaque, handle: net.Socket.Handle, how: net.ShutdownHow) net.ShutdownError!void {
    const node = nodeFromUserdata(userdata);
    _ = how;

    node.closeSocket(handle) catch |err| switch (err) {
        error.InvalidHandle => return error.SocketUnconnected,
    };
}

fn netInterfaceNameResolve(userdata: ?*anyopaque, name: *const net.Interface.Name) net.Interface.Name.ResolveError!net.Interface {
    _ = userdata;
    _ = name;
    @panic("Not implemented yet");
}

fn netInterfaceName(userdata: ?*anyopaque, interface: net.Interface) net.Interface.NameError!net.Interface.Name {
    _ = userdata;
    _ = interface;
    @panic("Not implemented yet");
}

fn netLookup(userdata: ?*anyopaque, host_name: net.HostName, resolved: *Queue(net.HostName.LookupResult), options: net.HostName.LookupOptions) net.HostName.LookupError!void {
    _ = userdata;
    _ = host_name;
    _ = resolved;
    _ = options;
    @panic("Not implemented yet");
}
