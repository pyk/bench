const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const Perf = @import("Perf.zig");

test "Perf: lifecycle" {
    var perf = try Perf.init();
    defer perf.deinit();

    try perf.capture();

    var x: u64 = 0;
    for (0..10_000) |i| {
        x +%= i;
        std.mem.doNotOptimizeAway(x);
    }
    std.debug.print("TEST\n", .{});

    try perf.stop();
    const m = perf.read();

    // Verify we captured instructions
    if (m.instructions == 0) {
        std.debug.print("WARN: Captured 0 instructions. Check permissions.\n", .{});
    } else {
        try testing.expect(m.instructions > 10_000);
        try testing.expect(m.cycles > 0);
    }
}

test "Perf: cache misses" {
    var perf = try Perf.init();
    defer perf.deinit();

    try perf.capture();

    // Thrash L1 cache
    var buf = try testing.allocator.alloc(u8, 1024 * 1024);
    defer testing.allocator.free(buf);
    @memset(buf, 0xAA);

    var sum: u64 = 0;
    var i: usize = 0;
    while (i < buf.len) : (i += 64) {
        sum +%= buf[i];
    }
    std.mem.doNotOptimizeAway(sum);

    try perf.stop();
    const m = perf.read();
    std.debug.print("m = {any}", .{m});
}
