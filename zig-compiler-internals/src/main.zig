const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zig_compiler_internals = @import("zig_compiler_internals");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const SubCommand = enum {
    cc,
};

const InitializeError = error{
    ParsingOptionsError,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const sub_com = if (parseArgs(init.minimal.args)) |sub| sub else {
        return InitializeError.ParsingOptionsError;
    };

    switch (sub_com) {
        .cc => try computeCC(init.io, gpa),
    }
}

fn parseArgs(args: std.process.Args) ?SubCommand {
    var iterator = args.iterate();
    _ = iterator.next();
    if (iterator.next()) |sub| {
        if (std.mem.eql(u8, sub, "cc")) {
            return .cc;
        }
        return null;
    }
    return null;
}

fn computeCC(io: Io, gpa: Allocator) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buffer);
    var dir = try Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        const ext = std.fs.path.extension(entry.path);

        if (!std.mem.eql(u8, ext, ".zig")) {
            continue;
        }

        const content = try entry.dir.readFileAllocOptions(io, entry.basename, gpa, .unlimited, .of(u8), 0);
        defer gpa.free(content);
        var cc_info = zig_compiler_internals.CCInfo.init(gpa, content, entry.path);
        defer cc_info.deinit();
        try cc_info.compute();
        try cc_info.print(&stdout.interface);
    }
    try stdout.interface.flush();
}
