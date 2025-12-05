const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("bench", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    ///////////////////////////////////////////////////////////////////////////
    // zig build test - Run the tests

    const test_step = b.step("test", "Run tests");
    const test_filter = b.option([]const u8, "test-filter", "Filter tests");
    const mod_test = b.addTest(.{
        .root_module = mod,
        .filters = if (test_filter) |filter| &.{filter} else &.{},
    });
    const mod_test_run = b.addRunArtifact(mod_test);
    test_step.dependOn(&mod_test_run.step);
}
