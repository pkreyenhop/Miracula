const std = @import("std");

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

fn epochToDate(epoch_secs: u64) struct { day: u8, month: u8, year: u16 } {
    const secs = epoch_secs;
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    
    var days = secs / 86400;
    var year: u16 = 1970;
    while (true) {
        const is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
        const days_in_year = if (is_leap) @as(u32, 366) else 365;
        if (days >= days_in_year) {
            days -= days_in_year;
            year += 1;
        } else {
            break;
        }
    }
    
    const is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    var month: u8 = 0;
    while (month < 12) : (month += 1) {
        var dim = days_in_month[month];
        if (month == 1 and is_leap) dim = 29;
        if (days >= dim) {
            days -= dim;
        } else {
            break;
        }
    }
    
    return .{
        .day = @intCast(days + 1),
        .month = month,
        .year = year,
    };
}

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

    const seconds = @as(u64, @intCast(@divTrunc(stat.mtime.nanoseconds, std.time.ns_per_s)));
    const date = epochToDate(seconds);

    const month_index: usize = date.month;
    if (month_index >= months.len) {
        reportBadFile(path);
        return;
    }

    var out_buf: [128]u8 = undefined;
    const out_str = try std.fmt.bufPrint(&out_buf, "{d} {s} {d:4}\n", .{ date.day, months[month_index], date.year });
    _ = std.posix.system.write(1, out_str.ptr, out_str.len);
}

fn reportBadFile(path: []const u8) void {
    std.debug.print("fdate: bad file \"{s}\"\n", .{path});
}
