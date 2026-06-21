const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");
const platform = @import("platform.zig");

const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

const Word = main.Word;
const NIL = main.NIL;
const t = main.heap.t;
const h = main.heap.h;

/// Returns the mtime of `path` as a Word, or 0 if the file does not exist.
/// Called from C ABI — parameter must remain a C string pointer.
pub export fn fm_time(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return @intCast(info.mtime);
    } else {
        return 0;
    }
}

/// Returns 1 if `path` ends in ".m" (a Miranda source file), 0 otherwise.
pub fn normal(path: [*:0]const u8) c_int {
    const text = std.mem.span(path);
    return if (text.len >= 2 and std.mem.eql(u8, text[text.len - 2 ..], ".m")) 1 else 0;
}

/// Returns true if heap nodes `x` and `y` refer to the same filesystem inode.
pub fn same_file(x: Word, y: Word) bool {
    const ix = main.fil_inodev(x);
    const iy = main.fil_inodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

/// Returns a heap cons cell `(dev . ino)` for `path`, used to track file identity across loads.
/// Returns `(0 . 0)` if the file does not exist.
pub fn inodev(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return main.cons(main.cons(@intCast(info.dev), @intCast(info.ino)), main.NIL);
    } else {
        return main.cons(main.cons(0, 0), main.NIL);
    }
}

/// Returns true if `path` exists and is stat-able.
pub fn fileExists(path: [*:0]const u8) bool {
    if (platform.getFileInfo(path)) |_| {
        return true;
    } else {
        return false;
    }
}

/// Copies the contents of `path` to stdout. Used by the `//f` command to display source.
pub fn filecopy(path: [*:0]const u8) void {
    const fd = clib.open(path, clib.O_RDONLY, 0);
    if (fd < 0) return;
    defer _ = clib.close(fd);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = clib.read(fd, &buffer, buffer.len);
        if (n <= 0) break;
        _ = clib.write(clib.STDOUT_FILENO, &buffer, @intCast(n));
    }
}

/// Copies file `from` to file `to`, creating or truncating `to`. Used during dump/undump.
pub fn filecp(from: [*:0]const u8, to: [*:0]const u8) void {
    const f_in = clib.open(from, clib.O_RDONLY, 0);
    if (f_in < 0) return;
    defer _ = clib.close(f_in);

    const f_out = clib.open(to, clib.O_WRONLY | clib.O_CREAT | clib.O_TRUNC, @as(c_uint, 0o644));
    if (f_out < 0) return;
    defer _ = clib.close(f_out);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = clib.read(f_in, &buffer, buffer.len);
        if (n <= 0) break;
        _ = clib.write(f_out, &buffer, @intCast(n));
    }
}

/// Deletes the object-file counterpart of `t_path` (replaces the final char with `obsuffix`).
/// No-op if the object file does not exist.
pub export fn unlinkx(t_path: [*:0]const u8) void {
    var obf_buf: [1024]u8 = undefined;
    const t_slice = std.mem.span(t_path);
    if (t_slice.len == 0) return;
    const len = t_slice.len;

    @memcpy(obf_buf[0 .. len - 1], t_slice[0 .. len - 1]);

    const obsuffix_slice = std.mem.span(main.obsuffix);
    @memcpy(obf_buf[len - 1 .. len - 1 + obsuffix_slice.len], obsuffix_slice);
    obf_buf[len - 1 + obsuffix_slice.len] = 0;

    const obf = @as([*:0]const u8, @ptrCast(obf_buf[0..].ptr));
    if (fileExists(obf)) {
        _ = clib.unlink(obf);
    }
}

/// Converts `m` to an absolute path by prepending cwd if needed. The result is
/// interned in the dictionary (`dicp`/`dicq`) and the original pointer updated.
/// Invariant: `m` must point into mutable, writable memory (not a string literal).
pub fn mkabsolute(m: [*:0]u8) [*:0]u8 {
    if (m[0] == '/') {
        return m;
    }
    if (clib.getcwd(ls.dicp, clib.pnlim) == null) {
        main.fatal("panic: cwd too long\n", .{.{}});
    }
    _ = clib.strcat(ls.dicp, "/");
    _ = clib.strcat(ls.dicp, m);
    const m_new = ls.dicp;
    ls.dicq += clib.strlen(ls.dicp) + 1;
    ls.dicp = ls.dicq;
    main.dic_check();
    return m_new;
}

/// Returns the terminal column width minus 2, defaulting to 78 if unavailable.
pub fn twidth() c_int {
    var window: clib.struct_winsize = undefined;
    if (clib.ioctl(clib.STDOUT_FILENO, clib.TIOCGWINSZ, &window) == -1 or window.ws_col == 0) {
        return 78;
    }
    return @as(c_int, @intCast(window.ws_col)) - 2;
}
