const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const Runner = @import("Runner.zig");

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

test "basic metrics" {
    const allocator = testing.allocator;
    const noop_metrics = try Runner.run(allocator, "NoOp", noOp, .{}, .{});

    // The minimum cannot be larger than the maximum
    try testing.expect(noop_metrics.min_ns <= noop_metrics.max_ns);

    // The median must be within the bounds
    try testing.expect(noop_metrics.median_ns >= noop_metrics.min_ns);
    try testing.expect(noop_metrics.median_ns <= noop_metrics.max_ns);

    // Execution must take some time (non-zero)
    try testing.expect(noop_metrics.min_ns > 0);

    const busy_metrics = try Runner.run(allocator, "Busy", busyWork, .{}, .{});

    // The busy function MUST be slower than the no-op
    try testing.expect(busy_metrics.median_ns > noop_metrics.median_ns);

    // The gap should be significant (e.g busy is at least 2x slower)
    // This proves the tool is actually measuring the function body,
    // not just the overhead of the tool itself.
    try testing.expect(busy_metrics.median_ns > (noop_metrics.median_ns * 2));

    const sleep_metrics = try Runner.run(allocator, "Sleep", sleepWork, .{}, .{});
    const target_ns = 1 * std.time.ns_per_ms;

    // We check if the result is reasonably close to 1ms.
    // Note: OS Sleep is imprecise. It will always be >= target, never less.
    try testing.expect(sleep_metrics.median_ns >= target_ns);

    const tolerance = 2 * std.time.ns_per_ms;
    try testing.expect(sleep_metrics.median_ns < (target_ns + tolerance));
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

test "run with args" {
    const allocator = testing.allocator;

    // Generate test data outside the benchmark
    const len = 100_000;
    var input = try allocator.alloc(u8, len);
    defer allocator.free(input);
    @memset(input, ' ');
    input[len - 1] = 'x'; // Stop at the end

    const m_naive = try Runner.run(allocator, "Naive", skipWhitespaceNaive, .{input}, .{ .sample_size = 100 });
    const m_simd = try Runner.run(allocator, "SIMD", skipWhitespaceSIMD, .{input}, .{ .sample_size = 100 });

    try testing.expect(m_naive.median_ns > 0);
    try testing.expect(m_simd.median_ns > 0);

    // The fake SIMD should be faster because it increments by 4
    try testing.expect(m_simd.median_ns < m_naive.median_ns);
}

// Global buffer for memory test
var src_buf: [16 * 1024]u8 = undefined;
var dst_buf: [16 * 1024]u8 = undefined;

fn copyWork() !void {
    @memcpy(&dst_buf, &src_buf);
    std.mem.doNotOptimizeAway(dst_buf);
}

test "bandwidth check" {
    const allocator = testing.allocator;
    @memset(&src_buf, 0xAA);
    const metrics = try Runner.run(allocator, "Copy", copyWork, .{}, .{
        .sample_size = 1000,
        .bytes_per_op = src_buf.len,
    });

    try testing.expect(metrics.mb_sec > 0);
    try testing.expect(metrics.mb_sec > 1.0); // Sanity check
}

fn fastIncrement(val: *u64) !void {
    val.* +%= 1;
    std.mem.doNotOptimizeAway(val.*);
}

test "metrics accuracy" {
    const allocator = testing.allocator;
    var x: u64 = 0;

    // Run the benchmark on a sub-nanosecond operation
    const metrics = try Runner.run(allocator, "FastIncrement", fastIncrement, .{&x}, .{
        .warmup_iters = 100,
        .sample_size = 1000,
    });

    // Sanity check: It must take some time
    try testing.expect(metrics.median_ns > 0.0);

    // If batching is broken, this will measure the OS timer overhead.
    // In Release mode: Function call overhead is ~1ns, Timer is ~20ns. Check for < 10ns.
    // In Debug mode: Function call overhead is ~10-20ns. Timer is ~20ns.
    //                We relax the check to < 50ns to pass in standard 'zig build test'.
    const threshold = if (builtin.mode == .Debug) 50.0 else 10.0;

    if (metrics.median_ns >= threshold) {
        std.debug.print(
            "\nFAIL: Operation took {d:.2}ns (Mode: {s}), which exceeds threshold of {d:.2}ns.\n",
            .{ metrics.median_ns, @tagName(builtin.mode), threshold },
        );
        return error.BatchingFailed;
    }
}

///////////////////////////////////////////////////////////////////////////////
// Supported function's return signature

fn functionReturnVoid() void {
    _ = 1;
}

fn functionReturnVoidError() !void {
    _ = 1;
}

fn functionReturnValue() u64 {
    return 1;
}

fn functionReturnValueError() !u64 {
    return 1;
}

test "run: suppported signatures" {
    const allocator = testing.allocator;

    _ = try Runner.run(allocator, "functionReturnVoid", functionReturnVoid, .{}, .{});
    _ = try Runner.run(allocator, "functionReturnVoidError", functionReturnVoidError, .{}, .{});
    _ = try Runner.run(allocator, "functionReturnValue", functionReturnValue, .{}, .{});
    _ = try Runner.run(allocator, "functionReturnValueError", functionReturnValueError, .{}, .{});
}

///////////////////////////////////////////////////////////////////////////////
// Fibonacci

fn fibNaive(n: u64) u64 {
    if (n <= 1) return n;
    return fibNaive(n - 1) + fibNaive(n - 2);
}

fn fibIterative(n: u64) u64 {
    if (n == 0) return 0;

    var a: u64 = 0;
    var b: u64 = 1;
    for (2..n + 1) |_| {
        const c = a + b;
        a = b;
        b = c;
    }

    return b;
}

test "run: fibonacci" {
    const allocator = testing.allocator;
    const opts = Runner.Options{
        .sample_size = 100,
        .warmup_iters = 3,
    };
    const m_naive = try Runner.run(allocator, "fibNaive", fibNaive, .{@as(u64, 30)}, opts);
    const m_iter = try Runner.run(allocator, "fibIterative", fibIterative, .{@as(u64, 30)}, opts);

    try testing.expect(m_naive.mean_ns > m_iter.mean_ns * 100);
}
