//! Buffered logical physical-line counting.
const std = @import("std");
const simd = std.simd;

/// Counts the logical lines in a file this means that a started line at the end
/// of the file is counted as line (contrast: wc -l counts newline characters)
pub fn countLogicalLines(data: []const u8) usize {
    if (data.len == 0) return 0;

    return countNewlines(data) + @intFromBool(data[data.len - 1] != '\n');
}

/// Counts newline characters like wc -l
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
