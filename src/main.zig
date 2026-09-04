const std = @import("std");
const Application = @import("application.zig").Application;
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (try cli.parse(args[1..])) |command| {
        cli.run(command);
        return;
    }

    var application: Application = .{};
    application.run();
}
