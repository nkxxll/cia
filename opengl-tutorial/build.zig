const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "opengl-tutorial",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.linkSystemLibrary("gtk4", .{ .use_pkg_config = .force });
    exe.root_module.linkSystemLibrary("epoxy", .{ .use_pkg_config = .force });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);

    const run_step = b.step("run", "Run the OpenGL tutorial");
    run_step.dependOn(&run.step);
}
