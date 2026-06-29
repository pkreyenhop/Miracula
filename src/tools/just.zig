//! just.zig — the standalone `just` text-justification filter: reflow stdin to a
//! target column width (default 72), the paragraph formatter used by the Miranda
//! online manual. A small companion program built as its own executable.

const std = @import("std");

const default_width = 72;
const max_width = 2400;
const threshold = 7;
const max_input = 16 * 1024 * 1024;

pub fn main(ctx: std.process.Init) !void {
    const allocator = ctx.gpa;

    var width: usize = readWidthFile(ctx) orelse default_width;
    var tolerance: usize = 3;

    const args = try ctx.minimal.args.toSlice(allocator);
    // defer allocator.free(args); // toSlice returns an owned slice of owned strings

    var first_file: usize = 1;
    while (first_file < args.len and std.mem.startsWith(u8, args[first_file], "-")) {
        const arg = args[first_file];
        if (arg.len >= 3 and arg[1] == 't' and std.ascii.isDigit(arg[2])) {
            tolerance = try std.fmt.parseUnsigned(usize, arg[2..], 10);
        } else if (arg.len >= 2 and (std.ascii.isDigit(arg[1]) or (arg[1] == '-' and arg.len >= 3 and std.ascii.isDigit(arg[2])))) {
            const parsed = try std.fmt.parseInt(isize, arg[1..], 10);
            if (parsed < 0) {
                width = @intCast(-parsed);
                tolerance = 0;
            } else {
                width = @intCast(parsed);
            }
        } else {
            std.debug.print("just: unknown flag {s}\n", .{arg});
            std.process.exit(1);
        }
        first_file += 1;
    }

    if (width == 0) {
        width = max_width;
        tolerance = 0;
    }
    if (width < 6 or width > max_width) {
        std.debug.print("just: silly width {d}\n(legal widths are in the range 6 to {d})\n", .{ width, max_width });
        std.process.exit(1);
    }

    const stdout = std.Io.File.stdout();
    var out_w = stdout.writer(ctx.io, &[_]u8{});
    if (first_file == args.len) {
        const stdin = std.Io.File.stdin();
        var r = stdin.reader(ctx.io, &[_]u8{});
        const input = try r.interface.allocRemaining(allocator, .limited(max_input));
        defer allocator.free(input);
        const output = try formatText(allocator, input, width, tolerance);
        defer allocator.free(output);
        try out_w.interface.writeAll(output);
    } else {
        for (args[first_file..]) |path| {
            const input = std.Io.Dir.cwd().readFileAlloc(ctx.io, path, allocator, .limited(max_input)) catch {
                std.debug.print("just: cannot open {s}\n", .{path});
                break;
            };
            defer allocator.free(input);
            const output = try formatText(allocator, input, width, tolerance);
            defer allocator.free(output);
            try out_w.interface.writeAll(output);
        }
    }
}

fn readWidthFile(ctx: std.process.Init) ?usize {
    var file = std.Io.Dir.cwd().openFile(ctx.io, ".justwidth", .{}) catch return null;
    defer file.close(ctx.io);
    var buffer: [64]u8 = undefined;
    var r = file.reader(ctx.io, &buffer);
    const len = r.interface.readSliceShort(&buffer) catch return null;
    const text = std.mem.trim(u8, buffer[0..len], " \t\r\n");
    return std.fmt.parseUnsigned(usize, text, 10) catch null;
}

fn formatText(allocator: std.mem.Allocator, input: []const u8, width: usize, tolerance: usize) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var paragraph: std.ArrayList(u8) = .empty;
    defer paragraph.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < input.len) {
        const end = std.mem.findScalarPos(u8, input, cursor, '\n') orelse input.len;
        var line = input[cursor..end];
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }

        if (line.len == 0 or line[0] == '>' or indent(line) > threshold) {
            try flushParagraph(allocator, &output, &paragraph, width, tolerance);
            try output.appendSlice(allocator, line);
            try output.append(allocator, '\n');
        } else {
            const squeezed = try squeezeLine(allocator, line);
            defer allocator.free(squeezed);
            if (paragraph.items.len > 0 and squeezed.len > 0) {
                try paragraph.append(allocator, ' ');
                if (isTerminator(paragraph.items[paragraph.items.len - 2])) {
                    try paragraph.append(allocator, ' ');
                }
            }
            try paragraph.appendSlice(allocator, squeezed);
        }

        if (end == input.len) break;
        cursor = end + 1;
    }
    try flushParagraph(allocator, &output, &paragraph, width, tolerance);
    return output.toOwnedSlice(allocator);
}

fn flushParagraph(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    paragraph: *std.ArrayList(u8),
    width: usize,
    tolerance: usize,
) !void {
    if (paragraph.items.len == 0) return;
    try formatParagraph(allocator, output, paragraph.items, width, tolerance);
    paragraph.clearRetainingCapacity();
}

fn formatParagraph(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    paragraph: []const u8,
    width: usize,
    tolerance: usize,
) !void {
    var words: std.ArrayList([]const u8) = .empty;
    defer words.deinit(allocator);
    var it = std.mem.tokenizeAny(u8, paragraph, " \t");
    while (it.next()) |word| {
        try words.append(allocator, word);
    }
    if (words.items.len == 0) return;

    var start: usize = 0;
    while (start < words.items.len) {
        var end = start;
        var line_len: usize = 0;
        while (end < words.items.len) {
            const next_len = line_len + words.items[end].len + if (end > start) @as(usize, 1) else 0;
            if (end > start and next_len > width) break;
            line_len = next_len;
            end += 1;
        }
        const last = end == words.items.len;
        try emitLine(allocator, output, words.items[start..end], width, tolerance, !last);
        start = end;
    }
}

fn emitLine(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    words: []const []const u8,
    width: usize,
    tolerance: usize,
    justify: bool,
) !void {
    if (words.len == 0) return;
    var words_len: usize = 0;
    for (words) |word| words_len += word.len;
    const gaps = words.len - 1;
    const min_len = words_len + gaps;
    const extra = if (width > min_len) width - min_len else 0;
    const extra_per_gap = if (gaps > 0) extra / gaps else 0;
    const remainder = if (gaps > 0) extra % gaps else 0;
    const can_justify = justify and gaps > 0 and extra_per_gap + @intFromBool(remainder > 0) <= tolerance;

    for (words, 0..) |word, i| {
        try output.appendSlice(allocator, word);
        if (i + 1 < words.len) {
            var spaces: usize = 1;
            if (can_justify) {
                spaces += extra_per_gap + @intFromBool(i < remainder);
            }
            try appendSpaces(allocator, output, spaces);
        }
    }
    try output.append(allocator, '\n');
}

fn appendSpaces(allocator: std.mem.Allocator, output: *std.ArrayList(u8), count: usize) !void {
    for (0..count) |_| {
        try output.append(allocator, ' ');
    }
}

fn squeezeLine(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var cursor = indent(line);
    var previous_was_space = false;
    while (cursor < line.len) : (cursor += 1) {
        var ch = line[cursor];
        if (ch == '\t') ch = ' ';
        if (ch == ' ') {
            if (!previous_was_space and out.items.len > 0) {
                try out.append(allocator, ' ');
            }
            previous_was_space = true;
        } else {
            try out.append(allocator, ch);
            previous_was_space = false;
        }
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') {
        _ = out.pop();
    }
    return out.toOwnedSlice(allocator);
}

fn indent(line: []const u8) usize {
    var count: usize = 0;
    for (line) |ch| {
        if (ch == ' ') {
            count += 1;
        } else if (ch == '\t') {
            count = 8 * (1 + count / 8);
        } else {
            break;
        }
    }
    return count;
}

fn isTerminator(ch: u8) bool {
    return ch == '.' or ch == '?' or ch == '!';
}

test "wraps and justifies ordinary paragraphs" {
    const allocator = std.testing.allocator;
    const output = try formatText(allocator, "alpha beta gamma delta\n", 16, 3);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("alpha beta gamma\ndelta\n", output);
}

test "preserves blank quoted and deeply indented lines" {
    const allocator = std.testing.allocator;
    const output = try formatText(allocator, "alpha beta\n\n> quote\n        code\nnext line\n", 20, 3);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("alpha beta\n\n> quote\n        code\nnext line\n", output);
}
