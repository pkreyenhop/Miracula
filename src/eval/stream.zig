//! stream.zig — the interpreter's file-handle abstraction: a minimal, pooled
//! `Stream` (posix fd or in-memory buffer, one-byte pushback, an 8 KiB read
//! buffer) plus the C-stdio-shaped operations built on it (`fopen`/`fclose`/
//! `getc`/`fread`/`fwrite`/`putc`/...) and the buffered stdout/stderr writers
//! (`IoState`) `word.print`/`word.printErr` use.
//!
//! Moved out of `word.zig` (Phase 2 step 4, docs/GoReady.md — word.zig
//! shrinking to the value vocabulary) as a pure relocation: every name here is
//! re-exported from `word.zig` unchanged, so no other file's imports needed to
//! change. `fread`/`fwrite` in particular preserve the dump (`.x`) file's byte
//! format exactly — nothing about their behavior changed in this move.

const std = @import("std");

/// A minimal stdio `Stream`: a posix fd (or an in-memory buffer for reading
/// dumps) with one-byte pushback and an 8 KiB read buffer. Allocated from a
/// fixed pool (`allocFile`/`freeFile`); the std streams are static instances.
pub const Stream = struct {
    file: std.Io.File = .{ .handle = -1, .flags = .{ .nonblocking = false } },
    pushback: ?u8 = null,
    mem_buf: ?[]const u8 = null,
    mem_pos: usize = 0,
    buf: [8192]u8 = undefined,
    buf_start: usize = 0,
    buf_end: usize = 0,
    /// Hook for interactive line input, installed by the REPL's line editor
    /// (zigline) on the `std_in` instance specifically. When non-null,
    /// `readByte` fills its buffer by calling this — an edited line (with
    /// history) plus a trailing newline, or null at end of input. Left null
    /// for non-interactive input (pipes, files) and every non-stdin `Stream`,
    /// which keeps using plain `read`, so piped tests are unaffected.
    readInteractiveLine: ?*const fn (dst: []u8) ?usize = null,

    /// Read one byte, honouring pushback, a memory-backed buffer, or the read buffer; errors at EOF.
    pub fn readByte(self: *Stream) !u8 {
        if (self.pushback) |pb| {
            self.pushback = null;
            return pb;
        }
        if (self.mem_buf) |buf| {
            if (self.mem_pos < buf.len) {
                const b = buf[self.mem_pos];
                self.mem_pos += 1;
                return b;
            }
            return error.EndOfStream;
        }
        if (self.buf_start >= self.buf_end) {
            const n = if (self.readInteractiveLine) |hook|
                (hook(&self.buf) orelse return error.EndOfStream)
            else
                try std.posix.read(self.file.handle, &self.buf);
            if (n == 0) return error.EndOfStream;
            self.buf_start = 0;
            self.buf_end = n;
        }
        const b = self.buf[self.buf_start];
        self.buf_start += 1;
        return b;
    }

    /// Push a byte back so the next read returns it (libc `ungetc`).
    pub fn ungetc(self: *Stream, c: u8) void {
        self.pushback = c;
    }

    /// Write a single byte directly (unbuffered).
    pub fn writeByte(self: *Stream, c: u8) !void {
        const buf = [1]u8{c};
        const rc = std.posix.system.write(self.file.handle, &buf, 1);
        if (rc < 0) return error.WriteFailed;
    }

    /// Write the whole slice, looping over short writes.
    pub fn writeAll(self: *Stream, slice: []const u8) !void {
        var written: usize = 0;
        while (written < slice.len) {
            const rc = std.posix.system.write(self.file.handle, slice[written..].ptr, slice.len - written);
            if (rc < 0) return error.WriteFailed;
            written += @intCast(rc);
        }
    }

    /// Write byte `c` `count` times (a padding helper).
    pub fn writeByteNTimes(self: *Stream, c: u8, count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try self.writeByte(c);
        }
    }

    /// Zig-native formatted write to this file (R1.4): the file analogue of
    /// `word.print`/`printErr`. Formats to a stack buffer and writes using
    /// writeAll to maintain correct streaming file offsets.
    pub fn print(self: *Stream, comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const fs = std.meta.fields(@TypeOf(args));
        const slice = if (comptime (fs.len == 1 and @typeInfo(fs[0].type) == .@"struct"))
            std.fmt.bufPrint(&buf, fmt, @field(args, fs[0].name)) catch return
        else
            std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.writeAll(slice) catch {};
    }
};

test "Stream.readByte: streams a memory buffer, then EndOfStream" {
    var f: Stream = .{ .mem_buf = "ab" };
    try std.testing.expectEqual(@as(u8, 'a'), try f.readByte());
    try std.testing.expectEqual(@as(u8, 'b'), try f.readByte());
    try std.testing.expectError(error.EndOfStream, f.readByte());
}

test "Stream.ungetc: the pushed byte is returned before the buffer resumes" {
    var f: Stream = .{ .mem_buf = "x" };
    f.ungetc('Z');
    try std.testing.expectEqual(@as(u8, 'Z'), try f.readByte());
    try std.testing.expectEqual(@as(u8, 'x'), try f.readByte());
}

/// Coerce any pointer/optional/null to an optional const C-string.
///
/// I/O subsystem state (shared-state plan Phase 2c): the stderr/stdout writer
/// caches, the three standard `Stream` streams, and the `Stream` allocation pool.
/// Accessed as `word.fio().X`; folds into `Interp.io` in Phase 3.
pub const IoState = struct {
    stdout_buf: [8192]u8 = undefined,
    stderr_buf: [8192]u8 = undefined,
    stdout_writer: std.Io.File.Writer = undefined,
    stderr_writer: std.Io.File.Writer = undefined,
    writers_initialized: bool = false,
    std_in: Stream = .{ .file = .{ .handle = std.posix.STDIN_FILENO, .flags = .{ .nonblocking = false } } },
    std_out: Stream = .{ .file = .{ .handle = std.posix.STDOUT_FILENO, .flags = .{ .nonblocking = false } } },
    std_err: Stream = .{ .file = .{ .handle = std.posix.STDERR_FILENO, .flags = .{ .nonblocking = false } } },
    file_pool: [16]Stream = undefined,
    file_in_use: [16]bool = [_]bool{false} ** 16,
};

/// Pointer to the I/O subsystem state held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `word.fio().X`.
pub inline fn fio() *IoState {
    return &@import("../session/interp.zig").current_interp.io;
}

/// The process's actual `std.Io` implementation (`rt.io`, set from
/// `ctx.io` in `main.zig`) — not `std.Options.debug_io`, which is only a
/// default and may not be the same implementation the process was
/// actually handed. Read via an inline `@import` (not a top-level const)
/// to avoid a cycle: `runtime_state.zig` imports `os.zig`, which
/// imports this file, and `word.zig` is a leaf module every other file is
/// meant to import freely.
inline fn procIo() std.Io {
    return @import("../runtime/runtime_state.zig").io;
}

/// Lazily initialise the buffered stdout/stderr writers (once).
pub fn initWriters() void {
    if (fio().writers_initialized) return;
    const io = procIo();
    fio().stdout_writer = std.Io.File.stdout().writer(io, &fio().stdout_buf);
    fio().stderr_writer = std.Io.File.stderr().writer(io, &fio().stderr_buf);
    fio().writers_initialized = true;
}

/// Formatted write to stdout using Zig format strings (the buffered analogue of
/// libc `printf`); flushes after each call.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    initWriters();
    fio().stdout_writer.interface.print(fmt, args) catch {};
    fio().stdout_writer.interface.flush() catch {};
}

/// Formatted write to stderr (the `print` analogue).
pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    initWriters();
    fio().stderr_writer.interface.print(fmt, args) catch {};
    fio().stderr_writer.interface.flush() catch {};
}

/// Zig-native formatted write to an optional file (the `fprintf` analogue):
/// a no-op when `file` is null, matching the old shim's behaviour. Lets
/// file-targeted call sites convert without sprinkling `.?`.
pub fn fprint(file: ?*Stream, comptime fmt: []const u8, args: anytype) void {
    if (file) |f| f.print(fmt, args);
}

// stdio: std streams, Stream pool, and C-style file ops (R1.5/R1.6 consolidation).
// `printf`/`fprintf`/`sprintf`/`snprintf`/`formatC`/`formatArg` (the runtime
// C-format-string engine) and `fmemopen` were deleted here (Phase 2 step 3/4,
// docs/GoReady.md) once nothing called them anymore — every call site
// now uses Zig-native format strings via `word.print`/`printErr`/`fprint`, or
// (for reading dumps) `fopen` directly. `putc`/`putchar` stay: still used by
// `heap.zig`'s dump writer. The whole stdio subsystem lives next to the Stream
// struct; os.zig
// re-exports these. fread/fwrite preserve the dump (.x) byte format.
// (fio.std_in/fio.std_out/fio.std_err and the Stream pool now live in `IoState` above.)

/// The standard-input `Stream`.
pub fn stdin() ?*Stream {
    return &fio().std_in;
}
/// The standard-output `Stream`.
pub fn stdout() ?*Stream {
    return &fio().std_out;
}
/// The standard-error `Stream`.
pub fn stderr() ?*Stream {
    return &fio().std_err;
}

// (fio.file_pool / fio.file_in_use now live in `IoState` above.)

/// Claim a free slot from the fixed `Stream` pool, or null if exhausted.
fn allocFile() ?*Stream {
    for (&fio().file_in_use, 0..) |*in_use, idx| {
        if (!in_use.*) {
            in_use.* = true;
            fio().file_pool[idx] = Stream{ .file = .{ .handle = -1, .flags = .{ .nonblocking = false } } };
            return &fio().file_pool[idx];
        }
    }
    return null;
}

/// Return a pooled `Stream` to the free list.
fn freeFile(f: *Stream) void {
    // Find `f`'s slot by pointer identity (no int<->ptr cast); a no-op if `f`
    // isn't a pooled Stream, matching the old in-range check.
    for (&fio().file_pool, 0..) |*slot, i| {
        if (slot == f) {
            fio().file_in_use[i] = false;
            return;
        }
    }
}

/// libc `fopen` (modes r/w/a) over the `Stream` pool.
pub fn fopen(path: ?*const anyopaque, mode: [*:0]const u8) ?*Stream {
    if (path == null) return null;
    const path_str = @as([*:0]const u8, @ptrCast(path.?));
    const mode_slice = std.mem.span(mode);

    var for_read = false;
    var for_write = false;
    var for_append = false;
    for (mode_slice) |mc| {
        if (mc == 'r') for_read = true;
        if (mc == 'w') for_write = true;
        if (mc == 'a') for_append = true;
    }

    const io = procIo();
    const dir = std.Io.Dir.cwd();

    const file = if (for_read)
        dir.openFile(io, std.mem.span(path_str), .{}) catch return null
    else if (for_write)
        dir.createFile(io, std.mem.span(path_str), .{}) catch return null
    else if (for_append) d: {
        const f = dir.createFile(io, std.mem.span(path_str), .{ .truncate = false }) catch return null;
        _ = std.posix.system.lseek(f.handle, 0, 2);
        break :d f;
    } else return null;

    const f_ptr = allocFile() orelse {
        file.close(io);
        return null;
    };
    f_ptr.file = file;
    f_ptr.pushback = null;
    f_ptr.mem_buf = null;
    f_ptr.mem_pos = 0;
    f_ptr.buf_start = 0;
    f_ptr.buf_end = 0;
    return f_ptr;
}

/// libc `fclose` (a no-op for the std streams).
pub fn fclose(file: ?*Stream) i32 {
    if (file) |f| {
        if (f == &fio().std_in or f == &fio().std_out or f == &fio().std_err) {
            return 0;
        }
        if (f.file.handle >= 0) {
            const io = procIo();
            f.file.close(io);
            f.file.handle = -1;
        }
        freeFile(f);
        return 0;
    }
    return -1;
}

/// The underlying file descriptor, or -1.
pub fn fileno(file: ?*Stream) i32 {
    if (file) |f| return f.file.handle;
    return -1;
}

/// libc `setbuf` — a no-op here (I/O is already unbuffered).
pub fn setbuf(file: ?*Stream, buf: ?[*]u8) void {
    _ = file;
    _ = buf;
}

/// libc `getc`: next byte, or -1 at EOF.
pub fn getc(file: ?*Stream) i32 {
    const f = file orelse return -1;
    const byte = f.readByte() catch return -1;
    return @as(i32, byte);
}

/// libc `getchar` (reads stdin).
pub fn getchar() i32 {
    return getc(&fio().std_in);
}

/// Push a byte back so the next read returns it (libc `ungetc`).
pub fn ungetc(ch: i32, file: ?*Stream) i32 {
    const f = file orelse return -1;
    if (ch == -1) return -1;
    f.ungetc(@intCast(@as(u8, @intCast(ch))));
    return ch;
}

/// libc `fgets`: read a line (up to `size-1` bytes or a newline) into `buf`.
pub fn fgets(buf: [*]u8, size: i32, file: ?*Stream) ?[*]u8 {
    const f = file orelse return null;
    if (size <= 1) return null;
    var i: usize = 0;
    const limit = @as(usize, @intCast(size - 1));
    while (i < limit) {
        const c_val = getc(f);
        if (c_val == -1) {
            if (i == 0) return null;
            break;
        }
        buf[i] = @intCast(@as(u8, @intCast(c_val)));
        i += 1;
        if (c_val == '\n') {
            break;
        }
    }
    buf[i] = 0;
    return buf;
}

/// libc `fread`: read `nmemb` items of `size` bytes; returns items read.
pub fn fread(ptr: ?*anyopaque, size: usize, nmemb: usize, file: ?*Stream) usize {
    const f = file orelse return 0;
    if (ptr == null or size == 0 or nmemb == 0) return 0;
    const buf = @as([*]u8, @ptrCast(ptr.?));
    const total_bytes = size * nmemb;
    var i: usize = 0;
    while (i < total_bytes) : (i += 1) {
        const byte = f.readByte() catch break;
        buf[i] = byte;
    }
    return i / size;
}

/// libc `fwrite`: write `nmemb` items of `size` bytes; returns items written.
pub fn fwrite(ptr: ?*const anyopaque, size: usize, nmemb: usize, file: ?*Stream) usize {
    const f = file orelse return 0;
    if (ptr == null or size == 0 or nmemb == 0) return 0;
    const buf = @as([*]const u8, @ptrCast(ptr.?));
    const total_bytes = size * nmemb;
    var i: usize = 0;
    while (i < total_bytes) : (i += 1) {
        f.writeByte(buf[i]) catch break;
    }
    return i / size;
}

/// libc `fdopen`: wrap an existing fd in a pooled `Stream`.
pub fn fdopen(fd: i32, mode: [*:0]const u8) ?*Stream {
    _ = mode;
    const f_ptr = allocFile() orelse return null;
    f_ptr.file = .{ .handle = fd, .flags = .{ .nonblocking = false } };
    f_ptr.pushback = null;
    f_ptr.mem_buf = null;
    f_ptr.mem_pos = 0;
    return f_ptr;
}

/// libc `putc`: write one char to `file`.
pub fn putc(ch: i32, file: ?*Stream) i32 {
    const f = file orelse return -1;
    f.writeByte(@intCast(@as(u8, @intCast(ch)))) catch return -1;
    return ch;
}

/// libc `fputc` (an alias for `putc`).
pub fn fputc(ch: i32, file: ?*Stream) i32 {
    return putc(ch, file);
}

/// libc `putchar` (to stdout).
pub fn putchar(ch: i32) i32 {
    return putc(ch, &fio().std_out);
}
