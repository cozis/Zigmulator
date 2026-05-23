const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigmulator = b.addModule("zigmulator", .{
        .root_source_file = b.path("src/simulator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const examples_step = b.step("examples", "Build all examples");

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/example.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("zigmulator", zigmulator);
    const install_exe = b.addInstallArtifact(exe, .{});
    examples_step.dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    const open_file_exe = b.addExecutable(.{
        .name = "open_file",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/open_file.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    open_file_exe.root_module.addImport("zigmulator", zigmulator);
    const install_open_file_exe = b.addInstallArtifact(open_file_exe, .{});
    examples_step.dependOn(&install_open_file_exe.step);
}
