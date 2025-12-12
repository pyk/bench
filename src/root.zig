const builtin = @import("builtin");

pub const Metrics = @import("Metrics.zig");
pub const perf = @import("perf.zig");
pub const Runner = @import("Runner.zig");
pub const Reporter = @import("Reporter.zig");

pub const Options = Runner.Options;
pub const run = Runner.run;
pub const report = Reporter.report;

test {
    if (builtin.os.tag == .linux) {
        _ = @import("perf.test.zig");
    }
    _ = @import("Runner.test.zig");
    _ = @import("Reporter.test.zig");
    _ = @import("reporters/MarkdownReporter.test.zig");
}
