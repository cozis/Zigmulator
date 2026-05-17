const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("node.zig");

const Scheduler = @This();
pub const EntryPoint = *const fn(std.process.Init) anyerror!void;

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

const State = enum {
    ready,
    running,
    blocked,
    failed,
    returned,
};

const Task = struct {
    regs  : Registers,
    stack : []align(16) u8,
    entry : EntryPoint,
    state : State,
    wakeup: ?u64,
    node  : *Node,
};

gpa: Allocator,
tasks: std.ArrayList(Task),
regs: Registers,
current: ?*Task,
current_time: u64,

pub fn init(self: *Scheduler, gpa: Allocator) void {
    self.gpa = gpa;
    self.tasks = .empty;
    self.current = null;
    self.current_time = 0;
}

pub fn deinit(self: *Scheduler) void {
    for (self.tasks.items) |task| {
        std.heap.page_allocator.free(task.stack);
    }
    self.tasks.deinit(self.gpa);
}

pub fn spawn(self: *Scheduler, node: *Node, entry: EntryPoint, stack_size: usize) !void {

    const stack = try std.heap.page_allocator.alignedAlloc(u8, .fromByteUnits(16), stack_size);
    errdefer std.heap.page_allocator.free(stack);

    var stack_top = @intFromPtr(stack.ptr) + stack.len;
    stack_top &= ~@as(usize, 0xf);
    stack_top -= @sizeOf(usize);

    // If the entry point returns, `ret` jumps here instead of into nowhere.
    @as(*usize, @ptrFromInt(stack_top)).* = @intFromPtr(&taskReturned);

    const task = Task {
        .regs = .{
            .rsp = stack_top,
            .rbp = 0,
            .rip = @intFromPtr(&taskStart),
            .rdi = @intFromPtr(self),
        },
        .stack  = stack,
        .entry  = entry,
        .state  = .ready,
        .wakeup = null,
        .node   = node,
    };

    try self.tasks.append(self.gpa, task);
}

fn findTaskWithState(self: *Scheduler, state: State) ?*Task {
    for (self.tasks.items) |*task| {
        if (task.state == state)
            return task;
    }
    return null;
}

fn findBlockedTaskWithLowestWakeupTime(self: *Scheduler) ?*Task {
    var task = self.findTaskWithState(.blocked) orelse return null;
    for (self.tasks.items) |*t| {
        // If the state is blocked, wakeup MUST be set
        std.debug.assert(t.state != .blocked or t.wakeup != null);
        if (t.state == .blocked and t.wakeup.? < task.wakeup.?) {
            task = t;
        }
    }
    return task;
}

fn advanceTimeAndUnblockTasks(self: *Scheduler, new_time: u64) void {
    std.debug.assert(self.current_time < new_time);
    self.current_time = new_time;
    for (self.tasks.items) |*task| {
        if (task.state == .blocked and task.wakeup.? <= new_time) {
            task.state = .ready;
            task.wakeup = null;
        }
    }
}

fn advanceTimeAndPickTask(self: *Scheduler) ?*Task {
    const task = self.findBlockedTaskWithLowestWakeupTime() orelse return null;
    self.advanceTimeAndUnblockTasks(task.wakeup.?);
    return task;
}

pub fn scheduleOne(self: *Scheduler) bool {
    const task = self.findTaskWithState(.ready)
        orelse self.advanceTimeAndPickTask()
        orelse return false;
    self.current = task;
    task.state = .running;
    contextSwitch(&self.regs, &task.regs);
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
    const task = self.current.?;

    task.entry(task.node.processInit()) catch {
        task.state = .failed;
        contextSwitch(&task.regs, &self.regs);
        unreachable;
    };

    task.state = .returned;
    contextSwitch(&task.regs, &self.regs);
    unreachable;
}

// Dummy return address on the task's stack. Should never be reached.
fn taskReturned() callconv(.c) noreturn {
    @panic("Task returned through the fake return address");
}

// Called by the current task to return control to the scheduler
pub fn sleep(self: *Scheduler, delta_us: u64) void {
    const task = self.current.?;
    task.state = .blocked;
    task.wakeup = self.current_time + delta_us;
    contextSwitch(&task.regs, &self.regs);
}
