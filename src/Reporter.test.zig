const std = @import("std");
const testing = std.testing;

const Runner = @import("Runner.zig");
const Reporter = @import("Reporter.zig");

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

test "report fib" {
    const allocator = testing.allocator;
    const opts = Runner.Options{
        .sample_size = 100,
        .warmup_iters = 3,
    };
    const m_naive = try Runner.run(allocator, "fibNaive", fibNaive, .{@as(u64, 20)}, opts);
    const m_iter = try Runner.run(allocator, "fibIterative", fibIterative, .{@as(u64, 20)}, opts);

    try Reporter.report(.{ .metrics = &.{ m_naive, m_iter }, .baseline_index = 0 });
}
