const Application = @import("application.zig").Application;

pub fn main() void {
    var application: Application = .{};
    application.run();
}
