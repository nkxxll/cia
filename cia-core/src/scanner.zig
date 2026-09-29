const std = @import("std");
const ArrayList = std.ArrayList;

/// Find all source files that are tracked by git and have the source file
/// ending for Zig this is ".zig". If the Scanning should be cancelled because
/// of a UI-event this can be done with `cancelled`.
pub fn scan(
    allocator: std.mem.Allocator,
    io: std.Io,
) !void {
    // WARN: the list has to either take ownership of the entries, take its own
    // owned entry type, or not outlive the waker
    var source_files: ArrayList(std.Io.Dir.Walker.Entry) = .initCapacity(64);
    defer {
        for (source_files.items) |entry| allocator.free(entry.path);
        source_files.deinit(allocator);
    }

    const r = try std.Io.Dir.cwd().openDir(io, "", .{ .iterate = true });

    walk(r);
}

fn walk(dir: std.Io.Dir, source_files: ArrayList(std.Io.Dir.Walker.Entry)) !void {
    var walker = try dir.walk();
    while (try walker.next()) |entry| {
        if (isSourceFile(entry)) {
            // TODO: append to source_files
        }

        if (entry.kind == .directory) {
            try walk(entry.dir);
        }
    }
}

/// Uses libgit2 to find out whether the file is ignored and tests the
/// extension for the zig file extension
fn isSourceFile(entry: std.Io.Dir.Walker.Entry) bool {
    return true;
}
