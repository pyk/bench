const std = @import("std");
const testing = std.testing;
const Writer = std.Io.Writer;

const Metrics = @import("Metrics.zig");
const Reporter = @import("Reporter.zig");

fn createMetrics(name: []const u8, ns: f64) Metrics {
    return Metrics{
        .name = name,
        .samples = 100,
        .iterations = 1000000,
        .min_ns = ns,
        .max_ns = ns,
        .mean_ns = ns,
        .median_ns = ns,
        .std_dev_ns = 0,
        .ops_sec = if (ns > 0) 1_000_000_000.0 / ns else 0,
        .mb_sec = 0,
        .cycles = null,
        .instructions = null,
        .ipc = null,
        .cache_misses = null,
    };
}

test "MarkdownReporter: Time Unit Scaling (ns, us, ms, s)" {
    const m_ns = createMetrics("Nano", 100.0);
    const m_us = createMetrics("Micro", 15_000.0);
    const m_ms = createMetrics("Milli", 250_000_000.0);
    const m_s = createMetrics("Second", 5_000_000_000.0);

    var buffer: [16 * 1024]u8 = undefined;
    var w: Writer = .fixed(&buffer);

    try Reporter.write(&w, .{ .metrics = &.{ m_ns, m_us, m_ms, m_s } });

    const expected =
        "| Benchmark |      Time | Iterations |   Ops/s | \n" ++
        "| :-------- | --------: | ---------: | ------: | \n" ++
        "| `Nano`    | 100.00 ns |    1000000 | 10.0M/s | \n" ++
        "| `Micro`   |  15.00 us |    1000000 | 66.7k/s | \n" ++
        "| `Milli`   | 250.00 ms |    1000000 |   4.0/s | \n" ++
        "| `Second`  |    5.00 s |    1000000 |   0.2/s | \n";

    try testing.expectEqualStrings(expected, w.buffered());
}

test "MarkdownReporter: Throughput Mixing (Bytes vs Ops)" {
    // Case A: Only Ops/s (Default)
    const m_ops = createMetrics("OpsOnly", 100.0);

    // Case B: Bytes/s (High throughput)
    // 1000ns = 1M Ops/s. We manually set MB/s.
    var m_bytes = createMetrics("BytesOnly", 1000.0);
    m_bytes.mb_sec = 500.0;

    var buffer: [16 * 1024]u8 = undefined;
    var w: Writer = .fixed(&buffer);

    try Reporter.write(&w, .{ .metrics = &.{ m_ops, m_bytes } });

    // Expectation:
    // 1. Both "Bytes/s" and "Ops/s" columns appear because at least one metric triggered each.
    // 2. OpsOnly has no Bytes/s -> "-"
    // 3. BytesOnly has Bytes/s -> "500.00MB/s". It also has valid Ops/s (1M), so it prints that too.
    const expected =
        "| Benchmark   |      Time | Iterations |    Bytes/s |   Ops/s | \n" ++
        "| :---------- | --------: | ---------: | ---------: | ------: | \n" ++
        "| `OpsOnly`   | 100.00 ns |    1000000 |          - | 10.0M/s | \n" ++
        "| `BytesOnly` |   1.00 us |    1000000 | 500.00MB/s |  1.0M/s | \n";

    try testing.expectEqualStrings(expected, w.buffered());
}

test "MarkdownReporter: Hardware Counters (Sparse Data)" {
    const m_base = createMetrics("Baseline", 100.0);

    var m_full = createMetrics("WithHW", 100.0);
    m_full.cycles = 2500.0;
    m_full.instructions = 5000.0;
    m_full.ipc = 2.0;
    m_full.cache_misses = 15.0;

    var buffer: [16 * 1024]u8 = undefined;
    var w: Writer = .fixed(&buffer);

    try Reporter.write(&w, .{ .metrics = &.{ m_base, m_full } });

    // Expectation:
    // HW columns should appear. Baseline fills them with "-". WithHW fills them with values.
    const expected =
        "| Benchmark  |      Time | Iterations |   Ops/s | Cycles | Instructions |  IPC | Cache Misses | \n" ++
        "| :--------- | --------: | ---------: | ------: | -----: | -----------: | ---: | -----------: | \n" ++
        "| `Baseline` | 100.00 ns |    1000000 | 10.0M/s |      - |            - |    - |            - | \n" ++
        "| `WithHW`   | 100.00 ns |    1000000 | 10.0M/s |   2.5k |         5.0k | 2.00 |         15.0 | \n";

    try testing.expectEqualStrings(expected, w.buffered());
}

test "MarkdownReporter: Baseline Comparison" {
    const m_base = createMetrics("Base", 100.0); // Baseline (100ns)
    const m_fast = createMetrics("Fast", 50.0); // 2x faster (0.50x duration)
    const m_slow = createMetrics("Slow", 200.0); // 2x slower (2.00x duration)

    var buffer: [16 * 1024]u8 = undefined;
    var w: Writer = .fixed(&buffer);

    // Set baseline_index to 0 ("Base")
    try Reporter.write(&w, .{ .metrics = &.{ m_base, m_fast, m_slow }, .baseline_index = 0 });

    const expected =
        "| Benchmark |      Time | Relative | Iterations |   Ops/s | \n" ++
        "| :-------- | --------: | -------: | ---------: | ------: | \n" ++
        "| `Base`    | 100.00 ns |    1.00x |    1000000 | 10.0M/s | \n" ++
        "| `Fast`    |  50.00 ns |    0.50x |    1000000 | 20.0M/s | \n" ++
        "| `Slow`    | 200.00 ns |    2.00x |    1000000 |  5.0M/s | \n";

    try testing.expectEqualStrings(expected, w.buffered());
}
