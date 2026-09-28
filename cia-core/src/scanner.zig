const std = @import("std");
const LineCounter = @import("countlines.zig").LineCounter;
const LinesModel = @import("lines_model.zig").LinesModel;

const ignored_directories = [_][]const u8{
    ".git",
    ".jj",
    ".zig-cache",
    "zig-out",
    ".venv",
    "node_modules",
};

const PendingDirectory = struct {
    path: []u8,
};

const OwnedEntry = struct {
    name: []u8,
    kind: std.Io.File.Kind,
};

/// Scans `root`, which must have been opened with `.iterate = true`.
/// The returned model owns its paths and must be deinitialized by the caller;
/// `root` remains owned by the caller.
pub fn scan(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !LinesModel {
    return scanCancelable(allocator, io, root, null);
}

pub fn scanCancelable(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    cancelled: ?*const std.atomic.Value(bool),
) !LinesModel {
    var model = LinesModel.init(allocator);
    errdefer model.deinit();

    var counter = try LineCounter.init(allocator, 64 * 1024);
    defer counter.deinit();

    var directories: std.ArrayList(PendingDirectory) = .empty;
    defer {
        for (directories.items) |directory| allocator.free(directory.path);
        directories.deinit(allocator);
    }
    const root_path = try allocator.dupe(u8, "");
    directories.append(allocator, .{
        .path = root_path,
    }) catch |err| {
        allocator.free(root_path);
        return err;
    };

    var next_directory: usize = 0;
    while (next_directory < directories.items.len) : (next_directory += 1) {
        try checkCancelled(cancelled);
        const directory = directories.items[next_directory];
        scanDirectory(allocator, io, root, directory.path, &directories, &counter, &model, cancelled) catch |err| {
            if (err == error.OutOfMemory or err == error.Cancelled) return err;
            model.warning_count += 1;
        };
    }

    return model;
}

fn scanDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    directory_path: []const u8,
    directories: *std.ArrayList(PendingDirectory),
    counter: *LineCounter,
    model: *LinesModel,
    cancelled: ?*const std.atomic.Value(bool),
) !void {
    const opened = directory_path.len != 0;
    const directory = if (opened)
        try root.openDir(io, directory_path, .{ .iterate = true, .follow_symlinks = false })
    else
        root;
    defer if (opened) directory.close(io);

    var entries: std.ArrayList(OwnedEntry) = .empty;
    defer {
        for (entries.items) |entry| allocator.free(entry.name);
        entries.deinit(allocator);
    }

    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        try checkCancelled(cancelled);
        const kind = if (entry.kind == .unknown)
            (directory.statFile(io, entry.name, .{ .follow_symlinks = false }) catch {
                model.warning_count += 1;
                continue;
            }).kind
        else
            entry.kind;
        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);
        try entries.append(allocator, .{
            .name = name,
            .kind = kind,
        });
    }
    std.mem.sort(OwnedEntry, entries.items, {}, entryLessThan);

    for (entries.items) |entry| switch (entry.kind) {
        .directory => {
            if (isIgnoredDirectory(entry.name)) continue;

            const child_path = try joinRelative(allocator, directory_path, entry.name);
            errdefer allocator.free(child_path);
            try directories.append(allocator, .{
                .path = child_path,
            });
        },
        .file => {
            if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

            const lines = countFile(io, directory, entry.name, counter, cancelled) catch |err| {
                if (err == error.Cancelled) return err;
                model.warning_count += 1;
                continue;
            };
            const path = try joinRelative(allocator, directory_path, entry.name);
            model.appendOwned(path, lines) catch |err| {
                allocator.free(path);
                return err;
            };
        },
        else => {},
    };
}

fn countFile(
    io: std.Io,
    directory: std.Io.Dir,
    name: []const u8,
    counter: *LineCounter,
    cancelled: ?*const std.atomic.Value(bool),
) !usize {
    const file = try directory.openFile(io, name, .{
        .allow_directory = false,
        .follow_symlinks = false,
    });
    defer file.close(io);
    return counter.countFileCancelable(io, file, cancelled);
}

fn checkCancelled(cancelled: ?*const std.atomic.Value(bool)) !void {
    if (cancelled) |flag| {
        if (flag.load(.acquire)) return error.Cancelled;
    }
}

fn entryLessThan(_: void, lhs: OwnedEntry, rhs: OwnedEntry) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn isIgnoredDirectory(name: []const u8) bool {
    for (ignored_directories) |ignored| {
        if (std.mem.eql(u8, name, ignored)) return true;
    }
    return false;
}

fn joinRelative(allocator: std.mem.Allocator, parent: []const u8, name: []const u8) ![]u8 {
    if (parent.len == 0) return allocator.dupe(u8, name);
    return std.fs.path.join(allocator, &.{ parent, name });
}

test "scan uses BFS lexical order and filters entries and ignored directories" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "alpha/deep");
    try tmp.dir.createDirPath(io, "zeta");
    inline for (ignored_directories) |ignored| {
        try tmp.dir.createDirPath(io, ignored);
        const ignored_file = try std.fs.path.join(std.testing.allocator, &.{ ignored, "ignored.zig" });
        defer std.testing.allocator.free(ignored_file);
        try tmp.dir.writeFile(io, .{ .sub_path = ignored_file, .data = "ignored\n" });
    }

    try tmp.dir.writeFile(io, .{ .sub_path = "b.zig", .data = "one\ntwo" });
    try tmp.dir.writeFile(io, .{ .sub_path = "a.zig", .data = "one\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "not-zig.txt", .data = "no\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "alpha/a.zig", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "alpha/deep/d.zig", .data = "one\ntwo\nthree\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "zeta/z.zig", .data = "one" });
    try tmp.dir.symLink(io, "a.zig", "linked.zig", .{});
    try tmp.dir.symLink(io, "alpha", "linked-dir", .{ .is_directory = true });

    var model = try scan(std.testing.allocator, io, tmp.dir);
    defer model.deinit();

    const expected_paths = [_][]const u8{
        "a.zig",
        "b.zig",
        "alpha/a.zig",
        "zeta/z.zig",
        "alpha/deep/d.zig",
    };
    const expected_lines = [_]usize{ 1, 2, 0, 1, 3 };
    try std.testing.expectEqual(expected_paths.len, model.files.items.len);
    for (model.files.items, expected_paths, expected_lines) |file, expected_path, expected_line_count| {
        try std.testing.expectEqualStrings(expected_path, file.path);
        try std.testing.expectEqual(expected_line_count, file.lines);
    }
    try std.testing.expectEqual(7, model.total_lines);
    try std.testing.expectEqual(0, model.warning_count);
}

test "scan observes cancellation before traversal" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    var cancelled = std.atomic.Value(bool).init(true);
    try std.testing.expectError(
        error.Cancelled,
        scanCancelable(std.testing.allocator, io, tmp.dir, &cancelled),
    );
}
