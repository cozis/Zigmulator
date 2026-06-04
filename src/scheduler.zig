const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("node.zig");

const Scheduler = @This();

pub const MainEntryPoint = *const fn(std.process.Init) anyerror!void;
pub const NestedEntryPoint = *const fn(context: *const anyopaque) void;

pub const EntryPoint = union(enum) {
    main: MainEntryPoint,
    nested: NestedEntryPoint,
};

const Registers = struct {
    rsp: usize,
    rbp: usize,
    rip: usize,
    rdi: usize,
};

const ContextSwitch = extern struct {
    old: *Registers,
    new: *Registers,
};

const STACK_CANARY_SIZE = 256;
const STACK_CANARY_BYTE = 0xa5;

pub const TaskID = u64;

const State = enum {
    ready,
    running,
    blocked,
    failed,
    returned,
};

const Task = struct {
    id    : TaskID,
    regs  : Registers,
    stack : []align(16) u8,
    entry : EntryPoint,
    context: ?*const anyopaque,
    state : State,
    node  : *Node,

    // If this is a subtask, parent_id refers to the parent.
    // The cancel flag is set when the parent requests cancellation.
    parent_id: ?TaskID,
    cancel: bool,

    // These fields are only used when state=.blocked and
    // are not mutually exclusive. Each represents a different
    // wakeup condition.
    wakeup_time: ?u64,
    wakeup_tasks: ?[]const TaskID,
    wakeup_futex: ?*const u32,

    fn stackCanaryIsIntact(self: *Task) bool {
        const canary = self.stack[0..STACK_CANARY_SIZE];
        for (canary) |byte| {
            if (byte != STACK_CANARY_BYTE)
                return false;
        }
        return true;
    }
};

gpa: Allocator,
tasks: std.ArrayList(Task),
regs: Registers,
current_id: ?TaskID,
current_time: u64,
next_task_id: u64,

pub fn init(self: *Scheduler, gpa: Allocator) void {
    self.gpa = gpa;
    self.tasks = .empty;
    self.current_id = null;
    self.current_time = 0;
    self.next_task_id = 0;
}

pub fn deinit(self: *Scheduler) void {
    for (self.tasks.items) |task| {
        std.heap.page_allocator.free(task.stack);
    }
    self.tasks.deinit(self.gpa);
}

pub fn spawn(self: *Scheduler, node: *Node, entry: MainEntryPoint, stack_size: usize) !void {
    _ = try self.spawnInner(node, .{ .main = entry }, stack_size, null, null);
}

pub fn spawnNested(self: *Scheduler, node: *Node, entry: NestedEntryPoint, context: *const anyopaque) !TaskID {
    const parent_id = self.current_id.?;
    return (try self.spawnInner(node, .{ .nested = entry }, 64 * 1024, parent_id, context)).id;
}

fn spawnInner(
    self: *Scheduler,
    node: *Node,
    entry: EntryPoint,
    stack_size: usize,
    parent_id: ?TaskID,
    context: ?*const anyopaque,
) !*Task {

    if (stack_size > std.math.maxInt(usize) - STACK_CANARY_SIZE)
        return Allocator.Error.OutOfMemory;

    const stack = try std.heap.page_allocator.alignedAlloc(u8, .fromByteUnits(16), stack_size + STACK_CANARY_SIZE);
    errdefer std.heap.page_allocator.free(stack);
    @memset(stack[0..STACK_CANARY_SIZE], STACK_CANARY_BYTE);

    var stack_top = @intFromPtr(stack.ptr) + stack.len;
    stack_top &= ~@as(usize, 0xf);
    stack_top -= @sizeOf(usize);

    // If the entry point returns, `ret` jumps here instead of into nowhere.
    @as(*usize, @ptrFromInt(stack_top)).* = @intFromPtr(&taskReturned);

    const id = self.next_task_id;
    defer self.next_task_id += 1;

    const task = Task {
        .id = id,
        .regs = .{
            .rsp = stack_top,
            .rbp = 0,
            .rip = @intFromPtr(&taskStart),
            .rdi = @intFromPtr(self),
        },
        .stack  = stack,
        .entry  = entry,
        .context = context,
        .state  = .ready,
        .wakeup_time = null,
        .wakeup_tasks = null,
        .wakeup_futex = null,
        .node   = node,
        .parent_id = parent_id,
        .cancel = false,
    };

    try self.tasks.append(self.gpa, task);
    return &self.tasks.items[self.tasks.items.len - 1];
}

// Removes from the scheduler a nested task. This should only be used
// on a task that has never ran yet or the cleanup won't be clean.
// The intended use-case is undoing a previous call .spawnNested to
// in case of errors.
pub fn despawnNested(self: *Scheduler, id: TaskID) void {
    const index = self.findTaskIndexByID(id) orelse return;
    const task = &self.tasks.items[index];

    std.heap.page_allocator.free(task.stack);
    _ = self.tasks.orderedRemove(index);
}

fn findTaskWithState(self: *Scheduler, state: State) ?*Task {
    for (self.tasks.items) |*task| {
        if (task.state == state)
            return task;
    }
    return null;
}

fn findTaskIndexByID(self: *Scheduler, id: TaskID) ?usize {
    for (self.tasks.items, 0..) |*task, i| {
        if (task.id == id)
            return i;
    }
    return null;
}

fn findTaskByID(self: *Scheduler, id: TaskID) ?*Task {
    const index = self.findTaskIndexByID(id) orelse return null;
    return &self.tasks.items[index];
}

fn findBlockedTaskWithLowestWakeupTime(self: *Scheduler) ?*Task {
    var task: ?*Task = null;
    for (self.tasks.items) |*t| {
        if (t.state != .blocked or t.wakeup_time == null)
            continue;
        if (task == null or t.wakeup_time.? < task.?.wakeup_time.?)
            task = t;
    }
    return task;
}

fn advanceTimeAndUnblockTasks(self: *Scheduler, new_time: u64) void {
    std.debug.assert(self.current_time < new_time);
    self.current_time = new_time;
    for (self.tasks.items) |*task| {
        if (task.state == .blocked) {
            if (task.wakeup_time) |wakeup_time| {
                if (wakeup_time <= new_time) {
                    task.state = .ready;
                    task.wakeup_time = null;
                    task.wakeup_tasks = null;
                    task.wakeup_futex = null;
                }
            }
        }
    }
}

fn taskIsWaitingFor(task: *const Task, id: TaskID) bool {
    if (task.state != .blocked)
        return false;
    if (task.wakeup_tasks) |wakeup_tasks| {
        for (wakeup_tasks) |wakeup_id| {
            if (wakeup_id == id)
                return true;
        }
    }
    return false;
}

fn advanceTimeAndPickTask(self: *Scheduler) ?*Task {
    const task = self.findBlockedTaskWithLowestWakeupTime() orelse return null;
    self.advanceTimeAndUnblockTasks(task.wakeup_time.?);
    return task;
}

pub fn scheduleOne(self: *Scheduler) bool {
    const task = self.findTaskWithState(.ready)
        orelse self.advanceTimeAndPickTask()
        orelse return false;
    const id = task.id;
    self.current_id = id;
    task.state = .running;
    contextSwitch(&self.regs, &task.regs);
    const current = self.findTaskByID(id) orelse return true;
    if (!current.stackCanaryIsIntact())
        @panic("Task stack canary was overwritten");
    return true;
}

fn contextSwitch(old: *Registers, new: *Registers) void {
    asm volatile (
        \\ movq 0(%%rsi), %%rax
        \\ movq 8(%%rsi), %%rcx
        \\ leaq 0f(%%rip), %%rdx
        \\ movq %%rsp, 0(%%rax)
        \\ movq %%rbp, 8(%%rax)
        \\ movq %%rdx, 16(%%rax)
        \\ movq 0(%%rcx), %%rsp
        \\ movq 8(%%rcx), %%rbp
        \\ movq 24(%%rcx), %%rdi
        \\ jmpq *16(%%rcx)
        \\0:
        :
        : [message] "{rsi}" (&ContextSwitch{ .old = old, .new = new }),
        : .{
            .rax = true,
            .rcx = true,
            .rdx = true,
            .rbx = true,
            .rsi = true,
            .rdi = true,
            .r8 = true,
            .r9 = true,
            .r10 = true,
            .r11 = true,
            .r12 = true,
            .r13 = true,
            .r14 = true,
            .r15 = true,
            .memory = true,
        });
}

fn taskStart(self: *Scheduler) callconv(.c) noreturn {
    const id = self.current_id.?;
    const task = self.findTaskByID(id).?;

    var failed = false;
    switch (task.entry) {
        .main => |entry| {
            const node = task.node;
            entry(node.processInit()) catch {
                failed = true;
            };
        },
        .nested => |entry| entry(task.context.?),
    }

    const current = self.findTaskByID(id).?;
    current.state = if (failed) .failed else .returned;
    current.wakeup_time = null;
    current.wakeup_tasks = null;
    current.wakeup_futex = null;
    if (current.parent_id) |parent_id| {
        if (self.findTaskByID(parent_id)) |parent| {
            if (taskIsWaitingFor(parent, current.id)) {
                parent.state = .ready;
                parent.wakeup_time = null;
                parent.wakeup_tasks = null;
                parent.wakeup_futex = null;
            }
        }
    }
    contextSwitch(&current.regs, &self.regs);
    unreachable;
}

// Dummy return address on the task's stack. Should never be reached.
fn taskReturned() callconv(.c) noreturn {
    @panic("Task returned through the fake return address");
}

// Called by the current task to return control to the scheduler
pub fn sleep(self: *Scheduler, delta_us: u64) void {
    const current = self.findTaskByID(self.current_id.?).?;
    current.state = .blocked;
    current.wakeup_time = self.current_time + delta_us;
    current.wakeup_tasks = null;
    current.wakeup_futex = null;
    contextSwitch(&current.regs, &self.regs);
}

pub fn futexWait(self: *Scheduler, ptr: *const u32, expected: u32) void {
    if (@atomicLoad(u32, ptr, .seq_cst) != expected)
        return;

    const current = self.findTaskByID(self.current_id.?).?;
    current.state = .blocked;
    current.wakeup_time = null;
    current.wakeup_tasks = null;
    current.wakeup_futex = ptr;
    contextSwitch(&current.regs, &self.regs);
}

pub fn futexWake(self: *Scheduler, ptr: *const u32, max_waiters: u32) void {
    var woken: u32 = 0;
    for (self.tasks.items) |*task| {
        if (woken == max_waiters)
            break;
        if (task.state == .blocked and task.wakeup_futex == ptr) {
            task.state = .ready;
            task.wakeup_time = null;
            task.wakeup_tasks = null;
            task.wakeup_futex = null;
            woken += 1;
        }
    }
}

fn findCompletedTaskInSet(self: *Scheduler, ids: []const TaskID) !?*Task {
    for (ids) |id| {
        const child = self.findTaskByID(id) orelse return error.InvalidHandle;
        switch (child.state) {
            .returned, .failed => return child,
            else => {},
        }
    }
    return null;
}

pub fn wait(self: *Scheduler, ids: []const TaskID) !TaskID {
    const id = self.current_id.?;

    while (true) {
        const child = try self.findCompletedTaskInSet(ids);
        if (child) |c| {
            std.debug.assert(c.parent_id == id);
            return c.id;
        }

        const task = self.findTaskByID(self.current_id.?).?;
        task.state = .blocked;
        task.wakeup_time = null;
        task.wakeup_tasks = ids;
        task.wakeup_futex = null;
        contextSwitch(&task.regs, &self.regs);
    }
}

pub fn cancel(self: *Scheduler, id: TaskID) !void {
    const child = self.findTaskByID(id)
        orelse return error.InvalidHandle;

    if (child.parent_id != self.current_id)
        return error.InvalidHandle;

    child.cancel = true;
}
