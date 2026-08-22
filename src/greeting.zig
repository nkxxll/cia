const std = @import("std");

pub fn format(buffer: []u8, name: []const u8) error{NoSpaceLeft}![:0]u8 {
    if (name.len == 0) {
        return std.fmt.bufPrintZ(buffer, "Hello, world!", .{}) catch error.NoSpaceLeft;
    }

    return std.fmt.bufPrintZ(buffer, "Hello, {s}!", .{name}) catch error.NoSpaceLeft;
}

test "formats default and named greetings" {
    var buffer: [64]u8 = undefined;

    try std.testing.expectEqualStrings("Hello, world!", try format(&buffer, ""));
    try std.testing.expectEqualStrings("Hello, Zig!", try format(&buffer, "Zig"));
}
