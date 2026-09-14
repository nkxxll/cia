//! By convention, root.zig is the root source file when making a package.
pub const CCInfo = @import("CCInfo.zig");

test {
    _ = CCInfo;
}
