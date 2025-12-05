const std = @import("std");
const testing = std.testing;

const bench = @import("root.zig");

fn noOp() !void {
    // Pure overhead measurement
}

fn busyWork() !void {
    var x: u64 = 0;
    // Sufficiently large loop to be measurable, but fast enough for unit tests
    for (0..50_000) |i| {
        x +%= i;
    }
    std.mem.doNotOptimizeAway(x);
}

fn sleepWork() !void {
    var threaded = std.Io.Threaded.init(testing.allocator);
    defer threaded.deinit();
    const io = threaded.io();
    try io.sleep(.fromMilliseconds(1), .awake);
    std.mem.doNotOptimizeAway(io);
}

// Global buffer for memory test
var src_buf: [16 * 1024]u8 = undefined;
var dst_buf: [16 * 1024]u8 = undefined;

fn copyWork() !void {
    @memcpy(&dst_buf, &src_buf);
    std.mem.doNotOptimizeAway(dst_buf);
}

test "run: basic check" {
    const allocator = testing.allocator;
    const stats_noop = try bench.run(allocator, noOp, .{});

    // The minimum cannot be larger than the maximum
    try testing.expect(stats_noop.min_ns <= stats_noop.max_ns);

    // The median must be within the bounds
    try testing.expect(stats_noop.median_ns >= stats_noop.min_ns);
    try testing.expect(stats_noop.median_ns <= stats_noop.max_ns);

    // Execution must take some time (non-zero)
    try testing.expect(stats_noop.min_ns > 0);

    const stats_busy = try bench.run(allocator, busyWork, .{});

    // The busy function MUST be slower than the no-op
    try testing.expect(stats_busy.median_ns > stats_noop.median_ns);

    // The gap should be significant (e.g busy is at least 2x slower)
    // This proves the tool is actually measuring the function body,
    // not just the overhead of the tool itself.
    try testing.expect(stats_busy.median_ns > (stats_noop.median_ns * 2));

    const stats_sleep = try bench.run(allocator, sleepWork, .{});
    const target_ns = 1 * std.time.ns_per_ms;

    // We check if the result is reasonably close to 1ms.
    // Note: OS Sleep is imprecise. It will always be >= target, never less.
    // We allow a "scheduler noise" overhead (e.g., +2ms tolerance for CI environments).
    try testing.expect(stats_sleep.median_ns >= target_ns);

    const tolerance = 2 * std.time.ns_per_ms;
    try testing.expect(stats_sleep.median_ns < (target_ns + tolerance));
}

test "run: bandwidth check" {
    const allocator = testing.allocator;
    @memset(&src_buf, 0xAA);
    const stats = try bench.run(allocator, copyWork, .{
        .sample_size = 1000,
        .bytes_per_op = src_buf.len,
    });

    try testing.expect(stats.mb_sec > 0);
    try testing.expect(stats.mb_sec > 1.0); // Sanity check
}
