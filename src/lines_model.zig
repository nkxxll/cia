const std = @import("std");

pub const FileLines = struct {
    /// Relative to the root passed to the scanner and owned by LinesModel.
    path: []u8,
    lines: usize,
};

/// Owns every file path and the backing storage for `files`.
pub const LinesModel = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList(FileLines) = .empty,
    total_lines: usize = 0,
    warning_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) LinesModel {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LinesModel) void {
        for (self.files.items) |file| self.allocator.free(file.path);
        self.files.deinit(self.allocator);
        self.* = undefined;
    }

    /// Takes ownership of `path` on success. The caller retains ownership if
    /// appending fails.
    pub fn appendOwned(self: *LinesModel, path: []u8, lines: usize) !void {
        try self.files.append(self.allocator, .{ .path = path, .lines = lines });
        self.total_lines += lines;
    }
};
