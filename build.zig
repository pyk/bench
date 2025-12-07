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

    ///////////////////////////////////////////////////////////////////////////
    // zig build quicksort

    const quicksort_step = b.step("quicksort", "Run quicksort benchmark");
    const quicksort_exe = b.addExecutable(.{
        .name = "quicksort-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/quicksort.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{
                    .name = "bench",
                    .module = mod,
                },
            },
        }),
    });
    const quicksort_run = b.addRunArtifact(quicksort_exe);
    quicksort_step.dependOn(&quicksort_run.step);

    ///////////////////////////////////////////////////////////////////////////
    // zig build repomix - Pack repository using repomix

    var threaded: std.Io.Threaded = .init(b.allocator);
    defer threaded.deinit();
    const io = threaded.io();
    const repomix_step = b.step("repomix", "Pack repository using repomix");
    const timestamp = std.Io.Clock.Timestamp.now(io, .awake) catch @panic("failed to collect timestamp");
    const filename = b.fmt("repomix-bench-{d}.xml", .{timestamp.raw});
    const repomix_cmd = b.addSystemCommand(&.{
        "npx",
        "repomix@latest",
        ".",
        "--style",
        "xml",
        "--ignore",
        ".github,.vscode,test",
        "-o",
        filename,
    });
    repomix_step.dependOn(&repomix_cmd.step);
}
