//! files.zig — filesystem helpers for the interpreter's loader and REPL.
//!
//! Thin wrappers over `platform`/`main_clib` (stat, copy, unlink, terminal
//! width) plus the file-identity helpers the module loader uses to detect when
//! a source file has changed or two paths name the same inode. Most entry
//! points are re-exported through `main.zig` and called as `main.<fn>`.

const std = @import("std");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const abi = @import("../runtime/main_clib.zig");
const platform = @import("platform.zig");
const heap = @import("../runtime/heap.zig");
const lex = @import("../parser/lex.zig");

const lex_state = @import("../parser/lex_state.zig");
const core_state = @import("../runtime/core_state.zig");
const ls = lex_state.ls;

const Word = word.Word;
const NIL = word.NIL;
const t = heap.t;
const h = heap.h;

/// Returns the mtime of `path` as a Word, or 0 if the file does not exist.
/// Called from C ABI — parameter must remain a C string pointer.
pub fn fileMtime(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return @intCast(info.mtime);
    } else {
        return 0;
    }
}

/// Returns 1 if `path` ends in ".m" (a Miranda source file), 0 otherwise.
pub fn isMirandaSource(path: [*:0]const u8) c_int {
    const text = std.mem.span(path);
    return if (text.len >= 2 and std.mem.eql(u8, text[text.len - 2 ..], ".m")) 1 else 0;
}

/// Returns true if heap nodes `x` and `y` refer to the same filesystem inode.
pub fn sameFile(x: Word, y: Word) bool {
    const ix = heap.filInodev(x);
    const iy = heap.filInodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

/// Returns a heap cons cell `(dev . ino)` for `path`, used to track file identity across loads.
/// Returns `(0 . 0)` if the file does not exist.
pub fn inodeId(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return heap.cons(heap.cons(@intCast(info.dev), @intCast(info.ino)), word.NIL);
    } else {
        return heap.cons(heap.cons(0, 0), word.NIL);
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
pub fn fileCopy(path: [*:0]const u8) void {
    const fd = abi.open(path, abi.O_RDONLY, 0);
    if (fd < 0) return;
    defer _ = abi.close(fd);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = abi.read(fd, &buffer, buffer.len);
        if (n <= 0) break;
        _ = abi.write(abi.STDOUT_FILENO, &buffer, @intCast(n));
    }
}

/// Copies file `from` to file `to`, creating or truncating `to`. Used during dump/undump.
pub fn copyFile(from: [*:0]const u8, to: [*:0]const u8) void {
    const f_in = abi.open(from, abi.O_RDONLY, 0);
    if (f_in < 0) return;
    defer _ = abi.close(f_in);

    const f_out = abi.open(to, abi.O_WRONLY | abi.O_CREAT | abi.O_TRUNC, @as(c_uint, 0o644));
    if (f_out < 0) return;
    defer _ = abi.close(f_out);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = abi.read(f_in, &buffer, buffer.len);
        if (n <= 0) break;
        _ = abi.write(f_out, &buffer, @intCast(n));
    }
}

/// Deletes the object-file counterpart of `t_path` (replaces the final char with `obsuffix`).
/// No-op if the object file does not exist.
pub fn unlinkObject(core: *core_state.CoreState, t_path: [*:0]const u8) void {
    var obf_buf: [1024]u8 = undefined;
    const t_slice = std.mem.span(t_path);
    if (t_slice.len == 0) return;
    const len = t_slice.len;

    @memcpy(obf_buf[0 .. len - 1], t_slice[0 .. len - 1]);

    const obsuffix_slice = std.mem.span(core.obsuffix);
    @memcpy(obf_buf[len - 1 .. len - 1 + obsuffix_slice.len], obsuffix_slice);
    obf_buf[len - 1 + obsuffix_slice.len] = 0;

    const obf = @as([*:0]const u8, @ptrCast(obf_buf[0..].ptr));
    if (fileExists(obf)) {
        _ = abi.unlink(obf);
    }
}

/// Converts `m` to an absolute path by prepending cwd if needed. The result is
/// interned in the dictionary (`dicp`/`dicq`) and the original pointer updated.
/// Invariant: `m` must point into mutable, writable memory (not a string literal).
pub fn makeAbsolute(m: [*:0]u8) [*:0]u8 {
    if (m[0] == '/') {
        return m;
    }
    if (abi.getcwd(ls.dicp, abi.pnlim) == null) {
        errors.fatal("panic: cwd too long\n", .{.{}});
    }
    _ = word.strcat(ls.dicp, "/");
    _ = word.strcat(ls.dicp, m);
    const m_new = ls.dicp;
    ls.dicq += word.strlen(ls.dicp) + 1;
    ls.dicp = ls.dicq;
    lex.dicCheck();
    return m_new;
}

/// Returns the terminal column width minus 2, defaulting to 78 if unavailable.
pub fn termWidth() c_int {
    var window: abi.struct_winsize = undefined;
    if (abi.ioctl(abi.STDOUT_FILENO, abi.TIOCGWINSZ, &window) == -1 or window.ws_col == 0) {
        return 78;
    }
    return @as(c_int, @intCast(window.ws_col)) - 2;
}
