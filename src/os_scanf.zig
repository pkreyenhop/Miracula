//! os_scanf.zig — the hand-rolled C `scanf`/`fscanf` family, split out of os.zig
//! for the Go port's <1000-line file ratchet (docs/GO_PORT_PLAN.md P4). Part of
//! the FFI floor (`os.zig` re-exports `sscanf`/`fscanf`); one-way os -> os_scanf.
//! Per GO_ANYTYPE_INVENTORY these are slated for deletion in the Go port
//! (replaced by fmt.Sscanf/fmt.Fscanf), so they live isolated here.

const std = @import("std");
const word_mod = @import("graph/word.zig");
const Stream = word_mod.Stream;
const Word = word_mod.Word;
const getc = word_mod.getc;
const ungetc = word_mod.ungetc;

// Scanning implementations
fn scanVal(str: []const u8, s_idx: *usize, spec: u8, width: ?usize, ptr: anytype) bool {
    const PtrType = @TypeOf(ptr);
    const ptr_info = @typeInfo(PtrType).pointer;
    const ChildType = ptr_info.child;
    const is_int_child = comptime @typeInfo(ChildType) == .int;
    const is_float_child = comptime @typeInfo(ChildType) == .float;
    const is_array_child = comptime @typeInfo(ChildType) == .array;
    const is_many_ptr = comptime ptr_info.size == .many or ptr_info.size == .c;

    switch (spec) {
        'c' => {
            if (s_idx.* >= str.len) return false;
            if (comptime is_int_child) {
                ptr.* = @intCast(str[s_idx.*]);
            } else {
                return false;
            }
            s_idx.* += 1;
            return true;
        },
        's' => {
            const start = s_idx.*;
            var end = start;
            const limit = if (width) |w| start + w else str.len;
            while (end < str.len and end < limit and !std.ascii.isWhitespace(str[end])) {
                end += 1;
            }
            if (end == start) return false;
            const scanned = str[start..end];
            if (comptime is_array_child) {
                const arr_len = @typeInfo(ChildType).array.len;
                if (scanned.len >= arr_len) return false;
                @memcpy(ptr[0..scanned.len], scanned);
                ptr[scanned.len] = 0;
            } else if (comptime is_many_ptr) {
                const buf: [*]u8 = @ptrCast(ptr);
                @memcpy(buf[0..scanned.len], scanned);
                buf[scanned.len] = 0;
            } else {
                return false;
            }
            s_idx.* = end;
            return true;
        },
        'd', 'i' => {
            if (comptime !is_int_child) return false;
            const start = s_idx.*;
            var end = start;
            if (end < str.len and (str[end] == '-' or str[end] == '+')) end += 1;
            while (end < str.len and str[end] >= '0' and str[end] <= '9') end += 1;
            if (end == start or (end == start + 1 and (str[start] == '-' or str[start] == '+'))) return false;
            const val = std.fmt.parseInt(ChildType, str[start..end], 10) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        'u' => {
            if (comptime !is_int_child) return false;
            const start = s_idx.*;
            var end = start;
            while (end < str.len and str[end] >= '0' and str[end] <= '9') end += 1;
            if (end == start) return false;
            const val = std.fmt.parseInt(ChildType, str[start..end], 10) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        'x' => {
            if (comptime !is_int_child) return false;
            const start = s_idx.*;
            var end = start;
            if (end + 1 < str.len and str[end] == '0' and (str[end + 1] == 'x' or str[end + 1] == 'X')) end += 2;
            const hex_start = end;
            while (end < str.len and ((str[end] >= '0' and str[end] <= '9') or
                (str[end] >= 'a' and str[end] <= 'f') or (str[end] >= 'A' and str[end] <= 'F'))) end += 1;
            if (end == hex_start) return false;
            const val = std.fmt.parseInt(ChildType, str[hex_start..end], 16) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        'f', 'g', 'e' => {
            if (comptime !is_float_child) return false;
            const start = s_idx.*;
            var end = start;
            if (end < str.len and (str[end] == '-' or str[end] == '+')) end += 1;
            var has_dot = false;
            while (end < str.len) {
                const sc = str[end];
                if (sc >= '0' and sc <= '9') {
                    end += 1;
                } else if (sc == '.' and !has_dot) {
                    has_dot = true;
                    end += 1;
                } else {
                    break;
                }
            }
            if (end == start) return false;
            const val = std.fmt.parseFloat(ChildType, str[start..end]) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        else => return false,
    }
}

pub fn sscanf(buf: ?*const anyopaque, format: [*:0]const u8, args: anytype) c_int {
    if (buf == null) return -1;
    const str = std.mem.span(@as([*:0]const u8, @ptrCast(buf.?)));

    const fmt = std.mem.span(format);
    const ArgsType = @TypeOf(args);
    const fields = std.meta.fields(ArgsType);

    var s_idx: usize = 0;
    var f_idx: usize = 0;
    var arg_idx: usize = 0;
    var parsed_count: c_int = 0;

    while (f_idx < fmt.len) {
        if (fmt[f_idx] == '%') {
            f_idx += 1;
            if (f_idx >= fmt.len) break;
            if (fmt[f_idx] == '%') {
                if (s_idx >= str.len or str[s_idx] != '%') return parsed_count;
                s_idx += 1;
                f_idx += 1;
                continue;
            }

            var suppress = false;
            if (fmt[f_idx] == '*') {
                suppress = true;
                f_idx += 1;
            }

            var width: ?usize = null;
            var w_val: usize = 0;
            var has_w = false;
            while (f_idx < fmt.len and fmt[f_idx] >= '0' and fmt[f_idx] <= '9') {
                w_val = w_val * 10 + (fmt[f_idx] - '0');
                has_w = true;
                f_idx += 1;
            }
            if (has_w) width = w_val;

            while (f_idx < fmt.len and (fmt[f_idx] == 'l' or fmt[f_idx] == 'h')) {
                f_idx += 1;
            }

            if (f_idx >= fmt.len) break;
            const spec = fmt[f_idx];
            f_idx += 1;

            if (spec != 'c') {
                while (s_idx < str.len and std.ascii.isWhitespace(str[s_idx])) {
                    s_idx += 1;
                }
            }

            if (s_idx >= str.len) {
                if (parsed_count == 0) return -1;
                return parsed_count;
            }

            if (suppress) {
                if (spec == 'c') {
                    s_idx += 1;
                } else {
                    while (s_idx < str.len and !std.ascii.isWhitespace(str[s_idx])) {
                        s_idx += 1;
                    }
                }
                continue;
            }

            if (arg_idx >= fields.len) return parsed_count;

            const success = inline for (fields, 0..) |field, idx| {
                if (idx == arg_idx) {
                    const ptr = @field(args, field.name);
                    break scanVal(str, &s_idx, spec, width, ptr);
                }
            } else false;

            if (!success) return parsed_count;
            parsed_count += 1;
            arg_idx += 1;
        } else if (std.ascii.isWhitespace(fmt[f_idx])) {
            f_idx += 1;
            while (s_idx < str.len and std.ascii.isWhitespace(str[s_idx])) {
                s_idx += 1;
            }
        } else {
            if (s_idx >= str.len or str[s_idx] != fmt[f_idx]) {
                return parsed_count;
            }
            s_idx += 1;
            f_idx += 1;
        }
    }

    return parsed_count;
}

fn scanValFromFile(f: *Stream, spec: u8, width: ?usize, ptr: anytype) bool {
    const PtrType = @TypeOf(ptr);
    const ptr_info = @typeInfo(PtrType).pointer;
    const ChildType = ptr_info.child;
    const is_int_child = comptime @typeInfo(ChildType) == .int;
    const is_float_child = comptime @typeInfo(ChildType) == .float;
    const is_array_child = comptime @typeInfo(ChildType) == .array;
    const is_many_ptr = comptime ptr_info.size == .many or ptr_info.size == .c;

    switch (spec) {
        'c' => {
            const ch = getc(f);
            if (ch == -1) return false;
            if (comptime is_int_child) {
                ptr.* = @intCast(ch);
            } else {
                return false;
            }
            return true;
        },
        's' => {
            var buf: [1024]u8 = undefined;
            var len: usize = 0;
            const limit = if (width) |w| w else buf.len;
            while (len < limit) {
                const ch = getc(f);
                if (ch == -1) break;
                if (std.ascii.isWhitespace(@intCast(ch))) {
                    _ = ungetc(ch, f);
                    break;
                }
                buf[len] = @intCast(ch);
                len += 1;
            }
            if (len == 0) return false;
            const scanned = buf[0..len];
            if (comptime is_array_child) {
                const arr_len = @typeInfo(ChildType).array.len;
                if (scanned.len >= arr_len) return false;
                @memcpy(ptr[0..scanned.len], scanned);
                ptr[scanned.len] = 0;
            } else if (comptime is_many_ptr) {
                const b: [*]u8 = @ptrCast(ptr);
                @memcpy(b[0..scanned.len], scanned);
                b[scanned.len] = 0;
            } else {
                return false;
            }
            return true;
        },
        'd', 'i' => {
            if (comptime !is_int_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const ch_first = getc(f);
            if (ch_first == -1) return false;
            if (ch_first == '-' or ch_first == '+') {
                buf[0] = @intCast(ch_first);
                len = 1;
            } else {
                _ = ungetc(ch_first, f);
            }
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if (ch >= '0' and ch <= '9') {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0 or (len == 1 and (buf[0] == '-' or buf[0] == '+'))) return false;
            const val = std.fmt.parseInt(ChildType, buf[0..len], 10) catch return false;
            ptr.* = val;
            return true;
        },
        'u' => {
            if (comptime !is_int_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if (ch >= '0' and ch <= '9') {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0) return false;
            const val = std.fmt.parseInt(ChildType, buf[0..len], 10) catch return false;
            ptr.* = val;
            return true;
        },
        'x' => {
            if (comptime !is_int_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const c1 = getc(f);
            if (c1 == '0') {
                const c2 = getc(f);
                if (c2 != 'x' and c2 != 'X') {
                    if (c2 != -1) _ = ungetc(c2, f);
                    _ = ungetc(c1, f);
                }
            } else {
                if (c1 != -1) _ = ungetc(c1, f);
            }
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if ((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F')) {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0) return false;
            const val = std.fmt.parseInt(ChildType, buf[0..len], 16) catch return false;
            ptr.* = val;
            return true;
        },
        'f', 'g', 'e' => {
            if (comptime !is_float_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const ch_first = getc(f);
            if (ch_first == -1) return false;
            if (ch_first == '-' or ch_first == '+') {
                buf[0] = @intCast(ch_first);
                len = 1;
            } else {
                _ = ungetc(ch_first, f);
            }
            var has_dot = false;
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if (ch >= '0' and ch <= '9') {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else if (ch == '.' and !has_dot) {
                    has_dot = true;
                    buf[len] = '.';
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0) return false;
            const val = std.fmt.parseFloat(ChildType, buf[0..len]) catch return false;
            ptr.* = val;
            return true;
        },
        else => return false,
    }
}

pub fn fscanf(file: ?*Stream, format: [*:0]const u8, args: anytype) c_int {
    const f = file orelse return -1;
    const fmt = std.mem.span(format);
    const ArgsType = @TypeOf(args);
    const fields = std.meta.fields(ArgsType);

    var f_idx: usize = 0;
    var arg_idx: usize = 0;
    var parsed_count: c_int = 0;

    while (f_idx < fmt.len) {
        if (fmt[f_idx] == '%') {
            f_idx += 1;
            if (f_idx >= fmt.len) break;
            if (fmt[f_idx] == '%') {
                const ch = getc(f);
                if (ch != '%') {
                    if (ch != -1) _ = ungetc(ch, f);
                    return parsed_count;
                }
                f_idx += 1;
                continue;
            }

            var suppress = false;
            if (fmt[f_idx] == '*') {
                suppress = true;
                f_idx += 1;
            }

            var width: ?usize = null;
            var w_val: usize = 0;
            var has_w = false;
            while (f_idx < fmt.len and fmt[f_idx] >= '0' and fmt[f_idx] <= '9') {
                w_val = w_val * 10 + (fmt[f_idx] - '0');
                has_w = true;
                f_idx += 1;
            }
            if (has_w) width = w_val;

            while (f_idx < fmt.len and (fmt[f_idx] == 'l' or fmt[f_idx] == 'h')) {
                f_idx += 1;
            }

            if (f_idx >= fmt.len) break;
            const spec = fmt[f_idx];
            f_idx += 1;

            if (spec != 'c') {
                while (true) {
                    const ch = getc(f);
                    if (ch == -1) {
                        if (parsed_count == 0) return -1;
                        return parsed_count;
                    }
                    if (!std.ascii.isWhitespace(@intCast(ch))) {
                        _ = ungetc(ch, f);
                        break;
                    }
                }
            }

            if (suppress) {
                if (spec == 'c') {
                    _ = getc(f);
                } else {
                    while (true) {
                        const ch = getc(f);
                        if (ch == -1) break;
                        if (std.ascii.isWhitespace(@intCast(ch))) {
                            _ = ungetc(ch, f);
                            break;
                        }
                    }
                }
                continue;
            }

            if (arg_idx >= fields.len) return parsed_count;

            const success = inline for (fields, 0..) |field, idx| {
                if (idx == arg_idx) {
                    const ptr = @field(args, field.name);
                    break scanValFromFile(f, spec, width, ptr);
                }
            } else false;

            if (!success) return parsed_count;
            parsed_count += 1;
            arg_idx += 1;
        } else if (std.ascii.isWhitespace(fmt[f_idx])) {
            f_idx += 1;
            while (true) {
                const ch = getc(f);
                if (ch == -1) break;
                if (!std.ascii.isWhitespace(@intCast(ch))) {
                    _ = ungetc(ch, f);
                    break;
                }
            }
        } else {
            const ch = getc(f);
            if (ch == -1 or ch != fmt[f_idx]) {
                if (ch != -1) _ = ungetc(ch, f);
                return parsed_count;
            }
            f_idx += 1;
        }
    }

    return parsed_count;
}
