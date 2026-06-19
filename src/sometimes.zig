const std = @import("std");
const Allocator = std.mem.Allocator;
const SourceLocation = std.builtin.SourceLocation;

// Registry of "sometimes" assertions.
//
// A sometimes-assertion records that a given condition was observed to be true
// at least once during a simulation. Unlike a regular assertion (which must
// always hold), a sometimes-assertion documents a branch we *expect* to be
// exercised eventually. In a single run it may legitimately never fire; its
// signal is only meaningful as coverage across many seeds.
//
// Each call site is identified by its source location (@src()), so the same
// physical assertSometimes() call is one entry regardless of how many times
// it is evaluated. An optional human-readable label is shown in the report.
//
// The registry only knows about assertions that were *evaluated* at least once.
// A call site that is reached with the condition true at least once is reported
// as taken; one that is reached but whose condition is always false is reported
// as not-taken. A call site that is never reached at all cannot appear.

pub const Sometimes = struct {
    const Entry = struct {
        file: []const u8,
        fn_name: []const u8,
        line: u32,
        column: u32,
        label: ?[]const u8,
        eval_count: u64,
        true_count: u64,

        fn matches(self: Entry, src: SourceLocation) bool {
            return self.line == src.line and
                self.column == src.column and
                std.mem.eql(u8, self.file, src.file);
        }
    };

    gpa: Allocator,
    entries: std.ArrayList(Entry),
    reported: bool,

    pub fn init(self: *Sometimes, gpa: Allocator) void {
        self.gpa = gpa;
        self.entries = .empty;
        self.reported = false;
    }

    pub fn deinit(self: *Sometimes) void {
        self.entries.deinit(self.gpa);
    }

    // Records one evaluation of a sometimes-assertion. The strings carried by
    // @src() (and any string-literal label) live for the whole program, so we
    // can store the slices directly without duplicating them.
    pub fn record(self: *Sometimes, cond: bool, src: SourceLocation, label: ?[]const u8) void {
        for (self.entries.items) |*entry| {
            if (entry.matches(src)) {
                entry.eval_count += 1;
                if (cond) entry.true_count += 1;
                if (label != null and entry.label == null) entry.label = label;
                return;
            }
        }

        // First time this call site is seen. If we can't grow the registry we
        // simply drop the entry: a sometimes-assertion must never affect the
        // behaviour of the program under test.
        self.entries.append(self.gpa, .{
            .file = src.file,
            .fn_name = src.fn_name,
            .line = src.line,
            .column = src.column,
            .label = label,
            .eval_count = 1,
            .true_count = if (cond) 1 else 0,
        }) catch return;
    }

    pub fn report(self: *Sometimes) void {
        self.reported = true;

        if (self.entries.items.len == 0)
            return;

        var taken: usize = 0;
        for (self.entries.items) |entry| {
            if (entry.true_count > 0) taken += 1;
        }

        std.debug.print("\n=== Sometimes assertions: {d}/{d} taken ===\n", .{ taken, self.entries.items.len });
        for (self.entries.items) |entry| {
            const mark = if (entry.true_count > 0) "\u{2713}" else "\u{2717}";
            std.debug.print("  [{s}] {s}:{d}:{d} ({s})", .{
                mark, entry.file, entry.line, entry.column, entry.fn_name,
            });
            if (entry.label) |label|
                std.debug.print(" \"{s}\"", .{label});
            std.debug.print(" \u{2014} {d}/{d} true\n", .{ entry.true_count, entry.eval_count });
        }
        std.debug.print("\n", .{});
    }
};
