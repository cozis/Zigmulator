# Zigmulator

Zigmulator is a Deterministic Simulation Testing framework for Zig.

It allows you to run one or more zig programs in a controlled environment with the ability to inject arbitrary I/O faults. The zigmulation is fully deterministic, which allows you to replay any scenario. It's ideal for testing distributed systems where bugs lay in the interleavings of different nodes.

It's still under construction, but the basic idea is that you write your programs in the form:

```zig
pub fn main(init: std.process.Init) anyerror!void {
    // ...
}
```

Then import them in the simulation program:

```zig
const std = @import("std");
const Io = std.Io;

const Simulator = @import("zigmulator").Simulator;

const programA = @import("projectA/main.zig").main;
const programB = @import("projectB/main.zig").main;
const programC = @import("projectC/main.zig").main;

pub fn main(init: std.process.Init) !void {

    var sim: Simulator = undefined;
    sim.init(std.heap.page_allocator, init.io);
    defer sim.deinit();

    // Associate executable names to zig entry functions
    try sim.addExecutable("program_a", programA);
    try sim.addExecutable("program_b", programB);
    try sim.addExecutable("program_c", programC);

    // Now run commands in the form:
    //     program_name arg1 arg2 arg3 ...
    // where program_name is one of the registered functions.
    try sim.spawn("program_a", .{});
    try sim.spawn("program_b", .{});
    try sim.spawn("program_c", .{});

    // Advance the cluster's state by advancing the program's
    // states one by one. Exits when all programs have returned
    // or failed.
    while (sim.scheduleOne()) {}

    std.debug.print("Simulation ended\n", .{});
}
```

To see this example in action:

```sh
zig build run
```

which will build examples/example.zig

## How it works

Zigmulator implements an in-memory kernel, disk, network and plugs it into your application via the new IO interface (since Zig 0.16). Multiple programs can run in the same simulation, in which case network traffic is routed between their mocks. This is a bruteforce approach but the only one that allows a complete control of the environment the applications are running in.

To avoid non-determinism of kernel-level scheduling, all simulated programs run in a single kernel thread and are scheduled in userspace. Any time a program performs an I/O operation, it yields to a different program.

## Limitations

Since Zigmulator mocks the entire world, the main limitation is in how much of it is mocked and how it differs from the real implementation. This project takes a best-effort approach: the model of the external world is simplified, and applications tested with Zigmulator are expected to only rely on functionality that is mocked. For instance, in the Zigmulator model, each process owns its own machine. If you spawn multiple nodes, each will have its own NIC and disk.

## Current Status

Currently Zigmulator is a proof of concept. A basic version of network, disk, scheduling have been implemented and only the write operations have been mocked.
