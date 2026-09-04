//! This struct counts the lines of a buffer efficiently with SIMD if SIMD is
//! possible with the CPU architecture. The model is simple either we have
//! count lines from fd which reads a buffer and calls count lines from buffer
//! or we directly call count lines from buffer.
const std = @import("std");
const simd = std.simd;

///! This struct is not thread save it uses one internal buffer to sequentially
///! count the line so may files.
pub const LineCounter = struct {
    buffer: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !LineCounter {
        return .{
            .buffer = try allocator.alloc(u8, buffer_size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LineCounter) void {
        self.allocator.free(self.buffer);
    }

    pub fn countBuffer(_: *const LineCounter, data: []const u8) usize {
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

        for (remaining) |byte| {
            lines += @intFromBool(byte == '\n');
        }

        return lines;
    }

    pub fn countFile(self: *LineCounter, file: std.fs.File) !usize {
        var lines: usize = 0;

        while (true) {
            const n = try file.read(self.buffer);
            if (n == 0) break;

            lines += self.countBuffer(self.buffer[0..n]);
        }

        return lines;
    }
};

test "countBuffer counts newlines across buffer sizes" {
    var counter = try LineCounter.init(std.testing.allocator, 1);
    defer counter.deinit();

    const cases = [_]struct {
        data: []const u8,
        expected: usize,
    }{
        .{ .data = "", .expected = 0 },
        .{ .data = "x", .expected = 0 },
        .{ .data = "\n", .expected = 1 },
        .{ .data = "text\ntext", .expected = 1 },
        .{ .data = "\ntext", .expected = 1 },
        .{ .data = "text\n", .expected = 1 },
        .{ .data = "\n\n", .expected = 2 },
        .{ .data = "one\r\ntwo\r\nthree", .expected = 2 },
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

    try std.testing.expectEqual(expected, counter.countBuffer(&large));
}
