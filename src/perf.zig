const std = @import("std");
const linux = std.os.linux;
const Type = std.builtin.Type;

// Bits for perf_event_attr.read_format
const PERF_FORMAT_TOTAL_TIME_ENABLED = 1 << 0;
const PERF_FORMAT_TOTAL_TIME_RUNNING = 1 << 1;
const PERF_FORMAT_ID = 1 << 2;
const PERF_FORMAT_GROUP = 1 << 3;

// Various ioctls act on perf_event_open() file descriptors:
const PERF_EVENT_IOC_ID = linux.IOCTL.IOR('$', 7, u64);
const PERF_EVENT_IOC_RESET = linux.PERF.EVENT_IOC.RESET;
const PERF_EVENT_IOC_ENABLE = linux.PERF.EVENT_IOC.ENABLE;
const PERF_EVENT_IOC_DISABLE = linux.PERF.EVENT_IOC.DISABLE;

/// The hardware events supported by the kernel for performance monitoring.
/// These map directly to `perf_event_attr.config` values.
pub const Event = enum {
    cpu_cycles,
    instructions,
    cache_misses,
    branch_misses,
    bus_cycles,

    /// Converts the enum into the specific kernel configuration integer
    /// required by the `perf_event_open` syscall.
    pub fn toConfig(self: Event) u64 {
        return switch (self) {
            .cpu_cycles => @intFromEnum(linux.PERF.COUNT.HW.CPU_CYCLES),
            .instructions => @intFromEnum(linux.PERF.COUNT.HW.INSTRUCTIONS),
            .cache_misses => @intFromEnum(linux.PERF.COUNT.HW.CACHE_MISSES),
            .branch_misses => @intFromEnum(linux.PERF.COUNT.HW.BRANCH_MISSES),
            .bus_cycles => @intFromEnum(linux.PERF.COUNT.HW.BUS_CYCLES),
        };
    }
};

pub fn GroupReadOutputType(comptime events: []const Event) type {
    var field_names: [events.len][]const u8 = undefined;
    var field_types: [events.len]type = undefined;
    var field_attrs: [events.len]Type.StructField.Attributes = undefined;
    for (events, 0..) |event, index| {
        field_names[index] = @tagName(event);
        field_types[index] = u64;
        field_attrs[index] = .{
            .@"comptime" = false,
            .@"align" = @alignOf(u64),
            .default_value_ptr = null,
        };
    }
    return @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attrs,
    );
}

/// A type-safe wrapper for the Linux `perf_event_open` system call,
/// specifically configured for event grouping (`PERF_FORMAT_GROUP`).
///
/// `Group` leverages Zig's `comptime` features to generate a custom
/// `ReadOutputType` result type that strictly matches the requested `events`.
/// It manages the complexity of creating a group leader, attaching sibling
/// events, and handling the binary layout of the kernel's read buffer.
///
/// Notes:
/// * The `read()` method returns a struct with named fields corresponding
///   exactly to the input events (e.g. `.cpu_cycles`).
/// * The `read()` method automatically detects if the CPU was oversubscribed
///   and scales the counter values based on `time_enabled` and `time_running`.
///
/// References:
/// * man 2 perf_event_open
/// * man 1 perf-list
pub fn Group(comptime events: []const Event) type {
    if (events.len == 0) @compileError("perf.Group requires at least 1 event");

    const Error = error{
        /// Failed to open group via perf_event_open
        OpenGroupFailed,
        /// Failed to retrieve the ID of the event via IOCTL
        GetIdFailed,
        /// Failed to reset counters via IOCTL
        ResetGroupFailed,
        /// Failed to enable counters via IOCTL
        EnableGroupFailed,
        /// Failed to disable counters via IOCTL
        DisableGroupFailed,
        /// Failed to read data from the file descriptor
        ReadGroupFailed,
        /// Group already deinitialized
        BadGroup,
    };

    const Output = GroupReadOutputType(events);

    // Matches the binary layout of the buffer read from the group leader fd.
    // See `man perf_event_open` section "Reading results".
    // Corresponds to `struct read_format` when using:
    // PERF_FORMAT_GROUP | PERF_FORMAT_TOTAL_TIME_ENABLED |
    // PERF_FORMAT_TOTAL_TIME_RUNNING | PERF_FORMAT_ID
    const ReadFormatGroup = extern struct {
        /// The number of events in this group.
        nr: u64,
        /// Total time the event group was enabled.
        time_enabled: u64,
        /// Total time the event group was actually running.
        time_running: u64,
        /// Array of values matching the `nr` of events.
        values: [events.len]extern struct {
            value: u64,
            id: u64,
        },
    };

    return struct {
        const Self = @This();

        event_fds: [events.len]linux.fd_t = undefined,
        event_ids: [events.len]u64 = undefined,

        /// Initializes the performance monitoring group.
        ///
        /// This opens a file descriptor for every event in the `events` list.
        /// The first event becomes the group leader. All subsequent events
        /// are created as siblings pinned to the leader.
        ///
        /// The counters start in a disabled state. You must call `enable()`
        /// to begin counting.
        ///
        /// **Note:** The caller owns the returned group and must call `deinit`
        /// to close the file descriptors.
        pub fn init() Error!Self {
            var self = Self{};
            @memset(&self.event_fds, -1);

            // Leader
            var group_fd = @as(i32, -1);
            const event_config = events[0].toConfig();
            self.event_fds[0] = try perf_open_group(group_fd, event_config);
            self.event_ids[0] = try ioctl_get_id(self.event_fds[0]);
            group_fd = self.event_fds[0];

            // Siblings
            if (events.len > 1) {
                for (events[1..], 1..) |event, i| {
                    const config = event.toConfig();
                    self.event_fds[i] = try perf_open_group(group_fd, config);
                    self.event_ids[i] = try ioctl_get_id(self.event_fds[i]);
                }
            }
            return self;
        }

        /// Closes all file descriptors associated with this event group.
        /// This invalidates the group object.
        pub fn deinit(self: *Self) void {
            for (self.event_fds, 0..) |event_fd, index| {
                if (event_fd != -1) {
                    _ = linux.close(event_fd);
                }
                self.event_fds[index] = -1;
                self.event_ids[index] = 0;
            }
        }

        /// Resets and enables the event group. Counting begins immediately.
        pub fn enable(self: *Self) Error!void {
            const group_fd = self.event_fds[0];
            if (group_fd == -1) return error.BadGroup;
            try ioctl_reset_group(group_fd);
            try ioctl_enable_group(group_fd);
        }

        /// Disables the event group. Counting stops immediately.
        pub fn disable(self: *Self) Error!void {
            const group_fd = self.event_fds[0];
            if (group_fd == -1) return error.BadGroup;
            try ioctl_disable_group(group_fd);
        }

        /// Reads the current values from the kernel and maps them to the
        /// type-safe output struct.
        ///
        /// This performs the following operations:
        /// 1. Reads the `read_format` binary struct from the leader FD.
        /// 2. Checks `time_enabled` and `time_running` to detect if the CPU
        ///    was oversubscribed.
        /// 3. If multiplexing occurred (time_running < time_enabled), scales
        ///    the raw values: `val = raw_val * (time_enabled / time_running)`
        /// 4. Maps the kernel's event IDs back to the field names of the output
        ///    struct.
        pub fn read(self: *Self) Error!Output {
            var output: Output = std.mem.zeroes(Output);
            var data: ReadFormatGroup = undefined;

            const rc = linux.read(self.event_fds[0], @ptrCast(&data), @sizeOf(ReadFormatGroup));
            if (linux.errno(rc) != .SUCCESS) return error.ReadGroupFailed;

            // If time_running is 0, we can't scale, so return zeros.
            if (data.time_running == 0) return output;

            // Multiplexing scaling: scaled_value = value * (time_enabled / time_running)
            const scale_needed = data.time_running < data.time_enabled;
            const scale_factor = if (scale_needed)
                @as(f64, @floatFromInt(data.time_enabled)) / @as(f64, @floatFromInt(data.time_running))
            else
                1.0;

            for (data.values) |item| {
                var val = item.value;

                if (scale_needed) {
                    val = @as(u64, @intFromFloat(@as(f64, @floatFromInt(val)) * scale_factor));
                }

                // Map the kernel ID back to our event tags
                inline for (events, 0..) |tag, i| {
                    if (item.id == self.event_ids[i]) {
                        @field(output, @tagName(tag)) = val;
                    }
                }
            }

            return output;
        }

        ///////////////////////////////////////////////////////////////////////////////
        // perf & ioctl calls

        // Open new file descriptor for the specific event
        fn perf_open_group(group_fd: linux.fd_t, config: u64) Error!linux.fd_t {
            var attr = std.mem.zeroes(linux.perf_event_attr);
            attr.type = linux.PERF.TYPE.HARDWARE;
            attr.config = config;

            // Enable grouping and ID tracking
            attr.read_format = PERF_FORMAT_GROUP |
                PERF_FORMAT_TOTAL_TIME_ENABLED |
                PERF_FORMAT_TOTAL_TIME_RUNNING |
                PERF_FORMAT_ID;

            attr.flags.disabled = (group_fd == -1); // Only leader starts disabled
            attr.flags.inherit = true;
            attr.flags.exclude_kernel = true;
            attr.flags.exclude_hv = true;

            // ref: `man 2 perf_event_open`
            // pid=0 (current process), cpu=-1 (any cpu), flags=0
            const pid = 0;
            const cpu = -1;
            const flags = 0;

            const rc = linux.perf_event_open(&attr, pid, cpu, group_fd, flags);
            if (linux.errno(rc) != .SUCCESS) return error.OpenGroupFailed;
            return @intCast(rc);
        }

        // ref: `man 2 perf_event_open` then search for `PERF_EVENT_IOC_ID`
        fn ioctl_get_id(fd: linux.fd_t) Error!u64 {
            var id: u64 = 0;
            const rc = linux.ioctl(fd, PERF_EVENT_IOC_ID, @intFromPtr(&id));
            if (linux.errno(rc) != .SUCCESS) return error.GetIdFailed;
            return id;
        }

        // ref: `man 2 perf_event_open` then search for `PERF_EVENT_IOC_RESET`
        fn ioctl_reset_group(fd: linux.fd_t) Error!void {
            const rc = linux.ioctl(fd, PERF_EVENT_IOC_RESET, 0);
            if (linux.errno(rc) != .SUCCESS) return error.ResetGroupFailed;
        }

        // ref: `man 2 perf_event_open` then search for `PERF_EVENT_IOC_ENABLE`
        fn ioctl_enable_group(fd: linux.fd_t) Error!void {
            const rc = linux.ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);
            if (linux.errno(rc) != .SUCCESS) return error.EnableGroupFailed;
        }

        // ref: `man 2 perf_event_open` then search for `PERF_EVENT_IOC_DISABLE`
        fn ioctl_disable_group(fd: linux.fd_t) Error!void {
            const rc = linux.ioctl(fd, PERF_EVENT_IOC_DISABLE, 0);
            if (linux.errno(rc) != .SUCCESS) return error.DisableGroupFailed;
        }
    };
}
