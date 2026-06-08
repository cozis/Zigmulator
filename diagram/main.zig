const std = @import("std");

const strace = @import("strace.zig");
const timeline_html  = @import("timeline_html.zig");
const timeline_ascii = @import("timeline_ascii.zig");

pub fn main(init: std.process.Init) !void {

    var args = init.minimal.args.iterate();
    _ = args.next(); // Skip first

    const diagram_name = args.next() orelse {
        std.debug.print("Missing diagram name\n", .{});
        return;
    };

    const input_file = args.next() orelse "simulation.log";

    if (std.mem.eql(u8, diagram_name, "strace")) {

        const output_file = args.next() orelse "strace.txt";
        strace.renderFile(init.io, init.gpa, input_file, output_file) catch |e| {
            if (e != error.FileNotFound)
                return e;
            std.debug.print("File {s} not found\n", .{input_file});
            return;
        };

    } else if (std.mem.eql(u8, diagram_name, "timeline_html")) {

        const output_file = args.next() orelse "timeline.html";
        timeline_html.renderFile(init.io, init.gpa, input_file, output_file) catch |e| {
            if (e != error.FileNotFound)
                return e;
            std.debug.print("File {s} not found\n", .{input_file});
            return;
        };

    } else if (std.mem.eql(u8, diagram_name, "timeline_ascii")) {

        const output_file = args.next() orelse "timeline.txt";
        timeline_ascii.renderFile(init.io, init.gpa, input_file, output_file, 1) catch |e| {
            if (e != error.FileNotFound)
                return e;
            std.debug.print("File {s} not found\n", .{input_file});
            return;
        };

    } else {

        std.debug.print("Invalid diagram name\n", .{});
    }
}
