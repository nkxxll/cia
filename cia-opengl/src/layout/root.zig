//! Pure treemap geometry; no GTK or OpenGL dependency.
const treemap = @import("treemap.zig");
pub const Rect = treemap.Rect;
pub const Tile = treemap.Tile;
pub const layout = treemap.layout;

test {
    _ = treemap;
}
