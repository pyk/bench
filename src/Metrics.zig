///////////////////////////////////////////////////////////////////////////////
// Meta

/// The identifier string for the benchmark
name: []const u8,
/// Total number of measurement samples collected
samples: usize,
/// Number of executions per sample (batch size)
iterations: u64,

///////////////////////////////////////////////////////////////////////////////
// Time

/// Minimum execution time per operation (nanoseconds)
min_ns: f64,
/// Maximum execution time per operation (nanoseconds)
max_ns: f64,
/// Mean execution time (nanoseconds)
mean_ns: f64,
/// Median execution time (nanoseconds)
median_ns: f64,
/// Standard deviation of the execution time
std_dev_ns: f64,

///////////////////////////////////////////////////////////////////////////////
// Throughput

/// Calculated operations per second
ops_sec: f64,
/// Data throughput in MB/s (populated if `bytes_per_op` > 0)
mb_sec: f64,

///////////////////////////////////////////////////////////////////////////////
// Hardware (Linux only, null otherwise)

/// Average CPU cycles per operation
cycles: ?f64 = null,
/// Average CPU instructions executed per operation
instructions: ?f64 = null,
/// Instructions Per Cycle (efficiency ratio)
ipc: ?f64 = null,
/// Average cache misses per operation
cache_misses: ?f64 = null,
