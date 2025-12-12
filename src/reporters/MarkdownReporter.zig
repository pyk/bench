const std = @import("std");
const Writer = std.Io.Writer;
const Metrics = @import("../Metrics.zig");

pub const Options = struct {
    metrics: []const Metrics,
    baseline_index: ?usize = null,
};

const Column = struct {
    title: []const u8,
    width: usize,
    align_right: bool,
    active: bool,
};

pub fn print(options: Options) !void {
    var buffer: [64 * 1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try write(fbs.writer(), options);
    std.debug.print("{s}", .{fbs.getWritten()});
}

pub fn write(w: *Writer, options: Options) !void {
    if (options.metrics.len == 0) return;

    // Initialize columns with Header names and default visibility
    var col_name = Column{ .title = "Benchmark", .width = 0, .align_right = false, .active = true };
    var col_time = Column{ .title = "Time", .width = 0, .align_right = true, .active = true };
    var col_iter = Column{ .title = "Iterations", .width = 0, .align_right = true, .active = true };

    var col_bytes = Column{ .title = "Bytes/s", .width = 0, .align_right = true, .active = false };
    var col_ops = Column{ .title = "Ops/s", .width = 0, .align_right = true, .active = false };
    var col_cycles = Column{ .title = "Cycles", .width = 0, .align_right = true, .active = false };
    var col_instr = Column{ .title = "Instructions", .width = 0, .align_right = true, .active = false };
    var col_ipc = Column{ .title = "IPC", .width = 0, .align_right = true, .active = false };
    var col_miss = Column{ .title = "Cache Misses", .width = 0, .align_right = true, .active = false };

    // We must format every number to a temporary buffer to know its length.
    var buf: [64]u8 = undefined;

    // Check headers first
    col_name.width = col_name.title.len;
    col_time.width = col_time.title.len;
    // col_cpu.width = col_cpu.title.len;
    col_iter.width = col_iter.title.len;
    col_bytes.width = col_bytes.title.len;
    col_ops.width = col_ops.title.len;
    col_cycles.width = col_cycles.title.len;
    col_instr.width = col_instr.title.len;
    col_ipc.width = col_ipc.title.len;
    col_miss.width = col_miss.title.len;

    for (options.metrics) |m| {
        // Name: +2 for backticks
        col_name.width = @max(col_name.width, m.name.len + 2);

        // Time
        const s_time = try fmtTime(&buf, m.mean_ns);
        col_time.width = @max(col_time.width, s_time.len);

        // Iterations
        const s_iter = try std.fmt.bufPrint(&buf, "{d}", .{m.samples});
        col_iter.width = @max(col_iter.width, s_iter.len);

        // Optional Columns (Enable & Measure)
        if (m.mb_sec > 0.001) {
            col_bytes.active = true;
            const s = try fmtBytes(&buf, m.mb_sec);
            col_bytes.width = @max(col_bytes.width, s.len);
        }
        if (m.ops_sec > 0.001 and m.mb_sec <= 0.001) {
            col_ops.active = true;
            const s_val = try fmtMetric(&buf, m.ops_sec);
            // We append "/s" in the final output, so add 2 to length
            col_ops.width = @max(col_ops.width, s_val.len + 2);
        }
        if (m.cycles) |v| {
            col_cycles.active = true;
            const s = try fmtMetric(&buf, v);
            col_cycles.width = @max(col_cycles.width, s.len);
        }
        if (m.instructions) |v| {
            col_instr.active = true;
            const s = try fmtMetric(&buf, v);
            col_instr.width = @max(col_instr.width, s.len);
        }
        if (m.ipc) |v| {
            col_ipc.active = true;
            const s = try std.fmt.bufPrint(&buf, "{d:.2}", .{v});
            col_ipc.width = @max(col_ipc.width, s.len);
        }
        if (m.cache_misses) |v| {
            col_miss.active = true;
            const s = try fmtMetric(&buf, v);
            col_miss.width = @max(col_miss.width, s.len);
        }
    }

    // Header Row
    try w.writeAll("| ");
    try printCell(w, col_name.title, col_name);
    try printCell(w, col_time.title, col_time);
    try printCell(w, col_iter.title, col_iter);
    if (col_bytes.active) try printCell(w, col_bytes.title, col_bytes);
    if (col_ops.active) try printCell(w, col_ops.title, col_ops);
    if (col_cycles.active) try printCell(w, col_cycles.title, col_cycles);
    if (col_instr.active) try printCell(w, col_instr.title, col_instr);
    if (col_ipc.active) try printCell(w, col_ipc.title, col_ipc);
    if (col_miss.active) try printCell(w, col_miss.title, col_miss);
    try w.writeAll("\n");

    // Separator Row
    try w.writeAll("| ");
    try printDivider(w, col_name);
    try printDivider(w, col_time);
    try printDivider(w, col_iter);
    if (col_bytes.active) try printDivider(w, col_bytes);
    if (col_ops.active) try printDivider(w, col_ops);
    if (col_cycles.active) try printDivider(w, col_cycles);
    if (col_instr.active) try printDivider(w, col_instr);
    if (col_ipc.active) try printDivider(w, col_ipc);
    if (col_miss.active) try printDivider(w, col_miss);
    try w.writeAll("\n");

    // Data Rows
    for (options.metrics) |m| {
        try w.writeAll("| ");

        // Name
        const name_s = try std.fmt.bufPrint(&buf, "`{s}`", .{m.name});
        try printCell(w, name_s, col_name);

        // Time/CPU
        try printCell(w, try fmtTime(&buf, m.mean_ns), col_time);

        // Iterations
        const iter_s = try std.fmt.bufPrint(&buf, "{d}", .{m.iterations});
        try printCell(w, iter_s, col_iter);

        // Optional
        if (col_bytes.active) {
            if (m.mb_sec > 0.001) try printCell(w, try fmtBytes(&buf, m.mb_sec), col_bytes) else try printCell(w, "-", col_bytes);
        }
        if (col_ops.active) {
            if (m.ops_sec > 0.001) {
                // Must manually construct the string with suffix to match width measurement
                const val = try fmtMetric(&buf, m.ops_sec);
                var buf2: [64]u8 = undefined;
                const final = try std.fmt.bufPrint(&buf2, "{s}/s", .{val});
                try printCell(w, final, col_ops);
            } else try printCell(w, "-", col_ops);
        }
        if (col_cycles.active) {
            if (m.cycles) |v| try printCell(w, try fmtMetric(&buf, v), col_cycles) else try printCell(w, "-", col_cycles);
        }
        if (col_instr.active) {
            if (m.instructions) |v| try printCell(w, try fmtMetric(&buf, v), col_instr) else try printCell(w, "-", col_instr);
        }
        if (col_ipc.active) {
            if (m.ipc) |v| {
                const s = try std.fmt.bufPrint(&buf, "{d:.2}", .{v});
                try printCell(w, s, col_ipc);
            } else try printCell(w, "-", col_ipc);
        }
        if (col_miss.active) {
            if (m.cache_misses) |v| try printCell(w, try fmtMetric(&buf, v), col_miss) else try printCell(w, "-", col_miss);
        }

        try w.writeAll("\n");
    }
}

fn printCell(w: *Writer, text: []const u8, col: Column) !void {
    const pad_len = if (col.width > text.len) col.width - text.len else 0;

    if (col.align_right) {
        _ = try w.splatByte(' ', pad_len);
        try w.writeAll(text);
    } else {
        try w.writeAll(text);
        _ = try w.splatByte(' ', pad_len);
    }
    try w.writeAll(" | ");
}

fn printDivider(w: *Writer, col: Column) !void {
    if (col.align_right) {
        // "-----------:"
        _ = try w.splatByte('-', col.width - 1);
        try w.writeAll(":");
    } else {
        // ":-----------"
        try w.writeAll(":");
        _ = try w.splatByte('-', col.width - 1);
    }
    try w.writeAll(" | ");
}

fn fmtTime(buf: []u8, ns: f64) ![]const u8 {
    if (ns < 1_000) return std.fmt.bufPrint(buf, "{d:.2} ns", .{ns});
    if (ns < 1_000_000) return std.fmt.bufPrint(buf, "{d:.2} us", .{ns / 1_000.0});
    if (ns < 1_000_000_000) return std.fmt.bufPrint(buf, "{d:.2} ms", .{ns / 1_000_000.0});
    return std.fmt.bufPrint(buf, "{d:.2} s", .{ns / 1_000_000_000.0});
}

fn fmtBytes(buf: []u8, mb: f64) ![]const u8 {
    if (mb > 1000) return std.fmt.bufPrint(buf, "{d:.2}GB/s", .{mb / 1024.0});
    return std.fmt.bufPrint(buf, "{d:.2}MB/s", .{mb});
}

fn fmtMetric(buf: []u8, val: f64) ![]const u8 {
    if (val < 1_000) return std.fmt.bufPrint(buf, "{d:.1}", .{val});
    if (val < 1_000_000) return std.fmt.bufPrint(buf, "{d:.1}k", .{val / 1_000.0});
    if (val < 1_000_000_000) return std.fmt.bufPrint(buf, "{d:.1}M", .{val / 1_000_000.0});
    return std.fmt.bufPrint(buf, "{d:.1}G", .{val / 1_000_000_000.0});
}
