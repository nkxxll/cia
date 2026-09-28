const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.addModule("cia-core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const library = b.addLibrary(.{
        .name = "cia-core",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cia-core", .module = core }},
        }),
    });
    library.installHeader(b.path("include/cia_core.h"), "cia_core.h");
    b.installArtifact(library);

    const tests = b.addTest(.{ .root_module = core });
    const test_step = b.step("test", "Run headless analysis and C ABI tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const smoke = b.addExecutable(.{
        .name = "c-api-test",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    smoke.root_module.addCSourceFile(.{ .file = b.path("tests/c_api.c"), .flags = &.{"-std=c11"} });
    smoke.root_module.linkLibrary(library);
    const run_smoke = b.addRunArtifact(smoke);
    run_smoke.addDirectoryArg(b.path("tests/fixtures"));
    test_step.dependOn(&run_smoke.step);
}
