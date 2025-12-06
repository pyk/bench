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
    const noop_metrics = try bench.run(allocator, "NoOp", noOp, .{}, .{});

    // The minimum cannot be larger than the maximum
    try testing.expect(noop_metrics.min_ns <= noop_metrics.max_ns);

    // The median must be within the bounds
    try testing.expect(noop_metrics.median_ns >= noop_metrics.min_ns);
    try testing.expect(noop_metrics.median_ns <= noop_metrics.max_ns);

    // Execution must take some time (non-zero)
    try testing.expect(noop_metrics.min_ns > 0);

    const busy_metrics = try bench.run(allocator, "Busy", busyWork, .{}, .{});

    // The busy function MUST be slower than the no-op
    try testing.expect(busy_metrics.median_ns > noop_metrics.median_ns);

    // The gap should be significant (e.g busy is at least 2x slower)
    // This proves the tool is actually measuring the function body,
    // not just the overhead of the tool itself.
    try testing.expect(busy_metrics.median_ns > (noop_metrics.median_ns * 2));

    const sleep_metrics = try bench.run(allocator, "Sleep", sleepWork, .{}, .{});
    const target_ns = 1 * std.time.ns_per_ms;

    // We check if the result is reasonably close to 1ms.
    // Note: OS Sleep is imprecise. It will always be >= target, never less.
    // We allow a "scheduler noise" overhead (e.g., +2ms tolerance for CI environments).
    try testing.expect(sleep_metrics.median_ns >= target_ns);

    const tolerance = 2 * std.time.ns_per_ms;
    try testing.expect(sleep_metrics.median_ns < (target_ns + tolerance));
}

test "run: bandwidth check" {
    const allocator = testing.allocator;
    @memset(&src_buf, 0xAA);
    const metrics = try bench.run(allocator, "Copy", copyWork, .{}, .{
        .sample_size = 1000,
        .bytes_per_op = src_buf.len,
    });

    try testing.expect(metrics.mb_sec > 0);
    try testing.expect(metrics.mb_sec > 1.0); // Sanity check
}

test "report: output" {
    const allocator = testing.allocator;
    @memset(&src_buf, 0xAA);
    const copy_metrics = try bench.run(allocator, "Copy", copyWork, .{}, .{
        .sample_size = 1000,
        .bytes_per_op = src_buf.len,
    });

    const noop_metrics = try bench.run(allocator, "NoOp", noOp, .{}, .{});
    const sleep_metrics = try bench.run(allocator, "Sleep", sleepWork, .{}, .{});
    const busy_metrics = try bench.run(allocator, "Busy", busyWork, .{}, .{});

    var single: std.Io.Writer.Allocating = .init(allocator);
    defer single.deinit();
    try bench.writeReport(&single.writer, .{ .metrics = &.{copy_metrics} });

    var double: std.Io.Writer.Allocating = .init(allocator);
    defer double.deinit();
    try bench.writeReport(&double.writer, .{ .metrics = &.{ noop_metrics, sleep_metrics } });

    var baseline: std.Io.Writer.Allocating = .init(allocator);
    defer baseline.deinit();
    try bench.writeReport(&baseline.writer, .{
        .metrics = &.{ noop_metrics, sleep_metrics, busy_metrics },
        .baseline_index = 0,
    });

    std.debug.print("\nsingle:\n{s}\n", .{single.written()});
    std.debug.print("\ndouble:\n{s}\n", .{double.written()});
    std.debug.print("\nbaseline:\n{s}\n", .{baseline.written()});
}

// Simulate a whitespace skipper function
fn skipWhitespaceNaive(input: []const u8) !void {
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (input[i] != ' ') break;
    }
    std.mem.doNotOptimizeAway(i);
}

fn skipWhitespaceSIMD(input: []const u8) !void {
    // Pretend this is SIMD optimized
    var i: usize = 0;
    while (i < input.len) : (i += 4) {
        if (input[i] != ' ') break;
    }
    std.mem.doNotOptimizeAway(i);
}

test "run: with args" {
    const allocator = testing.allocator;

    // Generate test data outside the benchmark
    const len = 100_000;
    var input = try allocator.alloc(u8, len);
    defer allocator.free(input);
    @memset(input, ' ');
    input[len - 1] = 'x'; // Stop at the end

    const m_naive = try bench.run(allocator, "Naive", skipWhitespaceNaive, .{input}, .{ .sample_size = 100 });
    const m_simd = try bench.run(allocator, "SIMD", skipWhitespaceSIMD, .{input}, .{ .sample_size = 100 });

    try testing.expect(m_naive.median_ns > 0);
    try testing.expect(m_simd.median_ns > 0);

    // The fake SIMD should be faster because it increments by 4
    try testing.expect(m_simd.median_ns < m_naive.median_ns);
}
