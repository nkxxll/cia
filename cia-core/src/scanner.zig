const std = @import("std");
const ArrayList = std.ArrayList;
const Git = @import("git.zig").Git;

/// Finds existing tracked Zig files, or all Zig files outside a repository.
pub fn find_source_files(allocator: std.mem.Allocator, io: std.Io) ![][]const u8 {
    // Own paths only: walker entries contain borrowed directory handles.
    var source_files: ArrayList([]const u8) = try .initCapacity(allocator, 64);
    defer {
        for (source_files.items) |path| allocator.free(path);
        source_files.deinit(allocator);
    }
    var repository = try Git.init(allocator, io, ".");
    defer if (repository) |*repo| repo.deinit();
    const directory = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer directory.close(io);
    try walk(allocator, io, directory, if (repository) |*repo| repo else null, &source_files);
    return try source_files.toOwnedSlice(allocator);
}

fn walk(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    repository: ?*const Git,
    source_files: *ArrayList([]const u8),
) !void {
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory and
            (std.mem.eql(u8, entry.basename, ".git") or std.mem.eql(u8, entry.basename, ".jj")))
        {
            walker.leave(io);
            continue;
        }
        if (try isSourceFile(repository, entry)) {
            const path = try allocator.dupe(u8, entry.path);
            errdefer allocator.free(path);
            try source_files.append(allocator, path);
        }
    }
}

/// Outside a Git repository, the file kind and .zig extension are sufficient.
fn isSourceFile(repository: ?*const Git, entry: std.Io.Dir.Walker.Entry) !bool {
    if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) return false;
    if (repository) |repo| return try repo.isGitFile(entry.path);
    return true;
}

test "outside Git only Zig files qualify" {
    var entry: std.Io.Dir.Walker.Entry = .{
        .dir = .cwd(),
        .basename = "source.zig",
        .path = "source.zig",
        .kind = .file,
    };
    try std.testing.expect(try isSourceFile(null, entry));
    entry.path = "source.txt";
    try std.testing.expect(!try isSourceFile(null, entry));
    entry.path = "directory.zig";
    entry.kind = .directory;
    try std.testing.expect(!try isSourceFile(null, entry));
}

test "scanner instantiates with Zig 0.16 IO" {
    const paths = try find_source_files(std.testing.allocator, std.testing.io);
    defer std.testing.allocator.free(paths);
    defer for (paths) |path| std.testing.allocator.free(path);
}
