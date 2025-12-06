// References: https://man7.org/linux/man-pages/man2/perf_event_open.2.html

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const posix = std.posix;

const Perf = @This();
const PERF_EVENT_IOC_ID = linux.IOCTL.IOR('$', 7, u64);

leader_fd: posix.fd_t = -1,
sibling_fds: [2]posix.fd_t = .{ -1, -1 },

/// IDs assigned by the kernel to identify events in the read buffer.
/// Indices: 0=Cycles, 1=Instructions, 2=CacheMisses
ids: [3]u64 = .{ 0, 0, 0 },

pub const Measurements = struct {
    cycles: u64,
    instructions: u64,
    cache_misses: u64,
};

pub fn init() !Perf {
    var self = Perf{};

    // CPU Cycles (Group Leader)
    self.leader_fd = try openEvent(.cpu_cycles, -1);
    self.ids[0] = try getId(self.leader_fd);

    {
        const fd = try openEvent(.instructions, self.leader_fd);
        self.ids[1] = try getId(fd);
        self.sibling_fds[0] = fd;
    }

    {
        const fd = try openEvent(.cache_misses, self.leader_fd);
        self.ids[2] = try getId(fd);
        self.sibling_fds[1] = fd;
    }

    return self;
}

pub fn deinit(self: *Perf) void {
    if (self.leader_fd != -1) {
        _ = linux.close(self.leader_fd);
        self.leader_fd = -1;
    }
    for (self.sibling_fds, 0..) |fd, i| {
        if (fd != -1) _ = linux.close(fd);
        self.sibling_fds[i] = -1;
    }
}

pub fn capture(self: *Perf) !void {
    if (self.leader_fd == -1) return;
    const reset = linux.ioctl(self.leader_fd, linux.PERF.EVENT_IOC.RESET, 0);
    if (std.c.errno(reset) != .SUCCESS) @panic("ioctl/reset fails");
    const enable = linux.ioctl(self.leader_fd, linux.PERF.EVENT_IOC.ENABLE, 0);
    if (std.c.errno(enable) != .SUCCESS) @panic("ioctl/enable fails");
}

pub fn stop(self: *Perf) !void {
    if (self.leader_fd == -1) return;
    const disable = linux.ioctl(self.leader_fd, linux.PERF.EVENT_IOC.DISABLE, 0);
    if (std.c.errno(disable) != .SUCCESS) @panic("ioctl/disable fails");
}

/// Reads the counter values.
/// Returns a struct with the collected data.
pub fn read(self: *Perf) !Measurements {
    var m = Measurements{
        .cycles = 0,
        .instructions = 0,
        .cache_misses = 0,
    };
    if (self.leader_fd == -1) return m;

    // Format: PERF_FORMAT_TOTAL_TIME_ENABLED | PERF_FORMAT_TOTAL_TIME_RUNNING | PERF_FORMAT_ID | PERF_FORMAT_GROUP
    // Layout: nr, time_enabled, time_running, [value, id], [value, id], ...
    // Max items = 3. Header = 3 u64. Total u64s = 3 + (2 * 3) = 9
    var buf: [16]u64 = undefined;

    _ = try posix.read(self.leader_fd, std.mem.sliceAsBytes(&buf));

    const nr = buf[0];
    const time_enabled = buf[1];
    const time_running = buf[2];

    // std.debug.print("nr={d}\n", .{nr});
    // std.debug.print("time_running={d}\n", .{time_running});

    if (time_running == 0) return m;

    var i: usize = 0;
    while (i < nr) : (i += 1) {
        const base_idx = 3 + (i * 2);
        if (base_idx + 1 >= buf.len) break;

        var val = buf[base_idx];
        const id = buf[base_idx + 1];

        // std.debug.print("i={d} val={d} (before)\n", .{ i, val });
        if (time_running < time_enabled) {
            val = @as(u64, @intFromFloat(@as(f64, @floatFromInt(val)) * (@as(f64, @floatFromInt(time_enabled)) / @as(f64, @floatFromInt(time_running)))));
        }

        // std.debug.print("i={d} val={d} (after)\n", .{ i, val });
        // std.debug.print("i={d} id={d}\n", .{ i, id });

        if (id == self.ids[0]) m.cycles = val;
        if (id == self.ids[1]) m.instructions = val;
        if (id == self.ids[2]) m.cache_misses = val;
    }

    return m;
}

const Event = enum { cpu_cycles, instructions, cache_misses };

fn openEvent(event: Event, group_fd: posix.fd_t) !posix.fd_t {
    const config: u64 = switch (event) {
        .cpu_cycles => @intFromEnum(linux.PERF.COUNT.HW.CPU_CYCLES),
        .instructions => @intFromEnum(linux.PERF.COUNT.HW.INSTRUCTIONS),
        .cache_misses => @intFromEnum(linux.PERF.COUNT.HW.CACHE_MISSES),
    };

    var attr = std.mem.zeroes(linux.perf_event_attr);
    attr.type = linux.PERF.TYPE.HARDWARE;
    attr.config = config;

    // Enable grouping and ID tracking
    attr.read_format = 1 << 0 | 1 << 1 | 1 << 2 | 1 << 3;

    attr.flags.disabled = (group_fd == -1); // Only leader starts disabled
    attr.flags.inherit = true;
    attr.flags.exclude_kernel = true;
    attr.flags.exclude_hv = true;

    const fd = try posix.perf_event_open(&attr, 0, -1, group_fd, 0);
    return fd;
}

fn getId(fd: i32) !u64 {
    var id: u64 = 0;
    if (linux.ioctl(fd, PERF_EVENT_IOC_ID, @intFromPtr(&id)) != 0) {
        return error.IoctlFailed;
    }
    return id;
}
