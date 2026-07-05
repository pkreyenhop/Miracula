//! reduce.zig — runtime support around the reduction engine.
//!
//! Holds the evaluation-time state (`EvalState`/`ev`) and the services the
//! combinator handlers call into: the I/O-directive interpreter (`output`/
//! `print`/`outf`/`apfile`/`closefile`), the strict-stream backend (`streamRead`
//! for `READ`/`READVALS`), value services (`force`, `compare`, `numplus`,
//! `head`), grammar/lexer helpers (`gResidue`, `memclass`, `lexstate`), and the
//! family of fatal-error reporters (`mathError`, `intError`, `badcaseError`, …).
//! The graph-reduction machine itself lives in `reducer/reduce.zig`.

const std = @import("std");
const options = @import("version_options");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const platform = @import("../io/platform.zig");
const rt = @import("runtime_state.zig");
const heap = @import("heap.zig");
const repl = @import("../driver/repl.zig");
const engine = @import("reducer/reduce.zig");
const reducer_trace = @import("reducer/trace.zig");
const big = @import("big.zig");
const lex = @import("../parser/lex.zig");
const main_clib = @import("main_clib.zig");
const core_state = @import("core_state.zig");
const reduce_core = @import("reducer/reduce_core.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;
const NIL: Word = word.CMBASE + 138;
const FST = word.HD;
const MAXDIGIT = 0x7fff;
const SIGNBIT = 0x10000000;

/// Evaluation / reducer-I/O state (shared-state plan Phase 2d). Accessed as
/// `reduce.ev.X`; folds into `Interp.eval` in Phase 3.
pub const EvalState = struct {
    /// How stdin is currently bound (0 = free, ':' = text read, '-' = binary).
    stdinuse: Word = 0,
    /// Queue of open output files (`Tofile`/`Appendfile`).
    outfilq: Word = NIL,
    /// List of child processes awaiting `wait`.
    waiting: Word = NIL,
    /// Current `Tofile` output stream.
    s_out: ?*word.FILE = null,
    /// Evaluation-error recovery trap.
    errtrap: Word = 0,
    /// Reduction-step counter (the perf metric reported by `outstats`).
    cycles: i64 = 0,
};

/// Pointer to the evaluator state held in `interp` (so `interp.reset()` clears
/// it). Accessed as `ev.X`.
pub const ev = &@import("interp.zig").interp.eval;

const stoChar = heap.stoChar;
extern fn fromUTF8(f: ?*word.FILE) Word;
const parseLine = repl.parseLine;
const reduce = engine.reduce;
const charname = heap.charname;

inline fn getTag(x: Word) word.NodeTag {
    return heap.heap.getTag(x);
}

inline fn setTag(x: Word, val: word.NodeTag) void {
    heap.heap.setTag(x, val);
}

inline fn h(x: Word) Word {
    return heap.heap.h(x);
}

inline fn t(x: Word) Word {
    return heap.heap.t(x);
}

inline fn hp(x: Word) *Word {
    return heap.heap.hp(x);
}

inline fn tp(x: Word) *Word {
    return heap.heap.tp(x);
}

inline fn lh(x: Word) Word {
    if (getTag(h(x)) == .STRCONS) {
        return t(h(x));
    } else {
        return h(x);
    }
}

inline fn forceDbl(x: Word) f64 {
    if (getTag(x) == .INT) {
        return big.toFloat(heap.heap, x);
    } else {
        return heap.getDbl(x);
    }
}

inline fn fsign(x: f64) c_int {
    if (x < 0.0) return -1;
    if (x > 0.0) return 1;
    return 0;
}

inline fn sign(x: c_long) c_int {
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}

inline fn cons(x: Word, y: Word) Word {
    return heap.make(.CONS, x, y);
}

inline fn ap(x: Word, y: Word) Word {
    return heap.make(.AP, x, y);
}

inline fn datapair(x: Word, y: Word) Word {
    return heap.make(.DATAPAIR, x, y);
}

inline fn digit0(x: Word) Word {
    return h(x) & MAXDIGIT;
}

inline fn stosmallint(x: Word) Word {
    const val = if (x < 0) SIGNBIT | (-x) else x;
    return heap.make(.INT, val, 0);
}

/// The standard-input `FILE*` handle.
fn getStdin() ?*word.FILE {
    const T = @TypeOf(main_clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdin();
    } else {
        return main_clib.stdin;
    }
}

/// The standard-error `FILE*` handle.
fn getStderr() ?*word.FILE {
    const T = @TypeOf(main_clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stderr();
    } else {
        return main_clib.stderr;
    }
}

/// The standard-output `FILE*` handle.
fn getStdout() ?*word.FILE {
    const T = @TypeOf(main_clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdout();
    } else {
        return main_clib.stdout;
    }
}

inline fn rewriteToValue(expr: *Word, value: Word) void {
    hp(expr.*).* = word.I;
    tp(expr.*).* = value;
    expr.* = value;
}

inline fn rewriteToNil(expr: *Word) void {
    rewriteToValue(expr, NIL);
}

inline fn setcell(e: Word, t_val: word.NodeTag, a: Word, b: Word) void {
    setTag(e, t_val);
    hp(e).* = a;
    tp(e).* = b;
}

inline fn rewriteToCons(e: Word, hd_value: Word, tl_value: Word) void {
    setcell(e, .CONS, hd_value, tl_value);
}

/// Abort with "missing case in definition" — the `BADCASE` combinator's reporter.
pub fn badcaseError(arg_info: Word) void {
    const subject = h(arg_info);
    word.printErr("\nprogram error: missing case in definition", .{});
    if (subject != 0) {
        word.printErr(" of {s}", .{std.mem.span(getstring(subject, null).?)});
    }
    _ = word.putc('\n', getStderr().?);
    outHere(getStderr().?, t(arg_info), 1);
    outstats();
    main_clib.exit(1);
}

/// Abort with "lhs of definition doesn't match rhs" (a conformality error).
pub fn confError(arg_info: Word) void {
    word.printErr("\nprogram error: lhs of definition doesn't match rhs\n", .{});
    outHere(getStderr().?, t(arg_info), 1);
    outstats();
    main_clib.exit(1);
}

/// Abort a failed `$$`-grammar parse, reporting the unexpected token (or end of input).
pub fn parseCloseError(arg1: Word, arg3: Word) void {
    word.printErr("\nPARSE OF {s}FAILS WITH UNEXPECTED ", .{std.mem.span(getstring(arg1, null).?)});
    const arg3_reduced = reduce(t(gResidue(arg3)));
    if (arg3_reduced == NIL) {
        word.printErr("END OF INPUT\n", .{});
        outstats();
        main_clib.exit(1);
    }
    var hold_val = heap.make(.AP, FST, h(arg3_reduced));
    hold_val = reduce(hold_val);
    word.printErr("TOKEN \"", .{});
    if (hold_val == word.OFFSIDE) {
        word.printErr("offside", .{});
    }
    const p = getstring(hold_val, null);
    if (p) |ptr| {
        var i: usize = 0;
        while (ptr[i] != 0) : (i += 1) {
            word.printErr("{s}", .{charname(ptr[i])});
        }
    }
    word.printErr("\"\n", .{});
    outstats();
    main_clib.exit(1);
}

/// Backend for `READ`/`READBIN`/`READVALS`: pull the next char/value from the
/// stream in `ctx`, rewriting the node to a cons (or `[]` at EOF).
///
/// Was reached via an `extern fn`/`pub export fn` pair with `io.zig` (a
/// linker-as-module-system link, like the ones R7.3 already dissolved
/// elsewhere) through a separately-declared `reduce_ctx` struct whose layout
/// only *happened* to match `ReductionCtx` for the fields actually read here.
/// Takes the real `ReductionCtx` directly now, and the four inline "UPLEFT"
/// reimplementations are gone in favour of calling `reduce_core.upLeft`
/// itself (dropping the third copy of that primitive the Phase-2
/// investigation found).
pub fn streamRead(ctx: *reduce_core.ReductionCtx, op: Word) Word {
    switch (op) {
        word.READBIN => {
            reduce_core.upLeft(ctx);
            const lastarg = t(ctx.e);

            if (lastarg == 0) {
                if (ev.stdinuse == '-') {
                    stdinError(':');
                }
                if (ev.stdinuse != 0) {
                    rewriteToNil(&ctx.e);
                    return word.ACT_DONE;
                }
                ev.stdinuse = ':';
                tp(ctx.e).* = @as(Word, @intCast(@intFromPtr(getStdin().?)));
            }
            const hold_char = main_clib.getc(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
            if (hold_char == main_clib.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
                rewriteToNil(&ctx.e);
                return word.ACT_DONE;
            }
            rewriteToCons(ctx.e, hold_char, heap.make(.AP, word.READBIN, t(ctx.e)));
            return word.ACT_DONE;
        },
        word.READ => {
            reduce_core.upLeft(ctx);
            const lastarg = t(ctx.e);

            if (lastarg == 0) {
                if (ev.stdinuse == ':') {
                    stdinError('-');
                }
                if (ev.stdinuse != 0) {
                    rewriteToNil(&ctx.e);
                    return word.ACT_DONE;
                }
                ev.stdinuse = '-';
                tp(ctx.e).* = @as(Word, @intCast(@intFromPtr(getStdin().?)));
            }
            const hold_char = if (rt.rs.UTF8 != 0) stoChar(fromUTF8(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))))) else main_clib.getc(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
            if (hold_char == main_clib.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
                rewriteToNil(&ctx.e);
                return word.ACT_DONE;
            }
            rewriteToCons(ctx.e, hold_char, heap.make(.AP, word.READ, t(ctx.e)));
            return word.ACT_DONE;
        },
        word.READVALS => {
            reduce_core.upLeft(ctx); // GETARG(arg1)
            ctx.args[0] = t(ctx.e);

            if (ctx.spine.isEmpty()) return word.ACT_DONE;

            reduce_core.upLeft(ctx);
            const lastarg = t(ctx.e);

            const val = parseLine(ctx.heap, h(ctx.args[0]), @ptrFromInt(@as(usize, @intCast(lastarg))), t(ctx.args[0]));
            if (val == main_clib.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(lastarg))));
                rewriteToNil(&ctx.e);
                return word.ACT_DONE;
            }
            ctx.args[1] = heap.make(.AP, h(ctx.e), lastarg);
            rewriteToCons(ctx.e, val, ctx.args[1]);
            return word.ACT_DONE;
        },
        else => return word.ACT_NONE,
    }
}

/// Flatten a Miranda char-list `x` into a NUL-terminated C string in `linebuf`; aborts via `cmd` if it exceeds 1024 chars.
///
/// Tests: getstring: copies a char list into a C-string
pub fn getstring(x: Word, cmd: ?[*:0]const u8) ?[*:0]u8 {
    var curr_x = x;
    const x1 = x;
    var n: usize = 0;
    const buf_size = 1024;
    while (getTag(curr_x) == .CONS and n < buf_size) {
        n += 1;
        hp(curr_x).* = reduce(h(curr_x));
        tp(curr_x).* = reduce(t(curr_x));
        curr_x = t(curr_x);
    }
    curr_x = x1;
    var p_idx: usize = 0;
    while (getTag(curr_x) == .CONS and n > 0) {
        n -= 1;
        rt.rs.linebuf[p_idx] = @intCast(h(curr_x));
        p_idx += 1;
        curr_x = t(curr_x);
    }
    rt.rs.linebuf[p_idx] = 0;
    p_idx += 1;
    if (p_idx > buf_size) {
        if (cmd) |cmd_str| {
            word.printErr("\n{s}, argument string too long (limit={} chars): {s}...\n", .{ cmd_str, @as(c_int, buf_size), &rt.rs.linebuf });
            outstats();
            main_clib.exit(1);
        } else {
            return @ptrCast(&rt.rs.linebuf);
        }
    }
    return @ptrCast(&rt.rs.linebuf);
}

test "getstring: copies a char list into a C-string" {
    tu.freshInterp();
    const s = getstring(tu.str("hello"), null);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("hello", std.mem.span(@as([*:0]const u8, s.?)));
}

/// Reset the reduction clock (currently a no-op stub).
pub fn initclock() void {}

/// Print the end-of-evaluation statistics (reductions, cells, GC) when enabled.
pub fn outstats() void {
    reducer_trace.dump(); // per-combinator trace (no-op unless -Dreduce-trace)
    if (rt.rs.atcount == 0) {
        return;
    }
    var buffer: main_clib.struct_tms = undefined;
    _ = main_clib.times(&buffer);
    word.printErr("||", .{});
    word.printErr("reductions = {}, cells claimed = {}, ", .{ ev.cycles, heap.heap.cellcount + heap.heap.claims });
    const clk_tck = @as(f64, @floatFromInt(main_clib.sysconf(word._SC_CLK_TCK)));
    word.printErr("no of gc's = {}, cpu = {d:.2}\n", .{ heap.heap.nogcs, @as(f64, @floatFromInt(buffer.tms_utime)) / clk_tck });
}

/// Write value `h_val` to file `f` for diagnostics, optionally followed by a newline.
pub fn outHere(f: ?*word.FILE, h_val: Word, nl: c_int) void {
    if (getTag(h_val) != .FILEINFO) {
        word.printErr("(impossible event in outhere)\n", .{});
        return;
    }
    f.?.print("(line {d:>3} of \"{s}\")", .{.{ t(h_val), strtab.strOf(strtab.table, h(h_val)) }});
    if (nl != 0) {
        _ = word.putc('\n', f.?);
    } else {
        _ = word.putc(' ', f.?);
    }
    if (core_state.s.compiling != 0 and core_state.s.errs == 0) {
        core_state.s.errs = h_val;
    }
}

/// Human-readable name of a standard-stream selector.
fn stdname(c_val: c_int) [*:0]const u8 {
    return if (c_val == ':') "$:-" else if (c_val == '-') "$-" else "$+";
}

/// Abort: stdin was read both as characters and as values (the `-`/`:` conflict).
pub fn stdinError(c_val: c_int) void {
    if (ev.stdinuse == c_val) {
        word.printErr("program error: duplicate use of {s}\n", .{stdname(c_val)});
    } else {
        word.printErr("program error: simultaneous use of {s} and {s}\n", .{ stdname(c_val), stdname(@intCast(ev.stdinuse)) });
    }
    outstats();
    main_clib.exit(1);
}

/// Abort with the function-related runtime error message `s`.
pub fn fnError(s: [*:0]const u8) void {
    word.printErr("\nprogram error: {s}\n", .{s});
    outstats();
    main_clib.exit(1);
}

/// Warn that environment variable `a` holds a non-Latin-1 value.
pub fn getenvError(a: [*:0]const u8) void {
    word.printErr("program error: getenv({s}): illegal characters in result string\n", .{a});
    outstats();
    main_clib.exit(1);
}

/// Abort with a list-subscript-out-of-range error.
pub fn subsError() void {
    fnError("subscript out of range");
}

/// Abort with a division-by-zero error.
pub fn divError() void {
    fnError("attempt to divide by zero");
}

/// Abort with a maths-domain error for function `s` (e.g. `log` of `<= 0`).
pub fn mathError(s: [*:0]const u8) void {
    const err_val = platform.getErrno();
    const err_type: [*:0]const u8 = if (err_val == main_clib.EDOM) "domain " else if (err_val == main_clib.ERANGE) "range " else "";
    word.printErr("\nmath function {s}error ({s})\n", .{ err_type, s });
    outstats();
    main_clib.exit(1);
}

/// Abort: operation `s` requires an integer argument.
pub fn intError(s: [*:0]const u8) void {
    word.printErr("\nprogram error: fractional number where integer expected ({s})\n", .{s});
    outstats();
    main_clib.exit(1);
}

/// Add `x + y`, promoting to `f64` if either is a `DOUBLE`, else bignum add.
///
/// Tests: numplus: integer add and float promotion
pub fn numplus(x: Word, y: Word) Word {
    if (getTag(x) == .DOUBLE) {
        return heap.stoDbl(heap.getDbl(x) + forceDbl(y));
    }
    if (getTag(y) == .DOUBLE) {
        return heap.stoDbl(big.toFloat(heap.heap, x) + heap.getDbl(y));
    }
    return big.add(heap.heap, x, y);
}

test "numplus: integer add and float promotion" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(c_longlong, 5), big.toInt(heap.heap, numplus(big.fromInt(heap.heap, 2), big.fromInt(heap.heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, -1), big.toInt(heap.heap, numplus(big.fromInt(heap.heap, 2), big.fromInt(heap.heap, -3))));
    const r = numplus(heap.stoDbl(1.5), big.fromInt(heap.heap, 2)); // DOUBLE + INT → DOUBLE
    try std.testing.expectEqual(word.NodeTag.DOUBLE, heap.getTag(r));
    try std.testing.expectEqual(@as(f64, 3.5), heap.getDbl(r));
}

/// The residual (unconsumed) token list after a grammar parse, reversed via `DESTREV`.
pub fn gResidue(toks2: Word) Word {
    var curr_toks2 = toks2;
    var toks1 = NIL;
    if (getTag(curr_toks2) != .CONS) {
        if (getTag(curr_toks2) == .AP and h(curr_toks2) == word.I and t(curr_toks2) == NIL) {
            return cons(NIL, NIL);
        }
        return cons(NIL, curr_toks2);
    }
    while (getTag(t(curr_toks2)) == .CONS) {
        toks1 = cons(h(curr_toks2), toks1);
        curr_toks2 = t(curr_toks2);
    }
    if (t(curr_toks2) == NIL or (getTag(t(curr_toks2)) == .AP and h(t(curr_toks2)) == word.I and t(t(curr_toks2)) == NIL)) {
        toks1 = cons(h(curr_toks2), toks1);
        return cons(ap(word.DESTREV, toks1), NIL);
    }
    return cons(ap(word.DESTREV, toks1), t(curr_toks2));
}

/// 1 if character `c_val` is in the lexer character-class list `x_val` (handles `..` ranges).
///
/// Tests: memclass: character-class membership with ranges
pub fn memclass(c_val: c_int, x_val: Word) c_int {
    var x = x_val;
    while (x != NIL) {
        if (h(x) == word.DOTDOT) {
            x = t(x);
            if (h(x) <= c_val and c_val <= h(t(x))) {
                return 1;
            }
            x = t(x);
        } else if (c_val == h(x)) {
            return 1;
        }
        x = t(x);
    }
    return 0;
}

test "memclass: character-class membership with ranges" {
    tu.freshInterp();
    // a range is encoded as [DOTDOT, low, high]
    const range = cons(word.DOTDOT, cons('a', cons('z', NIL)));
    try std.testing.expectEqual(@as(c_int, 1), memclass('m', range));
    try std.testing.expectEqual(@as(c_int, 0), memclass('A', range));
    // a bare class member
    const single = cons('x', NIL);
    try std.testing.expectEqual(@as(c_int, 1), memclass('x', single));
    try std.testing.expectEqual(@as(c_int, 0), memclass('y', single));
}

/// Abort: the lexer hit unrecognised input; prints up to 24 chars of context.
pub fn lexfail(x_val: Word) void {
    var x = x_val;
    var i: i32 = 24;
    word.printErr("\nLEX FAILS WITH UNRECOGNISED INPUT: \"", .{});
    while (i > 0 and x != NIL and 0 <= lh(x) and lh(x) <= 255) {
        i -= 1;
        word.printErr("{s}", .{charname(@intCast(lh(x)))});
        x = t(x);
    }
    word.printErr("{s}\"\n", .{if (x == NIL) @as([*:0]const u8, "") else "..."});
    outstats();
    main_clib.exit(1);
}

/// Split a packed lexer-state value into a `(hi . lo)` cons.
pub fn lexstate(x: Word) Word {
    const val = h(h(x));
    return cons(big.fromInt(heap.heap, val >> 8), stosmallint(val & 255));
}

/// The error message for a failed `fork`/pipe (used by `system`).
pub fn piperrmess(pid: Word) Word {
    return lex.strConv(if (pid == -1) "cannot create process\n" else "cannot open pipe\n");
}

/// Structurally compare two values (`<0`/`0`/`>0`); errors on comparing functions.
///
/// Tests: compare: orders ints, chars, and strings; 0 on equal
pub fn compare(arg_a: Word, arg_b: Word) c_int {
    var a = arg_a;
    var b = arg_b;
    while (true) {
        const tag_a = getTag(a);
        const tag_b = getTag(b);
        switch (tag_a) {
            .DOUBLE => {
                if (tag_b == .DOUBLE) {
                    return fsign(heap.getDbl(a) - heap.getDbl(b));
                } else {
                    return fsign(heap.getDbl(a) - big.toFloat(heap.heap, b));
                }
            },
            .INT => {
                if (tag_b == .INT) {
                    return big.cmp(heap.heap, a, b);
                } else {
                    return fsign(big.toFloat(heap.heap, a) - heap.getDbl(b));
                }
            },
            .UNICODE => {
                return sign(heap.getChar(a) - heap.getChar(b));
            },
            .ATOM => {
                if (tag_b == .UNICODE) {
                    return sign(heap.getChar(a) - heap.getChar(b));
                }
                if ((word.S <= a and a <= word.ERROR) or (word.S <= b and b <= word.ERROR)) {
                    fnError("attempt to compare functions");
                }
                if (tag_b == .ATOM) {
                    return sign(a - b);
                }
                return -1;
            },
            .CONSTRUCTOR => {
                if (tag_b == .CONSTRUCTOR) {
                    return sign(h(a) - h(b));
                } else {
                    return -1;
                }
            },
            .CONS, .AP => {
                if (tag_a == tag_b) {
                    hp(a).* = reduce(h(a));
                    hp(b).* = reduce(h(b));
                    const temp = compare(h(a), h(b));
                    if (temp != 0) {
                        return temp;
                    }
                    tp(a).* = reduce(t(a));
                    a = t(a);
                    tp(b).* = reduce(t(b));
                    b = t(b);
                    continue;
                } else if (word.S <= b and b <= word.ERROR) {
                    fnError("attempt to compare functions");
                } else {
                    return 1;
                }
            },
            else => {
                word.printErr("\nghastly error in compare\n", .{});
            },
        }
        return 0;
    }
}

test "compare: orders ints, chars, and strings; 0 on equal" {
    tu.freshInterp();
    try std.testing.expect(compare(big.fromInt(heap.heap, 2), big.fromInt(heap.heap, 3)) < 0);
    try std.testing.expect(compare(big.fromInt(heap.heap, 3), big.fromInt(heap.heap, 2)) > 0);
    try std.testing.expectEqual(@as(c_int, 0), compare(big.fromInt(heap.heap, 7), big.fromInt(heap.heap, 7)));
    // strings (char lists) compare lexicographically, element by element
    try std.testing.expect(compare(tu.str("abc"), tu.str("abd")) < 0);
    try std.testing.expectEqual(@as(c_int, 0), compare(tu.str("hi"), tu.str("hi")));
}

/// Fully evaluate `x` to normal form (deep `reduce`), descending applications and conses.
///
/// Tests: force: deep-evaluates a list of thunks to normal form
pub fn force(x_val: Word) void {
    var x = x_val;
    switch (getTag(x)) {
        .AP => {
            var curr_h = h(x);
            while (getTag(curr_h) == .AP) {
                curr_h = h(curr_h);
            }
            if (word.S <= curr_h and curr_h <= word.ERROR) {
                return;
            }
            while (getTag(x) == .AP) {
                tp(x).* = reduce(t(x));
                force(t(x));
                x = h(x);
            }
            return;
        },
        .CONS => {
            while (getTag(x) == .CONS) {
                hp(x).* = reduce(h(x));
                force(h(x));
                tp(x).* = reduce(t(x));
                x = t(x);
            }
        },
        else => {},
    }
}

test "force: deep-evaluates a list of thunks to normal form" {
    tu.freshInterp();
    const thunk = ap(ap(word.PLUS, big.fromInt(heap.heap, 2)), big.fromInt(heap.heap, 3));
    const lst = cons(thunk, NIL);
    force(lst);
    // the head thunk is now reduced to the INT 5 in place
    try std.testing.expectEqual(@as(c_longlong, 5), big.toInt(heap.heap, h(lst)));
}

/// The head atom/combinator at the end of a left spine of applications.
///
/// Tests: head: the leftmost atom of an application spine
pub fn head(x_val: Word) Word {
    var x = x_val;
    while (getTag(x) == .AP) {
        x = h(x);
    }
    return x;
}

test "head: the leftmost atom of an application spine" {
    tu.freshInterp();
    // ((K True) False) → head is K
    const g = ap(ap(word.K, word.True), word.False);
    try std.testing.expectEqual(@as(Word, word.K), head(g));
    // a bare atom is its own head
    try std.testing.expectEqual(@as(Word, word.I), head(word.I));
}

/// Open `f` for appending (the `Appendfile` directive), recording it in the open-file list.
pub fn apfile(f: Word) void {
    var p = ev.outfilq;
    const fil = getstring(f, "Appendfile");
    while (p != NIL and word.strcmp(strtab.strOf(strtab.table, h(h(p))), fil) != 0) {
        p = t(p);
    }
    if (p == NIL) {
        const s = word.fopen(fil, "a");
        if (s == null) {
            word.printErr("\nAppendfile: cannot write to \"{s}\"\n", .{std.mem.span(fil.?)});
        } else {
            // datapair = (filename string, FILE* handle); the FILE* is a
            // raw cell cast (read back via @ptrFromInt), not a node string.
            ev.outfilq = cons(datapair(strtab.strBits(strtab.table, lex.keep(fil.?)), @as(Word, @intCast(@intFromPtr(s.?)))), ev.outfilq);
        }
    }
}

/// Close the output file named by `f` (the `Closefile` directive).
pub fn closefile(f: Word) void {
    var p = &ev.outfilq;
    const fil = getstring(f, "Closefile");
    while (p.* != NIL and word.strcmp(strtab.strOf(strtab.table, h(h(p.*))), fil) != 0) {
        p = tp(p.*);
    }
    if (p.* != NIL) {
        _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(h(p.*))))));
        p.* = t(p.*);
    }
}

/// Switch output to the file named in `e` (the `Tofile` directive), opening it if needed.
pub fn outf(e: Word) void {
    var p = ev.outfilq;
    const f = getstring(t(h(e)), "Tofile");
    while (p != NIL and word.strcmp(strtab.strOf(strtab.table, h(h(p))), f) != 0) {
        p = t(p);
    }
    if (p == NIL) {
        ev.s_out = word.fopen(f, "w");
        if (ev.s_out == null) {
            word.printErr("\nTofile: cannot write to \"{s}\"\n", .{std.mem.span(f.?)});
            ev.s_out = getStdout();
            return;
        }
        if (main_clib.isatty(word.fileno(ev.s_out.?)) != 0) {
            word.setbuf(ev.s_out.?, null);
        }
        // datapair = (filename string, FILE* handle); FILE* is a raw cell cast.
        ev.outfilq = cons(datapair(strtab.strBits(strtab.table, lex.keep(f.?)), @as(Word, @intCast(@intFromPtr(ev.s_out.?)))), ev.outfilq);
    } else {
        ev.s_out = @ptrFromInt(@as(usize, @intCast(t(h(p)))));
    }
}

/// Print a Miranda char-list to the current output stream (`ev.s_out`), honouring UTF-8.
pub fn print(arg_e: Word) void {
    var e = reduce(arg_e);
    while (getTag(e) == .CONS) {
        hp(e).* = reduce(h(e));
        if (!heap.isChar(h(e))) {
            break;
        }
        const c = @as(u32, @intCast(heap.getChar(h(e))));
        if (rt.rs.UTF8 != 0) {
            main_clib.outUTF8(c, ev.s_out);
        } else if (word.fitsInByte(c)) {
            _ = word.putc(@intCast(c), ev.s_out.?);
        } else {
            word.printErr("\n warning: non Latin1 char {x} in print, ignored\n", .{c});
        }
        tp(e).* = reduce(t(e));
        e = t(e);
    }
    if (e == NIL) {
        return;
    }
    word.printErr("\nimpossible event in print\n", .{});
    _ = word.putc('<', getStderr().?);
    heap.outTerm(getStderr().?, e);
    word.printErr(">\n", .{});
    main_clib.exit(1);
}

const Stdout = 0;
const Stderr = 1;
const Tofile = 2;
const Closefile = 3;
const Appendfile = 4;
const System = 5;
const Exit = 6;
const Stdoutb = 7;
const Tofileb = 8;
const Appendfileb = 9;

/// Drive a list of output directives (`Stdout`/`Tofile`/`System`/`Exit`/…) — the top of the I/O interpreter.
pub fn output(arg_e: Word) void {
    var e = arg_e;
    const old_cstack = rt.rs.cstack;
    rt.rs.cstack = @ptrCast(&e);
    defer rt.rs.cstack = old_cstack;

    e = reduce(e);
    while (getTag(e) == .CONS) {
        hp(e).* = reduce(h(e));
        switch (h(head(h(e)))) {
            Stdout => {
                print(t(h(e)));
            },
            Stdoutb => {
                rt.rs.UTF8OUT = 0;
                print(t(h(e)));
                rt.rs.UTF8OUT = rt.rs.UTF8;
            },
            Stderr => {
                ev.s_out = getStderr();
                print(t(h(e)));
                ev.s_out = getStdout();
            },
            Tofile => {
                outf(h(e));
            },
            Tofileb => {
                rt.rs.UTF8OUT = 0;
                outf(h(e));
                rt.rs.UTF8OUT = rt.rs.UTF8;
            },
            Closefile => {
                tp(h(e)).* = reduce(t(h(e)));
                closefile(t(h(e)));
            },
            Appendfile => {
                tp(h(e)).* = reduce(t(h(e)));
                apfile(t(h(e)));
            },
            Appendfileb => {
                rt.rs.UTF8OUT = 0;
                tp(h(e)).* = reduce(t(h(e)));
                apfile(t(h(e)));
                rt.rs.UTF8OUT = rt.rs.UTF8;
            },
            System => {
                tp(h(e)).* = reduce(t(h(e)));
                const cmd = getstring(t(h(e)), "System");
                _ = main_clib.system(cmd);
            },
            Exit => {
                var n = reduce(t(h(e)));
                if (getTag(n) == .INT) {
                    n = digit0(n);
                } else {
                    intError("Exit");
                }
                outstats();
                main_clib.exit(@intCast(n));
            },
            else => {
                word.printErr("\n<impossible event in output list: ", .{});
                heap.outTerm(getStderr().?, h(e));
                word.printErr(">\n", .{});
            },
        }
        tp(e).* = reduce(t(e));
        e = t(e);
    }
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap.validate();
    }
    if (e == NIL) {
        return;
    }
    word.printErr("\nimpossible event in output\n", .{});
    _ = word.putc('<', getStderr().?);
    heap.outTerm(getStderr().?, e);
    word.printErr(">\n", .{});
    main_clib.exit(1);
}

comptime {
    @setEvalBranchQuota(50000);
    _ = @import("reducer/reduce.zig");
    _ = @import("reducer/combinators.zig");
    _ = @import("reducer/ready.zig");
    _ = @import("reducer/io.zig");
    _ = @import("reducer/lex.zig");
}
