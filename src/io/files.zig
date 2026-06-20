const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");
const platform = @import("platform.zig");

const Word = main.Word;
const NIL = main.NIL;
const t = main.heap.t;
const h = main.heap.h;

pub export fn fm_time(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return @intCast(info.mtime);
    } else {
        return 0;
    }
}

pub export fn normal(path: [*:0]const u8) c_int {
    const text = std.mem.span(path);
    return if (text.len >= 2 and std.mem.eql(u8, text[text.len - 2 ..], ".m")) 1 else 0;
}

pub fn same_file(x: Word, y: Word) bool {
    const ix = main.fil_inodev(x);
    const iy = main.fil_inodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

pub fn inodev(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return main.cons(main.cons(@intCast(info.dev), @intCast(info.ino)), main.NIL);
    } else {
        return main.cons(main.cons(0, 0), main.NIL);
    }
}

pub fn fileExists(path: [*:0]const u8) bool {
    if (platform.getFileInfo(path)) |_| {
        return true;
    } else {
        return false;
    }
}

pub export fn filecopy(path: [*:0]const u8) void {
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

pub export fn filecp(from: [*:0]const u8, to: [*:0]const u8) void {
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

pub fn mkabsolute(m: [*:0]u8) [*:0]u8 {
    if (m[0] == '/') {
        return m;
    }
    if (clib.getcwd(main.dicp, clib.pnlim) == null) {
        _ = clib.fprintf(main.getStderr(), "panic: cwd too long\n", .{.{}});
        clib.exit(1);
    }
    _ = clib.strcat(main.dicp, "/");
    _ = clib.strcat(main.dicp, m);
    const m_new = main.dicp;
    main.dicq += clib.strlen(main.dicp) + 1;
    main.dicp = main.dicq;
    main.dic_check();
    return m_new;
}

pub export fn twidth() c_int {
    var window: clib.struct_winsize = undefined;
    if (clib.ioctl(clib.STDOUT_FILENO, clib.TIOCGWINSZ, &window) == -1 or window.ws_col == 0) {
        return 78;
    }
    return @as(c_int, @intCast(window.ws_col)) - 2;
}
