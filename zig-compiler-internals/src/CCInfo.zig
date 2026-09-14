const Self = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;

content: [:0]const u8,
basename: []const u8,
gpa: Allocator,
function_list: ArrayList(Function),
/// Sum of the complexity of all function definitions in the file.
cc: usize,

pub const Function = struct {
    name: []const u8,
    /// Byte offsets delimiting the declaration, with an exclusive end.
    start: usize,
    end: usize,
    cc: usize,
    body_start: usize,
};

/// Borrows content and basename; both must outlive this value and its results.
pub fn init(gpa: Allocator, content: [:0]const u8, basename: []const u8) Self {
    return .{
        .content = content,
        .basename = basename,
        .gpa = gpa,
        .function_list = .empty,
        .cc = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.function_list.deinit(self.gpa);
    self.* = undefined;
}

/// Computes a syntactic cyclomatic complexity: 1 per function, plus 1 for
/// each if, loop, non-else switch prong (grouped values count once), and/or,
/// catch, orelse, and try. Comptime branches are included. Function prototypes
/// and decisions outside function bodies are excluded.
/// Repeated calls replace the previous results; errors leave empty results.
pub fn compute(self: *Self) !void {
    self.function_list.clearRetainingCapacity();
    self.cc = 0;
    errdefer {
        self.function_list.clearRetainingCapacity();
        self.cc = 0;
    }

    var tree = try Ast.parse(self.gpa, self.content, .zig);
    defer tree.deinit(self.gpa);
    if (tree.errors.len != 0) return error.InvalidSyntax;

    // Scan all nodes to discover container methods and local functions too.
    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @enumFromInt(i);
        if (tree.nodeTag(node) != .fn_decl) continue;
        var buffer: [1]Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&buffer, node).?;
        const body = tree.nodeData(node).node_and_node[1];
        const last_token = tree.lastToken(body);
        try self.function_list.append(self.gpa, .{
            .name = tree.tokenSlice(proto.name_token.?),
            .start = tree.tokenStart(tree.firstToken(node)),
            .end = tree.tokenStart(last_token) + tree.tokenSlice(last_token).len,
            .body_start = tree.tokenStart(tree.firstToken(body)),
            .cc = 1,
        });
    }
    std.mem.sort(Function, self.function_list.items, {}, struct {
        fn lessThan(_: void, a: Function, b: Function) bool {
            return a.start < b.start;
        }
    }.lessThan);

    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @enumFromInt(i);
        const decision = switch (tree.nodeTag(node)) {
            .if_simple,
            .@"if",
            .while_simple,
            .while_cont,
            .@"while",
            .for_simple,
            .@"for",
            .bool_and,
            .bool_or,
            .@"catch",
            .@"orelse",
            .@"try",
            => true,
            .switch_case_one,
            .switch_case_inline_one,
            .switch_case,
            .switch_case_inline,
            => tree.fullSwitchCase(node).?.ast.values.len != 0,
            else => false,
        };
        if (!decision) continue;
        const offset = tree.tokenStart(tree.nodeMainToken(node));
        // The last enclosing declaration is the innermost one. Its signature
        // is excluded too, rather than attributed to an enclosing function.
        var index = self.function_list.items.len;
        while (index > 0) {
            index -= 1;
            const function = &self.function_list.items[index];
            if (offset < function.start or offset >= function.end) continue;
            if (offset >= function.body_start) function.cc += 1;
            break;
        }
    }
    for (self.function_list.items) |function| self.cc += function.cc;
}

pub fn print(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s}: CC {d}\n", .{ self.basename, self.cc });
    for (self.function_list.items) |function| {
        try writer.print("  {s} [{d}..{d}): CC {d}\n", .{
            function.name, function.start, function.end, function.cc,
        });
    }
}

test "branches, loops, short circuits, and switch prongs" {
    const source =
        \\extern fn external() void;
        \\fn plain() void {}
        \\fn branching(a: bool, b: bool, xs: []u8, opt: ?u8, err: anyerror!u8) !void {
        \\    if (a and b or a) {} else if (b) {}
        \\    while (a) : ({}) {} else {}
        \\    while (b) {}
        \\    for (xs) |_| {}
        \\    for (xs, 0..) |_, i| { _ = i; } else {}
        \\    _ = opt orelse 0;
        \\    _ = err catch 0;
        \\    _ = try err;
        \\    switch (xs.len) { 0 => {}, 1, 2 => {}, else => {} }
        \\}
    ;
    var info = Self.init(std.testing.allocator, source, "branches.zig");
    defer info.deinit();
    try info.compute();
    try std.testing.expectEqual(2, info.function_list.items.len);
    try std.testing.expectEqual(1, info.function_list.items[0].cc);
    try std.testing.expectEqual(14, info.function_list.items[1].cc);
    try std.testing.expectEqual(15, info.cc);
    try info.compute();
    try std.testing.expectEqual(2, info.function_list.items.len);
    try std.testing.expectEqual(15, info.cc);
}

test "nested methods have independent complexity and source ranges" {
    const source =
        \\const outside = if (true) 1 else 2;
        \\const S = struct {
        \\    pub fn outer() void {
        \\        const Local = struct {
        \\            fn inner() void { if (true) {} }
        \\        };
        \\        if (false) {} else {}
        \\    }
        \\};
    ;
    var info = Self.init(std.testing.allocator, source, "nested.zig");
    defer info.deinit();
    try info.compute();
    try std.testing.expectEqual(2, info.function_list.items.len);
    const outer = info.function_list.items[0];
    const inner = info.function_list.items[1];
    try std.testing.expectEqualStrings("outer", outer.name);
    try std.testing.expectEqualStrings("inner", inner.name);
    try std.testing.expectEqual(2, outer.cc);
    try std.testing.expectEqual(2, inner.cc);
    try std.testing.expectEqual(4, info.cc);
    try std.testing.expectEqualStrings("fn inner() void { if (true) {} }", source[inner.start..inner.end]);
}

test "empty input and syntax errors reset results" {
    var info = Self.init(std.testing.allocator, "fn valid() void {}", "test.zig");
    defer info.deinit();
    try info.compute();
    info.content = "fn broken(";
    try std.testing.expectError(error.InvalidSyntax, info.compute());
    try std.testing.expectEqual(0, info.function_list.items.len);
    try std.testing.expectEqual(0, info.cc);
    info.content = "";
    try info.compute();
    try std.testing.expectEqual(0, info.cc);
}
