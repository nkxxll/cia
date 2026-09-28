//! Headless source analysis. Results own their paths; callers own input directories.
pub const FileLines = @import("lines_model.zig").FileLines;
pub const LinesModel = @import("lines_model.zig").LinesModel;
pub const LineCounter = @import("countlines.zig").LineCounter;
pub const scan = @import("scanner.zig").scan;
pub const scanCancelable = @import("scanner.zig").scanCancelable;

test {
    _ = @import("countlines.zig");
    _ = @import("lines_model.zig");
    _ = @import("scanner.zig");
}
