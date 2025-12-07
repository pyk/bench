const std = @import("std");
const bench = @import("bench");

fn swap(a: *i32, b: *i32) void {
    const temp = a.*;
    a.* = b.*;
    b.* = temp;
}

// Implementation 1: Lomuto Partition Scheme
// Simpler code, but generally performs more swaps than Hoare.
fn partitionLomuto(arr: []i32, low: usize, high: usize) usize {
    const pivot = arr[high];
    var i = low;

    var j = low;
    while (j < high) : (j += 1) {
        if (arr[j] < pivot) {
            swap(&arr[i], &arr[j]);
            i += 1;
        }
    }
    swap(&arr[i], &arr[high]);
    return i;
}

fn quickSortLomuto(arr: []i32, low: isize, high: isize) void {
    if (low < high) {
        const p_idx = partitionLomuto(arr, @intCast(low), @intCast(high));
        quickSortLomuto(arr, low, @as(isize, @intCast(p_idx)) - 1);
        quickSortLomuto(arr, @as(isize, @intCast(p_idx)) + 1, high);
    }
}

// Implementation 2: Hoare Partition Scheme
// More efficient partition logic, often 3x fewer swaps than Lomuto.
fn partitionHoare(arr: []i32, low: usize, high: usize) usize {
    const pivot = arr[low];
    var i: isize = @as(isize, @intCast(low)) - 1;
    var j: isize = @as(isize, @intCast(high)) + 1;

    while (true) {
        while (true) {
            i += 1;
            if (arr[@intCast(i)] >= pivot) break;
        }
        while (true) {
            j -= 1;
            if (arr[@intCast(j)] <= pivot) break;
        }

        if (i >= j) return @intCast(j);
        swap(&arr[@intCast(i)], &arr[@intCast(j)]);
    }
}

fn quickSortHoare(arr: []i32, low: isize, high: isize) void {
    if (low < high) {
        const p_idx = partitionHoare(arr, @intCast(low), @intCast(high));
        quickSortHoare(arr, low, @intCast(p_idx));
        // FIX: Cast p_idx to isize BEFORE adding 1
        quickSortHoare(arr, @as(isize, @intCast(p_idx)) + 1, high);
    }
}

fn stdSort(arr: []i32) void {
    std.mem.sort(i32, arr, {}, std.sort.asc(i32));
}

// Benchmark Wrappers

fn runLomuto(allocator: std.mem.Allocator, input: []const i32) !void {
    const arr = try allocator.alloc(i32, input.len);
    defer allocator.free(arr);
    @memcpy(arr, input);
    quickSortLomuto(arr, 0, @as(isize, @intCast(arr.len)) - 1);
    std.mem.doNotOptimizeAway(arr);
}

fn runHoare(allocator: std.mem.Allocator, input: []const i32) !void {
    const arr = try allocator.alloc(i32, input.len);
    defer allocator.free(arr);
    @memcpy(arr, input);
    quickSortHoare(arr, 0, @as(isize, @intCast(arr.len)) - 1);
    std.mem.doNotOptimizeAway(arr);
}

fn runStdSort(allocator: std.mem.Allocator, input: []const i32) !void {
    const arr = try allocator.alloc(i32, input.len);
    defer allocator.free(arr);
    @memcpy(arr, input);
    stdSort(arr);
    std.mem.doNotOptimizeAway(arr);
}

pub fn main() !void {
    // Use general purpose allocator to catch leaks if any, though page_allocator is fine for bench
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Prepare Data
    const size = 10_000;
    const input = try allocator.alloc(i32, size);
    defer allocator.free(input);

    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    for (input) |*x| x.* = rand.int(i32);

    std.debug.print("Benchmarking Sorting Algorithms Against Random Input (N={d})...\n", .{size});

    // Run Benchmarks
    const opts = bench.Options{
        .sample_size = 100,
        .warmup_iters = 20,
        // Throughput: treating 'size' bytes as the workload gives us MB/s
        .bytes_per_op = size * @sizeOf(i32),
    };

    const m_lomuto = try bench.run(allocator, "Unsafe Quicksort (Lomuto)", runLomuto, .{ allocator, input }, opts);
    const m_hoare = try bench.run(allocator, "Unsafe Quicksort (Hoare)", runHoare, .{ allocator, input }, opts);
    const m_std = try bench.run(allocator, "std.mem.sort", runStdSort, .{ allocator, input }, opts);

    // Report
    // We use std.mem.sort as the baseline (index 2)
    try bench.report(.{
        .metrics = &.{ m_lomuto, m_hoare, m_std },
        .baseline_index = 2,
    });
}
