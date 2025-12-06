const builtin = @import("builtin");
const std = @import("std");
const math = std.math;
const sort = std.sort;
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const tty = std.Io.tty;

const Perf = @import("Perf.zig");

/// Metrics of the execution
pub const Metrics = struct {
    name: []const u8,
    // Time
    min_ns: u64,
    max_ns: u64,
    mean_ns: f64,
    median_ns: u64,
    std_dev_ns: f64,
    // Throughput
    samples: usize,
    ops_sec: f64,
    mb_sec: f64,
    // Hardware (Linux only, 0 otherwise)
    cycles: ?f64 = null,
    instructions: ?f64 = null,
    ipc: ?f64 = null,
    cache_misses: ?f64 = null,
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

pub fn run(allocator: Allocator, name: []const u8, function: anytype, args: anytype, options: Options) !Metrics {
    assertFunctionDef(function, args);

    for (0..options.warmup_iters) |_| {
        std.mem.doNotOptimizeAway(function);
        std.mem.doNotOptimizeAway(args);
        try @call(.auto, function, args);
    }

    const samples = try allocator.alloc(u64, options.sample_size);
    defer allocator.free(samples);

    var timer = try Timer.start();

    for (0..options.sample_size) |i| {
        timer.reset();
        std.mem.doNotOptimizeAway(function);
        std.mem.doNotOptimizeAway(args);
        try @call(.auto, function, args);
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

    var metrics = Metrics{
        .name = name,
        .min_ns = samples[0],
        .max_ns = samples[samples.len - 1],
        .mean_ns = mean,
        .median_ns = samples[options.sample_size / 2],
        .std_dev_ns = math.sqrt(variance),
        .samples = options.sample_size,
        .ops_sec = ops_sec,
        .mb_sec = mb_sec,
    };

    if (builtin.os.tag == .linux) {
        if (Perf.init()) |p| {
            var perf = p;
            defer perf.deinit();

            try perf.capture();
            for (0..options.sample_size) |_| {
                std.mem.doNotOptimizeAway(function);
                std.mem.doNotOptimizeAway(args);
                try @call(.auto, function, args);
            }
            try perf.stop();

            const m = try perf.read();

            const sample_f = @as(f64, @floatFromInt(options.sample_size));
            const avg_cycles = @as(f64, @floatFromInt(m.cycles)) / sample_f;
            const avg_instr = @as(f64, @floatFromInt(m.instructions)) / sample_f;
            const avg_misses = @as(f64, @floatFromInt(m.cache_misses)) / sample_f;

            metrics.cycles = avg_cycles;
            metrics.instructions = avg_instr;
            metrics.cache_misses = avg_misses;
            if (avg_cycles > 0) {
                metrics.ipc = avg_instr / avg_cycles;
            }
        } else |_| {} // skip counter if we can't open use it
    }

    return metrics;
}

fn assertFunctionDef(function: anytype, args: anytype) void {
    // Verify args is a tuple
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("Expected 'args' to be a tuple, found " ++ @typeName(ArgsType));
    }

    // Unwrap function type
    const FnType = @TypeOf(function);
    if (@typeInfo(FnType) == .pointer) {
        FnType = @typeInfo(FnType).pointer.child;
    }
    const fn_info = @typeInfo(FnType);
    if (fn_info != .@"fn") {
        @compileError("Expected 'function' to be a function or function pointer, found " ++ @typeName(@TypeOf(function)));
    }

    // Verify argument count matches
    if (fn_info.@"fn".params.len != args_info.@"struct".fields.len) {
        @compileError(std.fmt.comptimePrint(
            "Function expects {d} arguments, but args tuple has {d}",
            .{ fn_info.Fn.params.len, args_info.Struct.fields.len },
        ));
    }
}

////////////////////////////////////////////////////////////////////////////////
// reporters

fn writeColor(writer: anytype, color: tty.Color, text: []const u8) !void {
    const config = tty.Config.detect(std.fs.File.stdout());
    if (config != .no_color) {
        switch (color) {
            .reset => try writer.writeAll("\x1b[0m"),
            .red => try writer.writeAll("\x1b[31m"),
            .green => try writer.writeAll("\x1b[32m"),
            .blue => try writer.writeAll("\x1b[34m"),
            .cyan => try writer.writeAll("\x1b[36m"),
            .dim => try writer.writeAll("\x1b[2m"),
            .black => try writer.writeAll("\x1b[90m"),
            else => try writer.writeAll(""),
        }
    }
    try writer.writeAll(text);
    if (config != .no_color) try writer.writeAll("\x1b[0m");
}

/// Writes the formatted report to a specific writer
pub fn writeReport(writer: *Writer, options: ReportOptions) !void {
    if (options.metrics.len == 0) return;

    try writer.print("Benchmark Summary: {d} benchmarks run\n", .{options.metrics.len});

    var max_name_len: usize = 0;
    for (options.metrics) |m| max_name_len = @max(max_name_len, m.name.len);

    for (options.metrics, 0..) |m, i| {
        const is_last_item = i == options.metrics.len - 1;

        // --- ROW 1: High Level (Name | Time | Speed | Comparison) ---
        const tree_char = if (is_last_item) "└─ " else "├─ ";
        try writeColor(writer, .bright_black, tree_char);
        try writeColor(writer, .cyan, m.name);
        // try writer.print("{s}{s}", .{ tree_char, m.name });

        // Align name
        const padding = max_name_len - m.name.len + 2;
        _ = try writer.splatByte(' ', padding);

        try fmtTime(writer, @as(f64, @floatFromInt(m.median_ns)));
        try writer.writeAll("   ");

        if (m.mb_sec > 0.001) {
            try fmtBandwidth(writer, m.mb_sec);
        } else {
            try fmtOps(writer, m.ops_sec);
        }

        // Comparison (On the first line now)
        if (options.baseline_index) |base_idx| {
            try writer.writeAll("   ");
            if (i == base_idx) {
                try writeColor(writer, .blue, "[baseline]");
            } else if (base_idx < options.metrics.len) {
                const base = options.metrics[base_idx];
                const base_f = @as(f64, @floatFromInt(base.median_ns));
                const curr_f = @as(f64, @floatFromInt(m.median_ns));

                if (curr_f > 0 and base_f > 0) {
                    if (curr_f < base_f) {
                        try writer.writeAll("\x1b[32m"); // Green manually to mix with print
                        try writer.print("{d:.2}x faster", .{base_f / curr_f});
                        try writer.writeAll("\x1b[0m");
                    } else {
                        try writer.writeAll("\x1b[31m");
                        try writer.print("{d:.2}x slower", .{curr_f / base_f});
                        try writer.writeAll("\x1b[0m");
                    }
                } else {
                    try writer.writeAll("-");
                }
            }
        }
        try writer.writeByte('\n');

        // Only printed if we have hardware stats
        if (m.cycles) |cycles| {
            const sub_tree_prefix = if (is_last_item) "   └─ " else "│  └─ ";
            try writer.writeAll(sub_tree_prefix);
            try writeColor(writer, .dim, "cycles: ");
            try fmtInt(writer, cycles);
        }

        if (m.instructions) |instructions| {
            try writer.writeAll("\t");
            try writeColor(writer, .dim, "instructions: ");
            try fmtInt(writer, instructions);
        }

        if (m.ipc) |ipc| {
            try writer.writeAll("\t");
            try writeColor(writer, .dim, "ipc: ");
            try writer.print("{d:.2}", .{ipc});
        }

        if (m.cache_misses) |cache_missess| {
            try writer.writeAll("\t");
            try writeColor(writer, .dim, "miss: ");
            try fmtInt(writer, cache_missess);

            try writer.writeByte('\n');
        }
    }
}

/// Prints a formatted summary table to stdout.
pub fn report(options: ReportOptions) !void {
    var stdout_buffer: [0x2000]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try writeReport(stdout, options);
}

////////////////////////////////////////////////////////////////////////////////
// formatters

fn fmtInt(writer: *Writer, val: f64) !void {
    if (val < 1000) {
        try writer.print("{d:.0}", .{val});
    } else if (val < 1_000_000) {
        try writer.print("{d:.1}k", .{val / 1000.0});
    } else if (val < 1_000_000_000) {
        try writer.print("{d:.1}M", .{val / 1_000_000.0});
    } else {
        try writer.print("{d:.1}G", .{val / 1_000_000_000.0});
    }
}

fn fmtTime(writer: *Writer, ns: f64) !void {
    var buf: [64]u8 = undefined;
    var slice: []u8 = undefined;

    if (ns < 1000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.0}ns", .{ns});
    } else if (ns < 1_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}us", .{ns / 1000.0});
    } else if (ns < 1_000_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}ms", .{ns / 1_000_000.0});
    } else {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}s", .{ns / 1_000_000_000.0});
    }
    try padLeft(writer, slice, 9);
}

fn fmtOps(writer: *Writer, ops: f64) !void {
    var buf: [64]u8 = undefined;
    var slice: []u8 = undefined;

    if (ops < 1000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.0}/s", .{ops});
    } else if (ops < 1_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}K/s", .{ops / 1000.0});
    } else if (ops < 1_000_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}M/s", .{ops / 1_000_000.0});
    } else {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}G/s", .{ops / 1_000_000_000.0});
    }
    try padLeft(writer, slice, 11);
}

fn fmtBandwidth(writer: *Writer, mb: f64) !void {
    var buf: [64]u8 = undefined;
    var slice: []u8 = undefined;

    if (mb >= 1000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}GB/s", .{mb / 1000.0});
    } else {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}MB/s", .{mb});
    }
    try padLeft(writer, slice, 11);
}

// Pads with spaces on the left (for numbers)
fn padLeft(writer: *Writer, text: []const u8, width: usize) !void {
    if (text.len < width) {
        _ = try writer.splatByte(' ', width - text.len);
    }
    try writer.writeAll(text);
}

// Pads with spaces on the right (for text/comparisons)
fn padRight(writer: *Writer, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    if (text.len < width) {
        _ = try writer.splatByte(' ', width - text.len);
    }
}

////////////////////////////////////////////////////////////////////////////////
// tests

test {
    _ = @import("test.zig");
    if (builtin.os.tag == .linux) {
        _ = @import("Perf.test.zig");
    }
}
