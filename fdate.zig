const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
    @cInclude("stdio.h");
});

const months = [_][*:0]const u8{
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

pub fn main(ctx: std.process.Init) !void {
    var input: [200]u8 = undefined;
    const stdin = std.Io.File.stdin();
    var r = stdin.reader(ctx.io, &input);
    const bytes_read = try r.interface.readSliceShort(&input);
    const text = std.mem.trim(u8, input[0..bytes_read], " \t\r\n");
    const token_end = std.mem.indexOfAny(u8, text, " \t\r\n") orelse text.len;
    const path = text[0..token_end];

    if (path.len == 0) {
        reportBadFile("");
        return;
    }

    const stat = std.Io.Dir.cwd().statFile(ctx.io, path, .{}) catch {
        reportBadFile(path);
        return;
    };

    var seconds: c.time_t = @intCast(@divTrunc(stat.mtime.nanoseconds, std.time.ns_per_s));
    const local_time = c.localtime(&seconds);
    if (local_time == null) {
        reportBadFile(path);
        return;
    }

    const time = local_time.*;
    const month_index: usize = @intCast(time.tm_mon);
    if (month_index >= months.len) {
        reportBadFile(path);
        return;
    }

    _ = c.printf("%d %s %4d\n", time.tm_mday, months[month_index], time.tm_year + 1900);
}

fn reportBadFile(path: []const u8) void {
    std.debug.print("fdate: bad file \"{s}\"\n", .{path});
}
