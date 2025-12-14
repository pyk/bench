<p align="center">
  <a href="https://pyk.sh">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/pyk/bench/blob/main/.github/logo-dark.svg">
      <img alt="pyk/bench logo" src="https://github.com/pyk/bench/blob/main/.github/logo-light.svg">
    </picture>
  </a>
</p>

<p align="center">
  Fast & Accurate Microbenchmarking for Zig
<p>

<p align="center">
  <img src="https://img.shields.io/badge/zig-0.16.0--dev-x?style=flat&labelColor=00f&color=fff&style=flat&logo=zig&logoColor=fff" alt="Zig Version">
  <img src="https://img.shields.io/badge/version-alpha-x?style=flat&labelColor=00f&color=fff&style=flat" alt="Alpha lib">
  <img src="https://img.shields.io/github/check-runs/pyk/bench/main?colorA=00f&colorB=fff&style=flat&logo=github" alt="CI Runs">
  <img src="https://img.shields.io/github/license/pyk/bench?colorA=00f&colorB=fff&style=flat" alt="MIT License">
</p>

## Demo

Let's benchmark fib:

```zig
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
    const m_naive = try bench.run(allocator, "fibNaive/30", fibNaive, .{30}, opts);
    const m_iter = try bench.run(allocator, "fibIterative/30", fibIterative, .{30}, opts);

    try bench.report(.{
        .metrics = &.{ m_naive, m_iter },
        .baseline_index = 0, // naive as baseline
    });
}
```

Run it, and you will get the following output in your terminal:

```markdown
| Benchmark         |    Time |    Speedup | Iterations |    Ops/s | Cycles | Instructions |  IPC | Cache Misses |
| :---------------- | ------: | ---------: | ---------: | -------: | -----: | -----------: | ---: | -----------: |
| `fibNaive/30`     | 1.78 ms |      1.00x |          1 |  563.2/s |   8.1M |        27.8M | 3.41 |          0.3 |
| `fibIterative/30` | 3.44 ns | 516055.19x |     300006 | 290.6M/s |   15.9 |         82.0 | 5.15 |          0.0 |
```

The benchmark report generates valid Markdown, so you can copy-paste it directly
into a markdown file:

| Benchmark         |    Time |    Speedup | Iterations |    Ops/s | Cycles | Instructions |  IPC | Cache Misses |
| :---------------- | ------: | ---------: | ---------: | -------: | -----: | -----------: | ---: | -----------: |
| `fibNaive/30`     | 1.78 ms |      1.00x |          1 |  563.2/s |   8.1M |        27.8M | 3.41 |          0.3 |
| `fibIterative/30` | 3.44 ns | 516055.19x |     300006 | 290.6M/s |   15.9 |         82.0 | 5.15 |          0.0 |

## Features

- **CPU Counters**: Measures CPU cycles, instructions, IPC, and cache misses
  directly from the kernel (Linux only).
- **Argument Support**: Pass pre-calculated data to your functions to separate
  setup overhead from the benchmark loop.
- **Baseline Comparison**: Easily compare multiple implementations against a
  reference function to see relative speedups or regressions.
- **Flexible Reporting**: Access raw metric data programmatically to generate
  custom reports (JSON, CSV) or assert performance limits in CI.
- **Easy Throughput Metrics**: Automatically calculates operations per second
  and data throughput (MB/s, GB/s) when payload size is provided.
- **Robust Statistics**: Uses median and standard deviation to provide reliable
  metrics despite system noise.

## Installation

Fetch the latest version:

```sh
zig fetch --save=bench https://github.com/pyk/bench/archive/main.tar.gz
```

Then add this to your `build.zig`:

```zig
const bench = b.dependency("bench", .{
    .target = target,
    .optimize = optimize,
});

// Use it on a module
const mod = b.createModule(.{
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "bench", .module = bench.module("bench") },
    },
});

// Or executable
const my_bench = b.addExecutable(.{
    .name = "my-bench",
    .root_module = b.createModule(.{
        .root_source_file = b.path("bench/my-bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "bench", .module = bench.module("bench") },
        },
    }),
});
```

If you are using it only for tests/benchmarks, it is recommended to mark it as
lazy:

```zig
.dependencies = .{
    .bench = .{
        .url = "...",
        .hash = "...",
        .lazy = true, // here
    },
}
```

## Usage

### Basic Run

To benchmark a single function, pass the allocator, a name, and the function
pointer to `run`.

```zig
const res = try bench.run(allocator, "My Function", myFn, .{});
try bench.report(.{ .metrics = &.{res} });
```

### Run with Arguments

You can generate test data before the benchmark starts and pass it via a tuple.
This ensures the setup cost doesn't pollute your measurements.

```zig
// Setup data outside the benchmark
const input = try generateLargeString(allocator, 10_000);

// Pass input as a tuple
const res = try bench.run(allocator, "Parser", parseFn, .{input}, .{});
```

### Comparing Implementations

You can run multiple benchmarks and compare them against a baseline. The
`baseline_index` determines which result is used as the reference (1.00x).

```zig
const a = try bench.run(allocator, "Implementation A", implA, .{});
const b = try bench.run(allocator, "Implementation B", implB, .{});

try bench.report(.{
    .metrics = &.{ a, b },
    // Use the first metric (Implementation A) as the baseline
    .baseline_index = 0,
});
```

### Measuring Throughput

If your function processes data (like copying memory or parsing strings),
provide `bytes_per_op` to get throughput metrics (MB/s or GB/s).

```zig
const size = 1024 * 1024;
const res = try bench.run(allocator, "Memcpy 1MB", copyFn, .{
    .bytes_per_op = size,
});

// Report will now show GB/s instead of just Ops/s
try bench.report(.{ .metrics = &.{res} });
```

### Configuration

You can tune the benchmark behavior by modifying the `Options` struct.

```zig
const res = try bench.run(allocator, "Heavy Task", heavyFn, .{
    .warmup_iters = 10,     // Default: 100
    .sample_size = 50,      // Default: 1000
});
```

### Built-in Reporter

The default bench.report prints a clean, Markdown-compatible table to stdout. It
automatically handles unit scaling (`ns`, `us`, `ms`, `s`) and formatting.

```markdown
| Benchmark         |    Time |    Speedup | Iterations |    Ops/s | Cycles | Instructions |  IPC | Cache Misses |
| :---------------- | ------: | ---------: | ---------: | -------: | -----: | -----------: | ---: | -----------: |
| `fibNaive/30`     | 1.78 ms |      1.00x |          1 |  563.2/s |   8.1M |        27.8M | 3.41 |          0.3 |
| `fibIterative/30` | 3.44 ns | 516055.19x |     300006 | 290.6M/s |   15.9 |         82.0 | 5.15 |          0.0 |
```

### Custom Reporter

The `run` function returns a `Metrics` struct containing all raw data (min, max,
median, variance, cycles, etc.). You can use this to generate JSON, CSV, or
assert performance limits in CI.

```zig
const metrics = try bench.run(allocator, "MyFn", myFn, .{});

// Access raw fields directly
std.debug.print("Median: {d}ns, Max: {d}ns\n", .{
    metrics.median_ns,
    metrics.max_ns
});
```

## Supported Metrics

The `run` function returns a `Metrics` struct containing the following data
points:

| Category   | Metric         | Description                                                |
| ---------- | -------------- | ---------------------------------------------------------- |
| Meta       | `name`         | The identifier string for the benchmark.                   |
| Time       | `min_ns`       | Minimum execution time per operation (nanoseconds).        |
| Time       | `max_ns`       | Maximum execution time per operation (nanoseconds).        |
| Time       | `mean_ns`      | Arithmetic mean execution time (nanoseconds).              |
| Time       | `median_ns`    | Median execution time (nanoseconds).                       |
| Time       | `std_dev_ns`   | Standard deviation of the execution time.                  |
| Meta       | `samples`      | Total number of measurement samples collected.             |
| Throughput | `ops_sec`      | Calculated operations per second.                          |
| Throughput | `mb_sec`       | Data throughput in MB/s (populated if `bytes_per_op` > 0). |
| Hardware\* | `cycles`       | Average CPU cycles per operation.                          |
| Hardware\* | `instructions` | Average CPU instructions executed per operation.           |
| Hardware\* | `ipc`          | Instructions Per Cycle (efficiency ratio).                 |
| Hardware\* | `cache_misses` | Average cache misses per operation.                        |

_\*Hardware metrics are currently available on Linux only. They will be `null`
on other platforms or if permissions are restricted._

## Tips

### Use Profiling Tools to Find Why Code is Slow

`bench` shows you the time your code takes. It tells you "what" the speed is.
But it does not tell you "why" it is slow. To find out why, use tools like
`perf` on Linux. Or use Firefox Profiler. These tools show you where the CPU
spends time. For example, `perf record` runs your code and collects data. Then
`perf report` shows hotspots. Like too many branches or cache misses. This helps
you fix the real problems.

### Use `std.mem.doNotOptimizeAway`

The compiler can remove code if it thinks it does nothing. For example, if you
compute a value but never use it, the compiler skips the work. This makes
benchmarks wrong. It shows fast times for code that does not run.To stop this,
use `std.mem.doNotOptimizeAway`. Pass your result to it. The compiler must
compute it then. For example, in a scanner or tokenizer:

```zig
while (true) {
    const token = try scanner.next();
    if (token == .end) break;
    std.mem.doNotOptimizeAway(token); // CRITICAL
}
```

Here, `doNotOptimizeAway(token)` forces the compiler to run `scanner.next()`.
Without it, the loop might empty. Always use this on key results. Like counts,
parsed values, or outputs.

### Enable Kernel Perf Event on Linux for Hardware Metrics

On Linux, hardware metrics like cycles and instructions come from the kernel.
But by default, it limits access. You get null values.

To fix, run:

```sh
sudo sysctl -w kernel.perf_event_paranoid=-1
```

This allows your code to read counters. Set to `2` to restrict again.

Check with `cat /proc/sys/kernel/perf_event_paranoid`. Lower values mean more
access. Value `-1` is full. Use it for benchmarks. But be careful in production.

### Avoid Constant Inputs in Benchmarks

If you use constant data like `const input = "hello";`, the compiler knows it at
build time. It can unroll loops or compute results ahead. Your benchmark
measures nothing real. Times stay flat even if data grows.

Instead, use runtime data. Allocate a buffer and fill it.

Bad example:

```zig
const input = "    hello"; // Compiler knows every byte
const res = try bench.run(allocator, "Parser", parse, .{input}, .{});
```

Good example:

```zig
var input = try allocator.alloc(u8, 100);
defer allocator.free(input);
@memset(input[0..4], ' ');
@memcpy(input[4..], "hello");
const res = try bench.run(allocator, "Parser", parse, .{input}, .{});
```

Now, the buffer is dynamic. The compiler cannot fold it. Times scale with real
work. For varying tests, change the memset size each run.

## References

### Prior Art

- [hendriknielaender/zBench](https://github.com/hendriknielaender/zBench)
- [Hejsil/zig-bench](https://github.com/Hejsil/zig-bench)
- [briangold/metron](https://github.com/briangold/metron)
- [dweiller/zubench](https://github.com/dweiller/zubench)

### Resources

- [Google Benchmark User Guide](https://github.com/google/benchmark/blob/main/docs/user_guide.md)

## Development

Install the Zig toolchain via mise (optional):

```shell
mise trust
mise install
```

Run tests:

```bash
zig build test --summary all
```

Build library:

```bash
zig build
```

Enable/disable `kernel.perf_event_paranoid` for debugging:

```sh
# Restrict access
sudo sysctl -w kernel.perf_event_paranoid=2

# Allow access (Required for CPU metrics)
sudo sysctl -w kernel.perf_event_paranoid=-1
```

## Devlog

- [Fixing Microbenchmark Accuracy](https://pyk.sh/blog/2025-12-07-bench-fixing-microbenchmark-accuracy-in-zig)
- [Fixing Zig benchmark where `std.mem.doNotOptimizeAway` was ignored](https://pyk.sh/blog/2025-12-08-bench-fixing-constant-folding)
- [Writing a Type-Safe Linux Perf Interface in Zig](https://pyk.sh/blog/2025-12-11-type-safe-linux-perf-event-open-in-zig)

## License

MIT. Use it for whatever.
