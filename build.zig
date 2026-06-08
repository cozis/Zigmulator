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

    const list_dir_exe = b.addExecutable(.{
        .name = "list_dir",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/list_dir.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    list_dir_exe.root_module.addImport("zigmulator", zigmulator);
    const install_list_dir_exe = b.addInstallArtifact(list_dir_exe, .{});
    examples_step.dependOn(&install_list_dir_exe.step);

    const sleep_exe = b.addExecutable(.{
        .name = "sleep",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/sleep.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sleep_exe.root_module.addImport("zigmulator", zigmulator);
    const install_sleep_exe = b.addInstallArtifact(sleep_exe, .{});
    examples_step.dependOn(&install_sleep_exe.step);

    const select_group_async_exe = b.addExecutable(.{
        .name = "select_group_async",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/select_group_async.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    select_group_async_exe.root_module.addImport("zigmulator", zigmulator);
    const install_select_group_async_exe = b.addInstallArtifact(select_group_async_exe, .{});
    examples_step.dependOn(&install_select_group_async_exe.step);

    const tcp_ping_pong_exe = b.addExecutable(.{
        .name = "tcp_ping_pong",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/tcp_ping_pong.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tcp_ping_pong_exe.root_module.addImport("zigmulator", zigmulator);
    const install_tcp_ping_pong_exe = b.addInstallArtifact(tcp_ping_pong_exe, .{});
    examples_step.dependOn(&install_tcp_ping_pong_exe.step);

    const run_tcp_ping_pong_cmd = b.addRunArtifact(tcp_ping_pong_exe);
    const tcp_ping_pong_step = b.step("tcp_ping_pong", "Run the TCP ping-pong example");
    tcp_ping_pong_step.dependOn(&run_tcp_ping_pong_cmd.step);

    const diagram_step = b.step("diagram", "Build the diagram generator");

    const diagram_exe = b.addExecutable(.{
        .name = "diagram",
        .root_module = b.createModule(.{
            .root_source_file = b.path("diagram/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_diagram_exe = b.addInstallArtifact(diagram_exe, .{});
    diagram_step.dependOn(&install_diagram_exe.step);

    const run_timeline_html_cmd = b.addRunArtifact(diagram_exe);
    run_timeline_html_cmd.addArg("timeline_html");
    if (b.args) |args| {
        run_timeline_html_cmd.addArgs(args);
    }
    const run_timeline_html_step = b.step("timeline_html", "Generate a timeline diagram as HTML");
    run_timeline_html_step.dependOn(&run_timeline_html_cmd.step);

    const run_timeline_ascii_cmd = b.addRunArtifact(diagram_exe);
    run_timeline_ascii_cmd.addArg("timeline_ascii");
    if (b.args) |args| {
        run_timeline_ascii_cmd.addArgs(args);
    }
    const run_timeline_ascii_step = b.step("timeline_ascii", "Generate a timeline diagram as ASCII");
    run_timeline_ascii_step.dependOn(&run_timeline_ascii_cmd.step);

    const run_strace_cmd = b.addRunArtifact(diagram_exe);
    run_strace_cmd.addArg("strace");
    if (b.args) |args| {
        run_strace_cmd.addArgs(args);
    }
    const run_strace_step = b.step("strace", "Generate a trace of all I/O calls");
    run_strace_step.dependOn(&run_strace_cmd.step);
}
