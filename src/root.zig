const std = @import("std");
const math = std.math;
const sort = std.sort;
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

/// A specific function pointer type, strictly enforcing fn() void
const VoidFn = *const fn () anyerror!void;

/// Metrics of the execution
pub const Metrics = struct {
    name: []const u8,
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

pub const ReportOptions = struct {
    metrics: []const Metrics,
    /// The index in 'metrics' to use as the baseline for comparison (e.g 1.00x).
    /// If null, no comparison column is shown.
    baseline_index: ?usize = null,
};

pub fn run(allocator: Allocator, name: []const u8, function: VoidFn, options: Options) !Metrics {
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

    return Metrics{
        .name = name,
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

/// Writes the formatted report to a specific writer
pub fn writeReport(writer: *Writer, options: ReportOptions) !void {
    if (options.metrics.len == 0) return;

    // Calculate Columns Widths
    var max_name_len: usize = 4; //  Min width for "Name"
    var has_bandwidth = false;

    for (options.metrics) |res| {
        if (res.name.len > max_name_len) max_name_len = res.name.len;
        if (res.mb_sec > 0.001) has_bandwidth = true;
    }

    // Print Header
    try writer.writeAll("Name");
    _ = try writer.splatByte(' ', max_name_len - 4);
    try writer.print(" | {s:>10} | {s:>10} | {s:>12}", .{ "Median", "Mean", "StdDev" });

    if (has_bandwidth) {
        try writer.print(" | {s:>14}", .{"Bandwidth"});
    } else {
        try writer.print(" | {s:>14}", .{"Throughput"});
    }

    if (options.baseline_index) |idx| {
        if (idx < options.metrics.len) {
            try writer.print(" | {s:>15}", .{"vs Base"});
        }
    }
    try writer.print("\n", .{});

    // Separator
    {
        const baseline_width = if (options.baseline_index != null) @as(usize, 18) else 0;
        const total_width: usize = max_name_len + 3 + 10 + 3 + 10 + 3 + 12 + 3 + 14 + baseline_width;
        _ = try writer.splatByte('-', total_width);
        try writer.print("\n", .{});
    }

    // Print Rows
    for (options.metrics, 0..) |s, i| {
        try writer.print("{s}", .{s.name});
        _ = try writer.splatByte(' ', max_name_len - s.name.len);

        try writer.print(" | {d:>7} ns | {d:>7} ns | {d:>9.2} ns", .{ s.median_ns, s.mean_ns, s.std_dev_ns });

        if (has_bandwidth) {
            if (s.mb_sec >= 1000) {
                try writer.print(" | {d:>9.2} GB/s", .{s.mb_sec / 1000.0});
            } else {
                try writer.print(" | {d:>9.2} MB/s", .{s.mb_sec});
            }
        } else {
            try writer.print(" | {d:>9.0} op/s", .{s.ops_sec});
        }

        // Comparison Logic
        if (options.baseline_index) |base_idx| {
            if (base_idx < options.metrics.len) {
                const base = options.metrics[base_idx];
                if (i == base_idx) {
                    try writer.print(" | {s:>15}", .{"-"});
                } else {
                    const base_f = @as(f64, @floatFromInt(base.median_ns));
                    const curr_f = @as(f64, @floatFromInt(s.median_ns));

                    if (curr_f > 0 and base_f > 0) {
                        if (curr_f < base_f) {
                            try writer.print(" | {d:>8.2}x faster", .{base_f / curr_f});
                        } else {
                            try writer.print(" | {d:>8.2}x slower", .{curr_f / base_f});
                        }
                    } else {
                        try writer.print(" | {s:>15}", .{"?"});
                    }
                }
            }
        }
        try writer.print("\n", .{});
    }
}

/// Prints a formatted summary table to stdout.
pub fn report(options: ReportOptions) !void {
    var stdout_buffer: [0x2000]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try writeReport(stdout, options);
}

test {
    _ = @import("test.zig");
}
