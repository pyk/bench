<p align="center">
  <a href="https://pyk.sh">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/pyk/bench/blob/main/.github/logo-dark.png">
      <img alt="pyk/bench logo" src="https://github.com/pyk/bench/blob/main/.github/logo-light.png" width="auto" height="90">
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

Add `bench` as a dependency to your `build.zig`.

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
try bench.report({ .metrics = &.{res} });
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

This tiny benchmark library support (✅) various metrics:

| Category    | Metric                       | Description                                                  |
| ----------- | ---------------------------- | ------------------------------------------------------------ |
| Time        | ✅ Mean / Average            | Arithmetic average of all runs                               |
| Time        | ✅ Median                    | The middle value (less sensitive to outliers)                |
| Time        | ✅ Min / Max                 | The absolute fastest and slowest runs                        |
| Time        | CPU vs Wall Time             | CPU time (active processing) vs Wall time (real world)       |
| Throughput  | ✅ Ops/sec                   | Operations per second                                        |
| Throughput  | ✅ Bytes/sec                 | Data throughput (MB/s, GB/s)                                 |
| Throughput  | Items/sec                    | Discrete items processed per second                          |
| Latency     | Percentiles                  | p75, p99, p99.9. (e.g. "99% of requests were faster than X") |
| Latency     | ✅ Std Dev / Variance        | How much the results deviate from the average                |
| Latency     | Outliers                     | Detecting and reporting anomaly runs                         |
| Latency     | Confidence / Margin of Error | e.g. "± 2.5%"                                                |
| Latency     | Histogram                    | Visual distribution of all runs                              |
| Memory      | Bytes Allocated              | Total heap memory requested per iteration                    |
| Memory      | Allocation Count             | Number of allocation calls                                   |
| CPU         | ✅ Cycles                    | CPU clock cycles used                                        |
| CPU         | ✅ Instructions              | Total CPU instructions executed                              |
| CPU         | ✅ IPC                       | Instructions Per Cycle (Efficiency)                          |
| CPU         | ✅ Cache Misses              | L1/L2 Cache misses                                           |
| Comparative | ✅ Speedup (x)               | "12.5x faster" (Current / Baseline).                         |
| Comparative | Relative Diff (%)            | "+ 50%" or "- 10%".                                          |
| Comparative | Big O                        | Complexity Analysis (O(n), O(log n)).                        |
| Comparative | R² (Goodness of Fit)         | How well the data fits a linear model.                       |

Other metrics will be added as needed. Feel free to send a pull request.

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
- [briangold/metron](https://github.com/briangold/metron)

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
sudo sysctl -w kernel.perf_event_paranoid=3

# Enable
sudo sysctl -w kernel.perf_event_paranoid=-1
```

## License

MIT. Use it for whatever.
