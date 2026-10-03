//! Headless source analysis. Results own their paths; callers own input directories.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const find_source_files = @import("scanner.zig").find_source_files;
pub const countLogicalLines = @import("countlines.zig").countLogicalLines;

pub const FileAnalysisResult = struct { loc: u64 };

pub const AnalysisResult = struct {
    loc: u64,
    files: []FileAnalysisResult,
};

/// default capacity for the reading the files at the start of the anlysis
const default_file_read_buffer_capacity = 4096;

pub fn analyzeFiles(allocator: Allocator, io: Io) !AnalysisResult {
    const source_files = try find_source_files(allocator, io);
    defer {
        for (source_files) |path| allocator.free(path);
        allocator.free(source_files);
    }
    var analyzed_files: std.ArrayList(FileAnalysisResult) = try .initCapacity(allocator, 64);
    defer analyzed_files.deinit(allocator);
    var buffer: std.ArrayList(u8) = try .initCapacity(allocator, default_file_read_buffer_capacity);
    defer buffer.deinit(allocator);
    var total_loc: u64 = 0;
    for (source_files) |file| {
        const result = try openCountClose(allocator, io, file, &buffer);
        try analyzed_files.append(allocator, result);
        total_loc += result.loc;
    }
    return .{ .loc = total_loc, .files = try analyzed_files.toOwnedSlice(allocator) };
}

/// Reuses the caller's allocation across files, growing only as needed.
fn openCountClose(allocator: Allocator, io: Io, path: []const u8, buffer: *std.ArrayList(u8)) !FileAnalysisResult {
    const file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;
    // resize does not shrink its only a capacity; list.len = len
    try buffer.resize(allocator, size);
    const read = try file.readPositionalAll(io, buffer.items, 0);
    buffer.items.len = read;
    return .{ .loc = countLogicalLines(buffer.items) };
}

test "file buffer grows and retains its allocation for smaller files" {
    const allocator = std.testing.allocator;
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);
    try buffer.ensureTotalCapacityPrecise(allocator, 1);
    const source = try openCountClose(allocator, std.testing.io, "src/root.zig", &buffer);
    try std.testing.expect(source.loc > 0);
    try std.testing.expect(buffer.capacity > 1);
    const capacity = buffer.capacity;
    const ptr = buffer.items.ptr;
    const empty = try openCountClose(allocator, std.testing.io, "tests/fixtures/empty.zig", &buffer);
    try std.testing.expectEqual(@as(u64, 0), empty.loc);
    try std.testing.expectEqual(capacity, buffer.capacity);
    try std.testing.expectEqual(ptr, buffer.items.ptr);
}

test {
    _ = @import("countlines.zig");
    _ = @import("scanner.zig");
}
