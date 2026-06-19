const std = @import("std");
const Allocator = std.mem.Allocator;
const SourceLocation = std.builtin.SourceLocation;

const sometimes_section = "zigmulator_sometimes";
const site_magic: u64 = 0x5a_69_67_53_6f_6d_65_74;

pub const SiteKind = enum {
    assert,
    reachable,
};

pub const Site = struct {
    file: []const u8,
    fn_name: []const u8,
    line: u32,
    column: u32,
    label: ?[]const u8,
    kind: u8,
    magic: u64,

    pub fn init(comptime src: SourceLocation, comptime label: ?[]const u8, comptime kind: SiteKind) Site {
        return .{
            .file = src.file,
            .fn_name = src.fn_name,
            .line = src.line,
            .column = src.column,
            .label = label,
            .kind = @intFromEnum(kind),
            .magic = site_magic,
        };
    }

    pub fn isValid(self: Site) bool {
        return self.magic == site_magic and self.line != 0;
    }

    pub fn kindName(self: Site) []const u8 {
        return switch (self.kind) {
            @intFromEnum(SiteKind.assert) => "assert",
            @intFromEnum(SiteKind.reachable) => "reachable",
            else => "unknown",
        };
    }

    fn matches(self: Site, src: SourceLocation) bool {
        return self.line == src.line and
            self.column == src.column and
            std.mem.eql(u8, self.file, src.file);
    }

    fn matchesSite(self: Site, other: Site) bool {
        return self.line == other.line and
            self.column == other.column and
            std.mem.eql(u8, self.file, other.file);
    }
};

const sentinel_site = Site{
    .file = "",
    .fn_name = "",
    .line = 0,
    .column = 0,
    .label = null,
    .kind = @intFromEnum(SiteKind.assert),
    .magic = site_magic,
};
const sentinel_site_entry linksection(sometimes_section) = sentinel_site;

extern const __start_zigmulator_sometimes: Site;
extern const __stop_zigmulator_sometimes: Site;

pub fn registerSite(comptime src: SourceLocation, comptime label: ?[]const u8, comptime kind: SiteKind) *const Site {
    const SiteDecl = struct {
        const site linksection(sometimes_section) = Site.init(src, label, kind);
    };
    return &SiteDecl.site;
}

pub fn compileTimeSites() []const Site {
    _ = &sentinel_site_entry;
    const start: [*]const Site = @ptrCast(&__start_zigmulator_sometimes);
    const stop_addr = @intFromPtr(&__stop_zigmulator_sometimes);
    const start_addr = @intFromPtr(start);
    const count = (stop_addr - start_addr) / @sizeOf(Site);
    return start[0..count];
}

pub fn reportCompileTimeSites() void {
    var count: usize = 0;
    for (compileTimeSites()) |site| {
        if (site.isValid()) count += 1;
    }

    if (count == 0) return;

    std.debug.print("\n=== Sometimes assertion sites: {d} compiled ===\n", .{count});
    for (compileTimeSites()) |site| {
        if (!site.isValid()) continue;

        std.debug.print("  [{s}] {s}:{d}:{d} ({s})", .{
            site.kindName(), site.file, site.line, site.column, site.fn_name,
        });
        if (site.label) |label|
            std.debug.print(" \"{s}\"", .{label});
        std.debug.print("\n", .{});
    }
    std.debug.print("\n", .{});
}

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
// The registry is seeded with compile-time call-site descriptors, so the final
// report can include branches that were compiled but never evaluated.

pub const Sometimes = struct {
    const Entry = struct {
        file: []const u8,
        fn_name: []const u8,
        line: u32,
        column: u32,
        label: ?[]const u8,
        kind_name: []const u8,
        eval_count: u64,
        true_count: u64,

        fn matchesSite(self: Entry, site: Site) bool {
            return self.line == site.line and
                self.column == site.column and
                std.mem.eql(u8, self.file, site.file);
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

    pub fn seedCompileTimeSites(self: *Sometimes) void {
        for (compileTimeSites()) |site| {
            if (!site.isValid()) continue;
            self.ensureSite(site);
        }
    }

    pub fn deinit(self: *Sometimes) void {
        self.entries.deinit(self.gpa);
    }

    // Records one evaluation of a sometimes-assertion. The strings carried by
    // @src() (and any string-literal label) live for the whole program, so we
    // can store the slices directly without duplicating them.
    pub fn record(self: *Sometimes, cond: bool, site: Site) void {
        for (self.entries.items) |*entry| {
            if (entry.matchesSite(site)) {
                entry.eval_count += 1;
                if (cond) entry.true_count += 1;
                if (site.label != null and entry.label == null) entry.label = site.label;
                return;
            }
        }

        // First time this call site is seen. If we can't grow the registry we
        // simply drop the entry: a sometimes-assertion must never affect the
        // behaviour of the program under test.
        self.appendSite(site, 1, if (cond) 1 else 0);
    }

    fn ensureSite(self: *Sometimes, site: Site) void {
        for (self.entries.items) |entry| {
            if (site.matchesSite(.{
                .file = entry.file,
                .fn_name = entry.fn_name,
                .line = entry.line,
                .column = entry.column,
                .label = entry.label,
                .kind = 0,
                .magic = site_magic,
            })) return;
        }
        self.appendSite(site, 0, 0);
    }

    fn appendSite(self: *Sometimes, site: Site, eval_count: u64, true_count: u64) void {
        self.entries.append(self.gpa, .{
            .file = site.file,
            .fn_name = site.fn_name,
            .line = site.line,
            .column = site.column,
            .label = site.label,
            .kind_name = site.kindName(),
            .eval_count = eval_count,
            .true_count = true_count,
        }) catch return;
    }

    pub fn allReached(self: Sometimes) bool {
        for (self.entries.items) |entry| {
            if (entry.true_count == 0) return false;
        }
        return true;
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
            std.debug.print("  [{d}/{d}] {s}:{d}:{d} ({s})", .{
                entry.true_count,
                entry.eval_count,
                entry.file,
                entry.line,
                entry.column,
                entry.fn_name,
            });
            if (entry.label) |label|
                std.debug.print(" \"{s}\"", .{label});
            std.debug.print("\n", .{});
        }
        std.debug.print("\n", .{});
    }
};
