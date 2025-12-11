<p align="center">
  <a href="https://pyk.sh">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/pyk/bench/blob/main/.github/logo-dark.svg">
      <img alt="pyk/bench logo" src="https://github.com/pyk/bench/blob/main/.github/logo-light.svg">
    </picture>
  </a>
</p>

<p align="center">
  Fast & Accurate Benchmarking for Zig
<p>

<p align="center">
  <img src="https://img.shields.io/badge/zig-0.16.0--dev-x?style=flat&labelColor=00f&color=fff&style=flat&logo=zig&logoColor=fff" alt="Zig Version">
  <img src="https://img.shields.io/badge/version-alpha-x?style=flat&labelColor=00f&color=fff&style=flat" alt="Alpha lib">
  <img src="https://img.shields.io/github/check-runs/pyk/bench/main?colorA=00f&colorB=fff&style=flat&logo=github" alt="CI Runs">
  <img src="https://img.shields.io/github/license/pyk/bench?colorA=00f&colorB=fff&style=flat" alt="MIT License">
</p>

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
- **Zero Dependencies**: Implemented in pure Zig using only the standard
  library.

## Installation

Fetch latest version:

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
try bench.report({ .metrics = &.{res} });
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

The default `bench.report` prints a human-readable table to stdout. It handles
units (ns, us, ms, s) and coloring automatically.

```sh
$ zig build quicksort
Benchmarking Sorting Algorithms Against Random Input (N=10000)...
Benchmark Summary: 3 benchmarks run
├─ Unsafe Quicksort (Lomuto)   358.64us    110.98MB/s   1.29x faster
│  └─ cycles: 1.6M      instructions: 1.2M      ipc: 0.75       miss: 65
├─ Unsafe Quicksort (Hoare)    383.02us    104.32MB/s   1.21x faster
│  └─ cycles: 1.7M      instructions: 1.3M      ipc: 0.76       miss: 56
└─ std.mem.sort                462.25us     86.45MB/s   [baseline]
   └─ cycles: 2.0M      instructions: 2.6M      ipc: 1.30       miss: 143
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

## Notes

- This library is designed to show you "what", not "why". I recommend using a
  proper profiling tool such as `perf` on linux + Firefox Profiler to answer
  "why".
- `doNotOptimizeAway` is your friend. For example if you are benchmarking some
  scanner/tokenizer:

  ```zig
    while (true) {
        const token = try scanner.next();
        if (token == .end) break;
        total_ops += 1;
        std.mem.doNotOptimizeAway(token); // CRITICAL
    }
  ```

- To get `cycles`, `instructions`, `ipc` (instructions per cycle) and
  `cache_misses` metrics on Linux, you may need to enable the
  `kernel.perf_event_paranoid`.

## Prior Art

- [hendriknielaender/zBench](https://github.com/hendriknielaender/zBench)
- [Hejsil/zig-bench](https://github.com/Hejsil/zig-bench)
- [briangold/metron](https://github.com/briangold/metron)
- [dweiller/zubench](https://github.com/dweiller/zubench)

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
# Disable
sudo sysctl -w kernel.perf_event_paranoid=2

# Enable
sudo sysctl -w kernel.perf_event_paranoid=-1
```

## Devlog

- [Fixing Microbenchmark Accuracy](https://pyk.sh/blog/2025-12-07-bench-fixing-microbenchmark-accuracy-in-zig)
- [Fixing Zig benchmark where `std.mem.doNotOptimizeAway` was ignored](https://pyk.sh/blog/2025-12-08-bench-fixing-constant-folding)
- [Writing a Type-Safe Linux Perf Interface in Zig](https://pyk.sh/blog/2025-12-11-type-safe-linux-perf-event-open-in-zig)

## License

MIT. Use it for whatever.
