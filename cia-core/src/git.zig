const std = @import("std");
const Allocator = std.mem.Allocator;
const git = @cImport({
    @cInclude("git2.h");
});

pub const Git = struct {
    allocator: Allocator,
    repository: *git.git_repository,
    index: *git.git_index,
    directory_prefix: []u8,

    const Self = @This();

    /// Loads the containing repository's index. Null means no repository;
    /// filesystem failures and errors opening a repository remain errors.
    pub fn init(gpa: Allocator, io: std.Io, directory: []const u8) !?Self {
        const absolute = try std.Io.Dir.cwd().realPathFileAlloc(io, directory, gpa);
        defer gpa.free(absolute);
        if (git.git_libgit2_init() < 0) return error.GitInitFailed;
        errdefer _ = git.git_libgit2_shutdown();

        var repository: ?*git.git_repository = null;
        const result = git.git_repository_open_ext(&repository, absolute.ptr, 0, null);
        if (result == git.GIT_ENOTFOUND) {
            _ = git.git_libgit2_shutdown();
            return null;
        }
        if (result < 0) return error.GitRepositoryOpenFailed;
        errdefer git.git_repository_free(repository);

        const workdir = git.git_repository_workdir(repository);
        if (workdir == null) return error.GitBareRepository;
        const prefix = try std.fs.path.relative(gpa, absolute, null, std.mem.span(workdir), absolute);
        errdefer gpa.free(prefix);
        var index: ?*git.git_index = null;
        if (git.git_repository_index(&index, repository) < 0)
            return error.GitIndexOpenFailed;
        return .{
            .allocator = gpa,
            .repository = repository.?,
            .index = index.?,
            .directory_prefix = prefix,
        };
    }

    pub fn deinit(self: *Self) void {
        git.git_index_free(self.index);
        git.git_repository_free(self.repository);
        self.allocator.free(self.directory_prefix);
        _ = git.git_libgit2_shutdown();
        self.* = undefined;
    }

    /// Path is relative to the directory passed to init. Includes conflicts.
    pub fn isGitFile(self: *const Self, path: []const u8) !bool {
        if (std.mem.indexOfScalar(u8, path, 0) != null or std.fs.path.isAbsolute(path))
            return error.InvalidGitPath;
        const joined = try std.fs.path.join(self.allocator, &.{ self.directory_prefix, path });
        defer self.allocator.free(joined);
        const terminated = try self.allocator.dupeZ(u8, joined);
        defer self.allocator.free(terminated);
        if (std.fs.path.sep != '/') {
            for (terminated) |*byte| {
                if (byte.* == std.fs.path.sep) byte.* = '/';
            }
        }
        for (0..4) |stage| {
            if (git.git_index_get_bypath(self.index, terminated.ptr, @intCast(stage)) != null)
                return true;
        }
        return false;
    }
};

test "index membership from a repository subdirectory" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "src", .default_dir);
    const absolute = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(absolute);
    if (git.git_libgit2_init() < 0) return error.GitInitFailed;
    defer _ = git.git_libgit2_shutdown();
    var repository: ?*git.git_repository = null;
    if (git.git_repository_init(&repository, absolute.ptr, 0) < 0)
        return error.GitRepositoryInitFailed;
    defer git.git_repository_free(repository);
    var index: ?*git.git_index = null;
    if (git.git_repository_index(&index, repository) < 0) return error.GitIndexOpenFailed;
    defer git.git_index_free(index);
    var entry = std.mem.zeroes(git.git_index_entry);
    const content = "const value = 1;\n";
    if (git.git_blob_create_from_buffer(&entry.id, repository, content.ptr, content.len) < 0)
        return error.GitBlobCreateFailed;
    entry.path = "src/tracked.zig";
    entry.mode = git.GIT_FILEMODE_BLOB;
    if (git.git_index_add(index, &entry) < 0) return error.GitIndexAddFailed;
    entry.path = "src/conflicted.zig";
    if (git.git_index_conflict_add(index, null, &entry, null) < 0)
        return error.GitIndexConflictFailed;
    if (git.git_index_write(index) < 0) return error.GitIndexWriteFailed;

    const subdirectory = try std.fs.path.join(gpa, &.{ absolute, "src" });
    defer gpa.free(subdirectory);
    var loaded = (try Git.init(gpa, io, subdirectory)).?;
    defer loaded.deinit();
    try std.testing.expect(try loaded.isGitFile("tracked.zig"));
    try std.testing.expect(try loaded.isGitFile("conflicted.zig"));
    try std.testing.expect(!try loaded.isGitFile("untracked.zig"));
    try std.testing.expectError(error.InvalidGitPath, loaded.isGitFile("bad\x00path"));
}

test "directory outside a repository returns null" {
    try std.testing.expect(try Git.init(std.testing.allocator, std.testing.io, "/tmp") == null);
}
