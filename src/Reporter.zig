const std = @import("std");
const Writer = std.Io.Writer;
const tty = std.Io.tty;

const Metrics = @import("Metrics.zig");

pub const Options = struct {
    metrics: []const Metrics,
    /// The index in 'metrics' to use as the baseline for comparison (e.g 1.00x).
    /// If null, no comparison column is shown.
    baseline_index: ?usize = null,
};

/// Prints a formatted summary table to stdout.
pub fn report(options: Options) !void {
    var buffer: [0x2000]u8 = undefined;
    var w: Writer = .fixed(&buffer);
    try writeReport(&w, options);
    std.debug.print("{s}", .{w.buffered()});
}

/// Writes the formatted report to a specific writer
pub fn writeReport(writer: *Writer, options: Options) !void {
    if (options.metrics.len == 0) return;

    try writer.print("Benchmark Summary: {d} benchmarks run\n", .{options.metrics.len});

    var max_name_len: usize = 0;
    for (options.metrics) |m| max_name_len = @max(max_name_len, m.name.len);

    for (options.metrics, 0..) |m, i| {
        const is_last_item = i == options.metrics.len - 1;

        // --- ROW 1: High Level (Name | Time | Speed | Comparison) ---
        const tree_char = if (is_last_item) "└─ " else "├─ ";
        try writeColor(writer, .bright_black, tree_char);
        try writeColor(writer, .cyan, m.name);
        // try writer.print("{s}{s}", .{ tree_char, m.name });

        // Align name
        const padding = max_name_len - m.name.len + 2;
        _ = try writer.splatByte(' ', padding);

        try fmtTime(writer, m.median_ns);
        try writer.writeAll("   ");

        if (m.mb_sec > 0.001) {
            try fmtBandwidth(writer, m.mb_sec);
        } else {
            try fmtOps(writer, m.ops_sec);
        }

        // Comparison (On the first line now)
        if (options.baseline_index) |base_idx| {
            try writer.writeAll("   ");
            if (i == base_idx) {
                try writeColor(writer, .blue, "[baseline]");
            } else if (base_idx < options.metrics.len) {
                const base = options.metrics[base_idx];
                const base_f = base.median_ns;
                const curr_f = m.median_ns;

                if (curr_f > 0 and base_f > 0) {
                    if (curr_f < base_f) {
                        try writer.writeAll("\x1b[32m"); // Green manually to mix with print
                        try writer.print("{d:.2}x faster", .{base_f / curr_f});
                        try writer.writeAll("\x1b[0m");
                    } else {
                        try writer.writeAll("\x1b[31m");
                        try writer.print("{d:.2}x slower", .{curr_f / base_f});
                        try writer.writeAll("\x1b[0m");
                    }
                } else {
                    try writer.writeAll("-");
                }
            }
        }
        try writer.writeByte('\n');

        // Only printed if we have hardware stats
        if (m.cycles) |cycles| {
            const sub_tree_prefix = if (is_last_item) "   └─ " else "│  └─ ";
            try writer.writeAll(sub_tree_prefix);
            try writeColor(writer, .dim, "cycles: ");
            try fmtInt(writer, cycles);
        }

        if (m.instructions) |instructions| {
            try writer.writeAll("\t");
            try writeColor(writer, .dim, "instructions: ");
            try fmtInt(writer, instructions);
        }

        if (m.ipc) |ipc| {
            try writer.writeAll("\t");
            try writeColor(writer, .dim, "ipc: ");
            try writer.print("{d:.2}", .{ipc});
        }

        if (m.cache_misses) |cache_missess| {
            try writer.writeAll("\t");
            try writeColor(writer, .dim, "miss: ");
            try fmtInt(writer, cache_missess);

            try writer.writeByte('\n');
        }
    }
}

fn writeColor(writer: *Writer, color: tty.Color, text: []const u8) !void {
    const config = tty.Config.detect(std.fs.File.stdout());
    if (config != .no_color) {
        switch (color) {
            .reset => try writer.writeAll("\x1b[0m"),
            .red => try writer.writeAll("\x1b[31m"),
            .green => try writer.writeAll("\x1b[32m"),
            .blue => try writer.writeAll("\x1b[34m"),
            .cyan => try writer.writeAll("\x1b[36m"),
            .dim => try writer.writeAll("\x1b[2m"),
            .black => try writer.writeAll("\x1b[90m"),
            else => try writer.writeAll(""),
        }
    }
    try writer.writeAll(text);
    if (config != .no_color) try writer.writeAll("\x1b[0m");
}

////////////////////////////////////////////////////////////////////////////////
// formatters

fn fmtInt(writer: *Writer, val: f64) !void {
    if (val < 1000) {
        try writer.print("{d:.0}", .{val});
    } else if (val < 1_000_000) {
        try writer.print("{d:.1}k", .{val / 1000.0});
    } else if (val < 1_000_000_000) {
        try writer.print("{d:.1}M", .{val / 1_000_000.0});
    } else {
        try writer.print("{d:.1}G", .{val / 1_000_000_000.0});
    }
}

fn fmtTime(writer: *Writer, ns: f64) !void {
    var buf: [64]u8 = undefined;
    var slice: []u8 = undefined;

    if (ns < 1000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}ns", .{ns});
    } else if (ns < 1_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}us", .{ns / 1000.0});
    } else if (ns < 1_000_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}ms", .{ns / 1_000_000.0});
    } else {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}s", .{ns / 1_000_000_000.0});
    }
    try padLeft(writer, slice, 9);
}

fn fmtOps(writer: *Writer, ops: f64) !void {
    var buf: [64]u8 = undefined;
    var slice: []u8 = undefined;

    if (ops < 1000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.0}/s", .{ops});
    } else if (ops < 1_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}K/s", .{ops / 1000.0});
    } else if (ops < 1_000_000_000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}M/s", .{ops / 1_000_000.0});
    } else {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}G/s", .{ops / 1_000_000_000.0});
    }
    try padLeft(writer, slice, 11);
}

fn fmtBandwidth(writer: *Writer, mb: f64) !void {
    var buf: [64]u8 = undefined;
    var slice: []u8 = undefined;

    if (mb >= 1000) {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}GB/s", .{mb / 1000.0});
    } else {
        slice = try std.fmt.bufPrint(&buf, "{d:.2}MB/s", .{mb});
    }
    try padLeft(writer, slice, 11);
}

// Pads with spaces on the left (for numbers)
fn padLeft(writer: *Writer, text: []const u8, width: usize) !void {
    if (text.len < width) {
        _ = try writer.splatByte(' ', width - text.len);
    }
    try writer.writeAll(text);
}

// Pads with spaces on the right (for text/comparisons)
fn padRight(writer: *Writer, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    if (text.len < width) {
        _ = try writer.splatByte(' ', width - text.len);
    }
}
