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

    const read_file_exe = b.addExecutable(.{
        .name = "read_file",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/read_file.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    read_file_exe.root_module.addImport("zigmulator", zigmulator);
    const install_read_file_exe = b.addInstallArtifact(read_file_exe, .{});
    examples_step.dependOn(&install_read_file_exe.step);

    const directories_exe = b.addExecutable(.{
        .name = "directories",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/directories.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    directories_exe.root_module.addImport("zigmulator", zigmulator);
    const install_directories_exe = b.addInstallArtifact(directories_exe, .{});
    examples_step.dependOn(&install_directories_exe.step);

    const delete_file_exe = b.addExecutable(.{
        .name = "delete_file",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/delete_file.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    delete_file_exe.root_module.addImport("zigmulator", zigmulator);
    const install_delete_file_exe = b.addInstallArtifact(delete_file_exe, .{});
    examples_step.dependOn(&install_delete_file_exe.step);

    const delete_dir_exe = b.addExecutable(.{
        .name = "delete_dir",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/delete_dir.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    delete_dir_exe.root_module.addImport("zigmulator", zigmulator);
    const install_delete_dir_exe = b.addInstallArtifact(delete_dir_exe, .{});
    examples_step.dependOn(&install_delete_dir_exe.step);
}
