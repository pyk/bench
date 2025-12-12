const builtin = @import("builtin");
const std = @import("std");
const math = std.math;
const sort = std.sort;
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

const Metrics = @import("Metrics.zig");
const perf = @import("perf.zig");

pub const Options = struct {
    warmup_iters: u64 = 100,
    sample_size: u64 = 1000,
    bytes_per_op: usize = 0,
};

pub fn run(allocator: Allocator, name: []const u8, function: anytype, args: anytype, options: Options) !Metrics {
    assertFunctionDef(function, args);

    // ref: https://pyk.sh/blog/2025-12-08-bench-fixing-constant-folding
    var runtime_args = createRuntimeArgs(function, args);
    std.mem.doNotOptimizeAway(&runtime_args);

    for (0..options.warmup_iters) |_| {
        try execute(function, runtime_args);
    }

    // We need to determine a batch_size such that the total execution time of the batch
    // is large enough to minimize timer resolution noise.
    // Target: 1ms (1,000,000 ns) per measurement block.
    const min_sample_time_ns = 1_000_000;
    var batch_size: u64 = 1;
    var timer = try Timer.start();

    while (true) {
        timer.reset();
        for (0..batch_size) |_| {
            try execute(function, runtime_args);
        }
        const duration = timer.read();

        if (duration >= min_sample_time_ns) break;

        // If the duration is 0 (too fast to measure) or small, scale up
        if (duration == 0) {
            batch_size *= 10;
        } else {
            const ratio = @as(f64, @floatFromInt(min_sample_time_ns)) / @as(f64, @floatFromInt(duration));
            const multiplier = @as(u64, @intFromFloat(std.math.ceil(ratio)));
            if (multiplier <= 1) {
                batch_size *= 2; // Fallback growth
            } else {
                batch_size *= multiplier;
            }
        }
    }

    const samples = try allocator.alloc(f64, options.sample_size);
    defer allocator.free(samples);

    for (0..options.sample_size) |i| {
        timer.reset();
        for (0..batch_size) |_| {
            try execute(function, runtime_args);
        }
        const total_ns = timer.read();
        // Average time per operation for this batch
        samples[i] = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(batch_size));
    }

    // Sort samples to find the median and process min/max
    sort.block(f64, samples, {}, sort.asc(f64));

    var sum: f64 = 0;
    for (samples) |s| sum += s;

    const mean = sum / @as(f64, @floatFromInt(options.sample_size));

    // Calculate Variance for Standard Deviation
    var sum_sq_diff: f64 = 0;
    for (samples) |s| {
        const diff = s - mean;
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
        .iterations = batch_size,
        .ops_sec = ops_sec,
        .mb_sec = mb_sec,
    };

    if (builtin.os.tag == .linux) {
        const events = [_]perf.Event{ .cpu_cycles, .instructions, .cache_misses };
        const perf_group = perf.Group(&events);
        if (perf_group.init()) |pg| {
            var group = pg;
            defer group.deinit();

            try group.enable();
            for (0..options.sample_size) |_| {
                for (0..batch_size) |_| {
                    try execute(function, runtime_args);
                }
            }
            try group.disable();

            const m = try group.read();
            const total_ops = @as(f64, @floatFromInt(options.sample_size * batch_size));
            const avg_cycles = @as(f64, @floatFromInt(m.cpu_cycles)) / total_ops;
            const avg_instr = @as(f64, @floatFromInt(m.instructions)) / total_ops;
            const avg_misses = @as(f64, @floatFromInt(m.cache_misses)) / total_ops;

            metrics.cycles = avg_cycles;
            metrics.instructions = avg_instr;
            metrics.cache_misses = avg_misses;
            if (avg_cycles > 0) {
                metrics.ipc = avg_instr / avg_cycles;
            }
        } else |_| {} // skip counter if we can't open it
    }

    return metrics;
}

inline fn execute(function: anytype, args: anytype) !void {
    const FnType = unwrapFnType(@TypeOf(function));
    const return_type = @typeInfo(FnType).@"fn".return_type.?;

    // Conditional execution based on whether the function can fail
    if (@typeInfo(return_type) == .error_union) {
        const result = try @call(.auto, function, args);
        std.mem.doNotOptimizeAway(result);
    } else {
        const result = @call(.auto, function, args);
        std.mem.doNotOptimizeAway(result);
    }
}

/// Returns the underlying Function type, unwrapping it if it is a pointer.
fn unwrapFnType(comptime T: type) type {
    if (@typeInfo(T) == .pointer) return @typeInfo(T).pointer.child;
    return T;
}

////////////////////////////////////////////////////////////////////////////////
// Function definition checker

fn assertFunctionDef(function: anytype, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("Expected 'args' to be a tuple, found '" ++ @typeName(ArgsType) ++ "'");
    }

    const FnType = unwrapFnType(@TypeOf(function));
    if (@typeInfo(FnType) != .@"fn") {
        @compileError("Expected 'function' to be a function or function pointer, found '" ++ @typeName(@TypeOf(function)) ++ "'");
    }

    const params_len = @typeInfo(FnType).@"fn".params.len;
    const args_len = @typeInfo(ArgsType).@"struct".fields.len;

    if (params_len != args_len) {
        @compileError(std.fmt.comptimePrint(
            "Function expects {d} arguments, but args tuple has {d}",
            .{ params_len, args_len },
        ));
    }
}

////////////////////////////////////////////////////////////////////////////////
// Runtime Arguments Helpers

/// Constructs the runtime argument tuple based on function parameters and input args.
fn createRuntimeArgs(function: anytype, args: anytype) RuntimeArgsType(@TypeOf(function), @TypeOf(args)) {
    const TupleType = RuntimeArgsType(@TypeOf(function), @TypeOf(args));
    var runtime_args: TupleType = undefined;

    // We only need the length here to iterate
    const fn_params = getFnParams(@TypeOf(function));

    inline for (0..fn_params.len) |i| {
        runtime_args[i] = args[i];
    }
    return runtime_args;
}

/// Computes the precise Tuple type required to hold the arguments.
fn RuntimeArgsType(comptime FnType: type, comptime ArgsType: type) type {
    const fn_params = getFnParams(FnType);
    const args_fields = @typeInfo(ArgsType).@"struct".fields;
    comptime var types: [fn_params.len]type = undefined;
    inline for (fn_params, 0..) |p, i| {
        if (p.type) |t| {
            types[i] = t;
        } else {
            types[i] = args_fields[i].type;
        }
    }
    return std.meta.Tuple(&types);
}

/// Helper to unwrap function pointers and retrieve parameter info
fn getFnParams(comptime FnType: type) []const std.builtin.Type.Fn.Param {
    return @typeInfo(unwrapFnType(FnType)).@"fn".params;
}
