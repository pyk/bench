const std = @import("std");
const bench = @import("bench");

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

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const opts = bench.Options{
        .sample_size = 100,
        .warmup_iters = 3,
    };
    const m_naive = try bench.run(allocator, "fibNaive", fibNaive, .{@as(u64, 30)}, opts);
    const m_iter = try bench.run(allocator, "fibIterative", fibIterative, .{@as(u64, 30)}, opts);

    try bench.report(.{
        .metrics = &.{ m_naive, m_iter },
        .baseline_index = 0, // naive as baseline
    });
}
