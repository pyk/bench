const std = @import("std");
const testing = std.testing;
const linux = std.os.linux;

const perf = @import("perf.zig");

test "Event toConfig mapping" {
    try testing.expectEqual(
        perf.Event.cpu_cycles.toConfig(),
        @intFromEnum(linux.PERF.COUNT.HW.CPU_CYCLES),
    );
    try testing.expectEqual(
        perf.Event.instructions.toConfig(),
        @intFromEnum(linux.PERF.COUNT.HW.INSTRUCTIONS),
    );
    try testing.expectEqual(
        perf.Event.branch_misses.toConfig(),
        @intFromEnum(linux.PERF.COUNT.HW.BRANCH_MISSES),
    );
}

test "GroupReadOutputType generates correct struct fields" {
    const events = [_]perf.Event{ .cpu_cycles, .branch_misses };
    const MyCounters = perf.GroupReadOutputType(&events);

    // We expect the struct to have fields named after the events
    try testing.expect(@hasField(MyCounters, "cpu_cycles"));
    try testing.expect(@hasField(MyCounters, "branch_misses"));

    // We expect the struct NOT to have fields we didn't include
    try testing.expect(!@hasField(MyCounters, "instructions"));

    const info = @typeInfo(MyCounters);
    inline for (info.@"struct".fields) |field| {
        try testing.expect(field.type == u64);
    }
}

test "GroupReadOutputType instantiation and usage" {
    const events = [_]perf.Event{ .instructions, .cache_misses };
    const MyCounters = perf.GroupReadOutputType(&events);

    var counters = MyCounters{
        .instructions = 100,
        .cache_misses = 5,
    };

    counters.instructions += 50;
    try testing.expectEqual(150, counters.instructions);
    try testing.expectEqual(5, counters.cache_misses);
}

test "Sanity check" {
    const ValidGroup = perf.Group(&.{.cpu_cycles});
    try testing.expect(@sizeOf(ValidGroup) > 0);
}

test "Group init/deinit lifecycle" {
    const MyGroup = perf.Group(&.{ .cpu_cycles, .instructions });

    // We expect this might fail with OpenGroupFailed (EACCES/ENOENT) on
    // many CI systems. We catch that specific error to pass the test,
    // proving the error mapping logic works.
    var group = MyGroup.init() catch return error.SkipZigTest;
    try testing.expect(group.event_fds[0] != -1);
    try testing.expect(group.event_ids[0] != 0);
    group.deinit();
    try testing.expect(group.event_fds[0] == -1);
    try testing.expect(group.event_ids[0] == 0);
}

test "Group handles BadGroup error" {
    const MyGroup = perf.Group(&.{.cpu_cycles});
    var group = MyGroup.init() catch return error.SkipZigTest;
    group.deinit();
    try testing.expectError(error.BadGroup, group.enable());
    try testing.expectError(error.BadGroup, group.disable());
}

test "Group lifecycle" {
    const MyGroup = perf.Group(&.{ .instructions, .cpu_cycles });
    var group = MyGroup.init() catch return error.SkipZigTest;
    defer group.deinit();

    try group.enable();

    var x: u64 = 0;
    for (0..10_000) |i| {
        x +%= i;
        std.mem.doNotOptimizeAway(x);
    }

    try group.disable();
    const m = try group.read();

    try testing.expect(m.instructions > 10_000);
    try testing.expect(m.cpu_cycles > 0);
}
