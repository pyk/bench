# bench

Tiny benchmarking library for Zig.

```zig
const bench = @import("root.zig");

pub fn main() !void {
    // Add your allocator here

    // Run the benchmark, collect some metrics
    const metrics = try bench.run(allocator, "Sleep", sleepWork, .{});

    // Do anything with metrics here

    // or you can simply report it to stdout
    try bench.report({ .metrics = &.{metrics} });
}

fn sleepWork() !void {
    var threaded = std.Io.Threaded.init(testing.allocator);
    defer threaded.deinit();
    const io = threaded.io();
    try io.sleep(.fromMilliseconds(1), .awake);
    std.mem.doNotOptimizeAway(io);
}
```

Default reporter looks like this:

```
Name       |     Median |       Mean |       StdDev |     Throughput
--------------------------------------------------------------------
NoOp       |      60 ns |      58 ns |      3.88 ns |  17108933 op/s
Sleep      | 1058766 ns | 1058698 ns |   2950.23 ns |       945 op/s
```

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
| CPU         | Cycles                       | CPU clock cycles used                                        |
| CPU         | Instructions                 | Total CPU instructions executed                              |
| CPU         | IPC                          | Instructions Per Cycle (Efficiency)                          |
| CPU         | Cache Misses                 | L1/L2 Cache misses                                           |
| Comparative | ✅ Speedup (x)               | "12.5x faster" (Current / Baseline).                         |
| Comparative | Relative Diff (%)            | "+ 50%" or "- 10%".                                          |
| Comparative | Big O                        | Complexity Analysis (O(n), O(log n)).                        |
| Comparative | R² (Goodness of Fit)         | How well the data fits a linear model.                       |

Other metrics will be added as needed. Feel free to send a pull request.

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

## License

MIT. Use it for whatever.
