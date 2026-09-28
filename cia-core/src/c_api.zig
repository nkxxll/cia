//! C adapter: no Zig allocators, slices, errors, or Io objects cross the ABI.
const std = @import("std");
const core = @import("cia-core");
const allocator = std.heap.page_allocator;
const Result = struct { model: core.LinesModel };

const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    scan_failed = 3,
};

const File = extern struct {
    path: ?[*]const u8,
    path_length: usize,
    lines: usize,
};

export fn cia_core_scan(path: ?[*:0]const u8, out_result: ?*?*Result) Status {
    const output = out_result orelse return .invalid_argument;
    output.* = null;
    const root_path = path orelse return .invalid_argument;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const root = std.Io.Dir.cwd().openDir(io, std.mem.span(root_path), .{ .iterate = true }) catch
        return .scan_failed;
    defer root.close(io);
    const result = allocator.create(Result) catch return .out_of_memory;
    result.model = core.scan(allocator, io, root) catch |err| {
        allocator.destroy(result);
        return if (err == error.OutOfMemory) .out_of_memory else .scan_failed;
    };
    output.* = result;
    return .ok;
}

export fn cia_core_result_destroy(result: ?*Result) void {
    const owned = result orelse return;
    owned.model.deinit();
    allocator.destroy(owned);
}

export fn cia_core_result_file_count(result: *const Result) usize {
    return result.model.files.items.len;
}

export fn cia_core_result_total_lines(result: *const Result) usize {
    return result.model.total_lines;
}

export fn cia_core_result_warning_count(result: *const Result) usize {
    return result.model.warning_count;
}

export fn cia_core_result_file(result: *const Result, index: usize, out_file: ?*File) Status {
    const output = out_file orelse return .invalid_argument;
    output.* = .{ .path = null, .path_length = 0, .lines = 0 };
    if (index >= result.model.files.items.len) return .invalid_argument;
    const file = result.model.files.items[index];
    output.* = .{ .path = file.path.ptr, .path_length = file.path.len, .lines = file.lines };
    return .ok;
}
