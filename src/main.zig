const std = @import("std");
const Application = @import("application.zig").Application;
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const initial_screen: Application.Screen = if (try cli.parse(args[1..])) |command|
        switch (command) {
            .lines => .lines,
        }
    else
        .home;

    var application: Application = .{ .initial_screen = initial_screen };
    application.run();
}
