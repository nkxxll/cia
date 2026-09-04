const std = @import("std");

pub const Command = enum {
    lines,
};

pub const ParseError = error{
    UnknownCommand,
    UnexpectedArgument,
};

pub fn parse(args: []const []const u8) ParseError!?Command {
    if (args.len == 0) return null;
    if (!std.mem.eql(u8, args[0], "lines")) return error.UnknownCommand;
    if (args.len != 1) return error.UnexpectedArgument;

    return .lines;
}

pub fn run(command: Command) void {
    switch (command) {
        .lines => {}, // Placeholder for line-counting command behavior.
    }
}

test "parse lines command" {
    try std.testing.expectEqual(Command.lines, (try parse(&.{"lines"})).?);
    try std.testing.expectEqual(null, try parse(&.{}));
    try std.testing.expectError(error.UnknownCommand, parse(&.{"unknown"}));
    try std.testing.expectError(error.UnexpectedArgument, parse(&.{ "lines", "extra" }));
}
