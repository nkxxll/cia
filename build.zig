//! Workspace convenience commands. Each child package also builds independently.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const options = .{ .target = b.standardTargetOptions(.{}), .optimize = b.standardOptimizeOption(.{}) };
    const core = b.dependency("cia_core", options);
    const ui = b.dependency("cia_opengl", options);
    const exe = ui.artifact("cia");
    b.installArtifact(exe);
    b.installArtifact(core.artifact("cia-core"));

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run CIA").dependOn(&run.step);

    const tests = b.step("test", "Run all headless tests");
    tests.dependOn(&core.builder.top_level_steps.get("test").?.step);
    tests.dependOn(&ui.builder.top_level_steps.get("test").?.step);
}
