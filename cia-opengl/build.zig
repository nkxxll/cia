const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("cia_core", .{ .target = target, .optimize = optimize });
    const layout = b.addModule("layout", .{
        .root_source_file = b.path("src/layout/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "cia",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cia-core", .module = core.module("cia-core") },
                .{ .name = "layout", .module = layout },
            },
        }),
    });
    exe.root_module.linkSystemLibrary("gtk4", .{ .use_pkg_config = .force });
    exe.root_module.linkSystemLibrary("epoxy", .{ .use_pkg_config = .force });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run CIA").dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run CLI and layout tests without GTK");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const layout_tests = b.addTest(.{ .root_module = layout });
    test_step.dependOn(&b.addRunArtifact(layout_tests).step);
}
