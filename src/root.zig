const std = @import("std");
const math = std.math;
const sort = std.sort;
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

/// A specific function pointer type, strictly enforcing fn() void
const VoidFn = *const fn () anyerror!void;

/// Statistical results of the execution
pub const Stats = struct {
    min_ns: u64,
    max_ns: u64,
    mean_ns: u64,
    median_ns: u64,
    std_dev_ns: f64,
    samples: usize,
    ops_sec: f64,
    mb_sec: f64,
};

pub const Options = struct {
    warmup_iters: u64 = 100,
    sample_size: u64 = 1000,
    bytes_per_op: usize = 0,
};

pub fn run(allocator: Allocator, function: VoidFn, options: Options) !Stats {
    for (0..options.warmup_iters) |_| {
        std.mem.doNotOptimizeAway(function);
        try function();
    }

    const samples = try allocator.alloc(u64, options.sample_size);
    defer allocator.free(samples);

    var timer = try Timer.start();

    for (0..options.sample_size) |i| {
        timer.reset();
        try function();
        samples[i] = timer.read();
    }

    // Sort samples to find the median and process min/max
    sort.block(u64, samples, {}, sort.asc(u64));

    var sum: u128 = 0;
    for (samples) |s| sum += s;

    const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(options.sample_size));

    // Calculate Variance for Standard Deviation
    var sum_sq_diff: f64 = 0;
    for (samples) |s| {
        const diff = @as(f64, @floatFromInt(s)) - mean;
        sum_sq_diff += diff * diff;
    }
    const variance = sum_sq_diff / @as(f64, @floatFromInt(options.sample_size));

    // Calculate Operations Per Second
    const ops_sec = if (mean > 0) 1_000_000_000.0 / mean else 0;

    // Calculate MB/s (Megabytes per second)
    // Formula: (Ops/Sec * Bytes/Op) / 1,000,000
    const mb_sec = if (options.bytes_per_op > 0)
        (ops_sec * @as(f64, @floatFromInt(options.bytes_per_op))) / 1_000_000.0
    else
        0;

    return Stats{
        .min_ns = samples[0],
        .max_ns = samples[samples.len - 1],
        .mean_ns = @as(u64, @intFromFloat(mean)),
        .median_ns = samples[options.sample_size / 2],
        .std_dev_ns = math.sqrt(variance),
        .samples = options.sample_size,
        .ops_sec = ops_sec,
        .mb_sec = mb_sec,
    };
}

test {
    _ = @import("test.zig");
}
