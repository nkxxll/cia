//! Buffered logical physical-line counting.
const std = @import("std");
const simd = std.simd;

/// Owns a reusable read buffer. A counter may be moved, but must not be used
/// concurrently because each file count reuses the same buffer.
pub const LineCounter = struct {
    buffer: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !LineCounter {
        if (buffer_size == 0) return error.InvalidBufferSize;
        return .{
            .buffer = try allocator.alloc(u8, buffer_size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LineCounter) void {
        self.allocator.free(self.buffer);
        self.* = undefined;
    }

    /// Counts logical physical lines: an empty input has zero lines, and a
    /// non-empty input has one line per newline plus an unterminated final line.
    pub fn countBuffer(_: *const LineCounter, data: []const u8) usize {
        if (data.len == 0) return 0;

        return countNewlines(data) + @intFromBool(data[data.len - 1] != '\n');
    }

    pub fn countFile(self: *LineCounter, io: std.Io, file: std.Io.File) !usize {
        return self.countFileCancelable(io, file, null);
    }

    pub fn countFileCancelable(
        self: *LineCounter,
        io: std.Io,
        file: std.Io.File,
        cancelled: ?*const std.atomic.Value(bool),
    ) !usize {
        var lines: usize = 0;
        var has_data = false;
        var last_byte: u8 = undefined;
        var file_reader = file.reader(io, self.buffer);
        const reader = &file_reader.interface;

        while (true) {
            if (cancelled) |flag| {
                if (flag.load(.acquire)) return error.Cancelled;
            }
            const chunk = reader.peekGreedy(1) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => return file_reader.err.?,
            };

            has_data = true;
            last_byte = chunk[chunk.len - 1];
            lines += countNewlines(chunk);
            reader.toss(chunk.len);
        }

        return lines + @intFromBool(has_data and last_byte != '\n');
    }
};

fn countNewlines(data: []const u8) usize {
    var lines: usize = 0;
    var remaining = data;

    if (simd.suggestVectorLength(u8)) |length| {
        const V = @Vector(length, u8);
        const newline: V = @splat('\n');

        while (remaining.len >= length) {
            const chunk: V = remaining[0..length].*;
            lines += @intCast(simd.countTrues(chunk == newline));
            remaining = remaining[length..];
        }
    }

    for (remaining) |byte| lines += @intFromBool(byte == '\n');
    return lines;
}

test "countBuffer counts logical physical lines" {
    var counter = try LineCounter.init(std.testing.allocator, 1);
    defer counter.deinit();

    const cases = [_]struct {
        data: []const u8,
        expected: usize,
    }{
        .{ .data = "", .expected = 0 },
        .{ .data = "x", .expected = 1 },
        .{ .data = "\n", .expected = 1 },
        .{ .data = "text\ntext", .expected = 2 },
        .{ .data = "\ntext", .expected = 2 },
        .{ .data = "text\n", .expected = 1 },
        .{ .data = "\n\n", .expected = 2 },
        .{ .data = "one\r\ntwo\r\nthree", .expected = 3 },
    };

    for (cases) |case| {
        try std.testing.expectEqual(case.expected, counter.countBuffer(case.data));
    }

    const vector_length = simd.suggestVectorLength(u8) orelse 16;
    var large: [vector_length * 3 + 5]u8 = @splat('x');
    var expected: usize = 0;
    for (&large, 0..) |*byte, i| {
        if (i % 7 == 0) {
            byte.* = '\n';
            expected += 1;
        }
    }

    expected += @intFromBool(large[large.len - 1] != '\n');
    try std.testing.expectEqual(expected, counter.countBuffer(&large));
}

test "countFile includes an unterminated final line across small reads" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "lines.zig", .data = "one\ntwo\nthree" });

    const file = try tmp.dir.openFile(io, "lines.zig", .{});
    defer file.close(io);
    var counter = try LineCounter.init(std.testing.allocator, 2);
    defer counter.deinit();

    try std.testing.expectEqual(3, try counter.countFile(io, file));
}
