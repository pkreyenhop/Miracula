//! reduce_rt.zig (renamed from runtime/reduce.zig, Phase 4 step 1,
//! docs/GO_PORT_PLAN.md — the name collided with `reducer/reduce.zig`,
//! the dispatch engine itself, once both moved under `eval/`) — runtime
//! support around the reduction engine.
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
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const platform = @import("../io/platform.zig");
const rt = @import("../runtime/runtime_state.zig");
const heap = @import("../graph/heap.zig");
const print_mod = @import("../graph/print.zig");
const repl = @import("../session/repl.zig");
const engine = @import("reduce.zig");
const reducer_trace = @import("trace.zig");
const spine = @import("spine.zig");
const big = @import("../graph/bignum.zig");
const lex = @import("../parser/lex.zig");
const os = @import("../os.zig");
const core_state = @import("../runtime/core_state.zig");
const lex_state = @import("../parser/lex_state.zig");
const reduce_core = @import("reduce_core.zig");
const Value = reduce_core.Value;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;
const NIL: Word = word.CMBASE + 138;
const FST = word.HD;
const MAXDIGIT = 0x7fff;
const SIGNBIT = 0x10000000;

/// Evaluation / reducer-I/O state (shared-state plan Phase 2d). Accessed as
/// `reduce.ev().X`; folds into `Interp.eval` in Phase 3.
pub const EvalState = struct {
    /// How stdin is currently bound (0 = free, ':' = text read, '-' = binary).
    stdinuse: Word = 0,
    /// Queue of open output files (`Tofile`/`Appendfile`).
    outfilq: Word = NIL,
    /// List of child processes awaiting `wait`.
    waiting: Word = NIL,
    /// Current `Tofile` output stream.
    s_out: ?*word.Stream = null,
    /// Evaluation-error recovery trap.
    errtrap: Word = 0,
    /// Reduction-step counter (the perf metric reported by `outstats`).
    cycles: i64 = 0,
    /// Per-combinator step histogram (`-Dreduce-trace`; zero-overhead when off).
    trace: reducer_trace.TraceState = .{},
    /// Free-list of previously-`deinit`ed `Spine` frame buffers, reused by
    /// `Spine.init` (see its doc for why this matters for `reduce()`'s
    /// per-call allocation cost).
    spine_buffer_pool: spine.BufferPool = .empty,
    /// Head of the singly-linked list of currently-registered `Spine`s (see
    /// `Spine.register`/`unregister` and `Heap.bases`'s GC-root marking).
    gc_roots_head: ?*spine.Spine = null,
};

/// Pointer to the evaluator state held in `current_interp` (so `interp.reset()`
/// clears it). Accessed as `ev().X`.
pub inline fn ev() *EvalState {
    return &@import("../session/interp.zig").current_interp.eval;
}

const stoChar = heap.stoChar;
extern fn fromUTF8(f: ?*word.Stream) Word;
const parseLine = repl.parseLine;
const reduce = engine.reduce;
const charname = print_mod.charname;

inline fn getTag(heap_ptr: *heap.Heap, x: Word) word.NodeTag {
    return heap_ptr.getTag(x);
}

inline fn setTag(heap_ptr: *heap.Heap, x: Word, val: word.NodeTag) void {
    heap_ptr.setTag(x, val);
}

inline fn h(heap_ptr: *heap.Heap, x: Word) Word {
    return heap_ptr.h(x);
}

inline fn t(heap_ptr: *heap.Heap, x: Word) Word {
    return heap_ptr.t(x);
}

inline fn hp(heap_ptr: *heap.Heap, x: Word) *Word {
    return heap_ptr.hp(x);
}

inline fn tp(heap_ptr: *heap.Heap, x: Word) *Word {
    return heap_ptr.tp(x);
}

inline fn lh(heap_ptr: *heap.Heap, x: Word) Word {
    if (getTag(heap_ptr, h(heap_ptr, x)) == .STRCONS) {
        return t(heap_ptr, h(heap_ptr, x));
    } else {
        return h(heap_ptr, x);
    }
}

inline fn forceDbl(heap_ptr: *heap.Heap, x: Word) f64 {
    if (getTag(heap_ptr, x) == .INT) {
        return big.toFloat(heap_ptr, x);
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

inline fn cons(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .CONS, x, y);
}

inline fn ap(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .AP, x, y);
}

inline fn datapair(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .DATAPAIR, x, y);
}

/// Wrap a raw native pointer (already cast to a `Word` via `@intFromPtr`) as
/// a GC-safe heap value, for storing in a cell field that `Heap.mark`/
/// `Heap.validate` might otherwise walk as if it were a cell reference.
///
/// `fileq`/`outfilq`'s entries have always stashed a `Stream*` this way (as a
/// `DATAPAIR`'s second field, alongside a filename) precisely because
/// `DATAPAIR`'s tag ordinal sits below both thresholds `mark`/`validate`
/// use to decide whether to recurse into a cell's hd/tl — so a raw pointer
/// there can never be mistaken for an out-of-range cell index. `streamRead`/
/// `STARTREADVALS`, however, wrote the raw pointer directly into an `AP`
/// cell's tail (reusing the reduction spine's own cell rather than
/// allocating a dedicated one) — `AP`'s ordinal is above both thresholds,
/// so any GC landing while that cell was reachable would try to chase the
/// pointer bit pattern as a cell reference and panic (`heap.validate:
/// cell ... has out-of-bounds tl reference ...`). Confirmed via `readvals`,
/// whose per-value reentrant parse+codegen+typecheck+fork cycle allocates
/// enough to make hitting this nearly certain; `read`/`readb` have the
/// identical hazard, just rarely unlucky enough to land a GC mid-stream.
/// `wrapPtr` extends the same established `fileq`/`outfilq` pattern to
/// these call sites instead of inventing a new one.
pub fn wrapPtr(heap_ptr: *heap.Heap, raw: Word) Value {
    return Value.fromRaw(datapair(heap_ptr, 0, raw));
}

/// Undo `wrapPtr`: read the raw pointer word back out of the wrapper cell.
pub fn unwrapPtr(heap_ptr: *heap.Heap, wrapped_val: Value) Word {
    return t(heap_ptr, wrapped_val.toRaw());
}

inline fn digit0(heap_ptr: *heap.Heap, x: Word) Word {
    return h(heap_ptr, x) & MAXDIGIT;
}

inline fn stosmallint(heap_ptr: *heap.Heap, x: Word) Word {
    const val = if (x < 0) SIGNBIT | (-x) else x;
    return heap.make(heap_ptr, .INT, val, 0);
}

/// The standard-input `Stream*` handle.
fn getStdin() ?*word.Stream {
    const T = @TypeOf(os.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdin();
    } else {
        return os.stdin;
    }
}

/// The standard-error `Stream*` handle.
fn getStderr() ?*word.Stream {
    const T = @TypeOf(os.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stderr();
    } else {
        return os.stderr;
    }
}

/// The standard-output `Stream*` handle.
fn getStdout() ?*word.Stream {
    const T = @TypeOf(os.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdout();
    } else {
        return os.stdout;
    }
}

inline fn rewriteToValue(heap_ptr: *heap.Heap, expr: *Word, value: Word) void {
    hp(heap_ptr, expr.*).* = word.I;
    tp(heap_ptr, expr.*).* = value;
    expr.* = value;
}

inline fn rewriteToNil(heap_ptr: *heap.Heap, expr: *Word) void {
    rewriteToValue(heap_ptr, expr, NIL);
}

inline fn setcell(heap_ptr: *heap.Heap, e: Word, t_val: word.NodeTag, a: Word, b: Word) void {
    setTag(heap_ptr, e, t_val);
    hp(heap_ptr, e).* = a;
    tp(heap_ptr, e).* = b;
}

inline fn rewriteToCons(heap_ptr: *heap.Heap, e: Word, hd_value: Word, tl_value: Word) void {
    setcell(heap_ptr, e, .CONS, hd_value, tl_value);
}

/// Abort with "missing case in definition" — the `BADCASE` combinator's reporter.
pub fn badcaseError(heap_ptr: *heap.Heap, arg_info_val: Value) reduce_core.ReduceError!void {
    const arg_info = arg_info_val.toRaw();
    const subject = h(heap_ptr, arg_info);
    word.printErr("\nprogram error: missing case in definition", .{});
    if (subject != 0) {
        word.printErr(" of {s}", .{std.mem.span((try getstring(heap_ptr, Value.fromRaw(subject), null)).?)});
    }
    _ = word.putc('\n', getStderr().?);
    outHere(heap_ptr, core_state.s(), getStderr().?, Value.fromRaw(t(heap_ptr, arg_info)), 1);
    outstats();
    os.exit(1);
}

/// Abort with "lhs of definition doesn't match rhs" (a conformality error).
pub fn confError(heap_ptr: *heap.Heap, arg_info_val: Value) void {
    const arg_info = arg_info_val.toRaw();
    word.printErr("\nprogram error: lhs of definition doesn't match rhs\n", .{});
    outHere(heap_ptr, core_state.s(), getStderr().?, Value.fromRaw(t(heap_ptr, arg_info)), 1);
    outstats();
    os.exit(1);
}

/// Abort a failed `$$`-grammar parse, reporting the unexpected token (or end of input).
pub fn parseCloseError(heap_ptr: *heap.Heap, arg1_val: Value, arg3_val: Value) reduce_core.ReduceError!void {
    const arg1 = arg1_val.toRaw();
    word.printErr("\nPARSE OF {s}FAILS WITH UNEXPECTED ", .{std.mem.span((try getstring(heap_ptr, Value.fromRaw(arg1), null)).?)});
    const arg3_reduced = try reduce(heap_ptr, t(heap_ptr, gResidue(heap_ptr, arg3_val).toRaw()));
    if (arg3_reduced == NIL) {
        word.printErr("END OF INPUT\n", .{});
        outstats();
        os.exit(1);
    }
    var hold_val = heap.make(heap_ptr, .AP, FST, h(heap_ptr, arg3_reduced));
    hold_val = try reduce(heap_ptr, hold_val);
    word.printErr("TOKEN \"", .{});
    if (hold_val == word.OFFSIDE) {
        word.printErr("offside", .{});
    }
    const p = try getstring(heap_ptr, Value.fromRaw(hold_val), null);
    if (p) |ptr| {
        var i: usize = 0;
        while (ptr[i] != 0) : (i += 1) {
            word.printErr("{s}", .{charname(heap_ptr, ptr[i])});
        }
    }
    word.printErr("\"\n", .{});
    outstats();
    os.exit(1);
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
    // `ctx.e`/`.args` are `Value` (Phase 5 step 4); this function's own
    // `t`/`h`/`tp`/`rewriteToNil`/`rewriteToCons` above are reduce_rt.zig's
    // private `Word`-typed duplicates (see this file's own module doc: kept
    // in lock-step with reduce_core.zig's versions, not shared with them),
    // so every touch of `ctx.e`/`.args` here converts at the boundary
    // (`.toRaw()`/`Value.fromRaw()`/`@ptrCast` for the one `*Word` out-param).
    switch (op) {
        word.READBIN => {
            reduce_core.upLeft(ctx);
            const lastarg = t(ctx.heap, ctx.e.toRaw());

            if (lastarg == 0) {
                if (ctx.eval.stdinuse == '-') {
                    stdinError(ctx.eval, ':');
                }
                if (ctx.eval.stdinuse != 0) {
                    rewriteToNil(ctx.heap, @ptrCast(&ctx.e));
                    return word.ACT_DONE;
                }
                ctx.eval.stdinuse = ':';
                tp(ctx.heap, ctx.e.toRaw()).* = wrapPtr(ctx.heap, @intCast(@intFromPtr(getStdin().?))).toRaw();
            }
            const hold_char = os.getc(@ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(t(ctx.heap, ctx.e.toRaw())))))));
            if (hold_char == os.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(t(ctx.heap, ctx.e.toRaw())))))));
                rewriteToNil(ctx.heap, @ptrCast(&ctx.e));
                return word.ACT_DONE;
            }
            rewriteToCons(ctx.heap, ctx.e.toRaw(), hold_char, heap.make(ctx.heap, .AP, word.READBIN, t(ctx.heap, ctx.e.toRaw())));
            return word.ACT_DONE;
        },
        word.READ => {
            reduce_core.upLeft(ctx);
            const lastarg = t(ctx.heap, ctx.e.toRaw());

            if (lastarg == 0) {
                if (ctx.eval.stdinuse == ':') {
                    stdinError(ctx.eval, '-');
                }
                if (ctx.eval.stdinuse != 0) {
                    rewriteToNil(ctx.heap, @ptrCast(&ctx.e));
                    return word.ACT_DONE;
                }
                ctx.eval.stdinuse = '-';
                tp(ctx.heap, ctx.e.toRaw()).* = wrapPtr(ctx.heap, @intCast(@intFromPtr(getStdin().?))).toRaw();
            }
            const hold_char = if (ctx.rs.UTF8 != 0) stoChar(fromUTF8(@ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(t(ctx.heap, ctx.e.toRaw())))))))) else os.getc(@ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(t(ctx.heap, ctx.e.toRaw())))))));
            if (hold_char == os.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(t(ctx.heap, ctx.e.toRaw())))))));
                rewriteToNil(ctx.heap, @ptrCast(&ctx.e));
                return word.ACT_DONE;
            }
            rewriteToCons(ctx.heap, ctx.e.toRaw(), hold_char, heap.make(ctx.heap, .AP, word.READ, t(ctx.heap, ctx.e.toRaw())));
            return word.ACT_DONE;
        },
        word.READVALS => {
            reduce_core.upLeft(ctx); // GETARG(arg1)
            ctx.args[0] = Value.fromRaw(t(ctx.heap, ctx.e.toRaw()));

            if (ctx.spine.isEmpty()) return word.ACT_DONE;

            reduce_core.upLeft(ctx);
            const lastarg = t(ctx.heap, ctx.e.toRaw());

            const val = parseLine(ctx.heap, core_state.s(), rt.rs(), lex_state.ls(), h(ctx.heap, ctx.args[0].toRaw()), @ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(lastarg))))), t(ctx.heap, ctx.args[0].toRaw()));
            if (val == os.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(unwrapPtr(ctx.heap, Value.fromRaw(lastarg))))));
                rewriteToNil(ctx.heap, @ptrCast(&ctx.e));
                return word.ACT_DONE;
            }
            ctx.args[1] = Value.fromRaw(heap.make(ctx.heap, .AP, h(ctx.heap, ctx.e.toRaw()), lastarg));
            rewriteToCons(ctx.heap, ctx.e.toRaw(), val, ctx.args[1].toRaw());
            return word.ACT_DONE;
        },
        else => return word.ACT_NONE,
    }
}

/// Flatten a Miranda char-list `x` into a NUL-terminated C string in `linebuf`; aborts via `cmd` if it exceeds 1024 chars.
///
/// Tests: getstring: copies a char list into a C-string
pub fn getstring(heap_ptr: *heap.Heap, x_val: Value, cmd: ?[*:0]const u8) reduce_core.ReduceError!?[*:0]u8 {
    const x = x_val.toRaw();
    var curr_x = x;
    const x1 = x;
    var n: usize = 0;
    const buf_size = 1024;
    while (getTag(heap_ptr, curr_x) == .CONS and n < buf_size) {
        n += 1;
        hp(heap_ptr, curr_x).* = try reduce(heap_ptr, h(heap_ptr, curr_x));
        tp(heap_ptr, curr_x).* = try reduce(heap_ptr, t(heap_ptr, curr_x));
        curr_x = t(heap_ptr, curr_x);
    }
    curr_x = x1;
    var p_idx: usize = 0;
    while (getTag(heap_ptr, curr_x) == .CONS and n > 0) {
        n -= 1;
        rt.rs().linebuf[p_idx] = @intCast(h(heap_ptr, curr_x));
        p_idx += 1;
        curr_x = t(heap_ptr, curr_x);
    }
    rt.rs().linebuf[p_idx] = 0;
    p_idx += 1;
    if (p_idx > buf_size) {
        if (cmd) |cmd_str| {
            word.printErr("\n{s}, argument string too long (limit={} chars): {s}...\n", .{ cmd_str, @as(c_int, buf_size), &rt.rs().linebuf });
            outstats();
            os.exit(1);
        } else {
            return @ptrCast(&rt.rs().linebuf);
        }
    }
    return @ptrCast(&rt.rs().linebuf);
}

test "getstring: copies a char list into a C-string" {
    tu.freshInterp();
    const s = try getstring(heap.heap(), Value.fromRaw(tu.str("hello")), null);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("hello", std.mem.span(@as([*:0]const u8, s.?)));
}

/// Reset the reduction clock (currently a no-op stub).
pub fn initclock() void {}

/// Print the end-of-evaluation statistics (reductions, cells, GC) when enabled.
pub fn outstats() void {
    reducer_trace.dump(&ev().trace); // per-combinator trace (no-op unless -Dreduce-trace)
    if (rt.rs().atcount == 0) {
        return;
    }
    var buffer: os.struct_tms = undefined;
    _ = os.times(&buffer);
    word.printErr("||", .{});
    word.printErr("reductions = {}, cells claimed = {}, ", .{ ev().cycles, heap.heap().cellcount + heap.heap().claims });
    const clk_tck = @as(f64, @floatFromInt(os.sysconf(word._SC_CLK_TCK)));
    word.printErr("no of gc's = {}, cpu = {d:.2}\n", .{ heap.heap().nogcs, @as(f64, @floatFromInt(buffer.tms_utime)) / clk_tck });
}

/// Write value `h_val` to file `f` for diagnostics, optionally followed by a newline.
pub fn outHere(heap_ptr: *heap.Heap, core: *core_state.CoreState, f: ?*word.Stream, h_val_arg: Value, nl: c_int) void {
    const h_val = h_val_arg.toRaw();
    if (getTag(heap_ptr, h_val) != .FILEINFO) {
        word.printErr("(impossible event in outhere)\n", .{});
        return;
    }
    f.?.print("(line {d:>3} of \"{s}\")", .{.{ t(heap_ptr, h_val), strtab.strOf(strtab.table(), h(heap_ptr, h_val)) }});
    if (nl != 0) {
        _ = word.putc('\n', f.?);
    } else {
        _ = word.putc(' ', f.?);
    }
    if (core.compiling != 0 and core.errs == 0) {
        core.errs = h_val;
    }
}

/// Human-readable name of a standard-stream selector.
fn stdname(c_val: c_int) [*:0]const u8 {
    return if (c_val == ':') "$:-" else if (c_val == '-') "$-" else "$+";
}

/// Abort: stdin was read both as characters and as values (the `-`/`:` conflict).
pub fn stdinError(eval: *EvalState, c_val: c_int) void {
    if (eval.stdinuse == c_val) {
        word.printErr("program error: duplicate use of {s}\n", .{stdname(c_val)});
    } else {
        word.printErr("program error: simultaneous use of {s} and {s}\n", .{ stdname(c_val), stdname(@intCast(eval.stdinuse)) });
    }
    outstats();
    os.exit(1);
}

/// Abort with the function-related runtime error message `s`.
pub fn fnError(s: [*:0]const u8) void {
    word.printErr("\nprogram error: {s}\n", .{s});
    outstats();
    os.exit(1);
}

/// Warn that environment variable `a` holds a non-Latin-1 value.
pub fn getenvError(a: [*:0]const u8) void {
    word.printErr("program error: getenv({s}): illegal characters in result string\n", .{a});
    outstats();
    os.exit(1);
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
    const err_type: [*:0]const u8 = if (err_val == os.EDOM) "domain " else if (err_val == os.ERANGE) "range " else "";
    word.printErr("\nmath function {s}error ({s})\n", .{ err_type, s });
    outstats();
    os.exit(1);
}

/// Abort: operation `s` requires an integer argument.
pub fn intError(s: [*:0]const u8) void {
    word.printErr("\nprogram error: fractional number where integer expected ({s})\n", .{s});
    outstats();
    os.exit(1);
}

/// Add `x + y`, promoting to `f64` if either is a `DOUBLE`, else bignum add.
///
/// Tests: numplus: integer add and float promotion
pub fn numplus(heap_ptr: *heap.Heap, x_val: Value, y_val: Value) word.ReduceError!Word {
    const x = x_val.toRaw();
    const y = y_val.toRaw();
    if (getTag(heap_ptr, x) == .DOUBLE) {
        return heap.stoDbl(heap.getDbl(x) + forceDbl(heap_ptr, y));
    }
    if (getTag(heap_ptr, y) == .DOUBLE) {
        return heap.stoDbl(big.toFloat(heap_ptr, x) + heap.getDbl(y));
    }
    return big.add(heap_ptr, x, y);
}

test "numplus: integer add and float promotion" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(c_longlong, 5), big.toInt(heap.heap(), try numplus(heap.heap(), Value.fromRaw(big.fromInt(heap.heap(), 2)), Value.fromRaw(big.fromInt(heap.heap(), 3)))));
    try std.testing.expectEqual(@as(c_longlong, -1), big.toInt(heap.heap(), try numplus(heap.heap(), Value.fromRaw(big.fromInt(heap.heap(), 2)), Value.fromRaw(big.fromInt(heap.heap(), -3)))));
    const r = try numplus(heap.heap(), Value.fromRaw(try heap.stoDbl(1.5)), Value.fromRaw(big.fromInt(heap.heap(), 2))); // DOUBLE + INT → DOUBLE
    try std.testing.expectEqual(word.NodeTag.DOUBLE, heap.getTag(heap.heap(), r));
    try std.testing.expectEqual(@as(f64, 3.5), heap.getDbl(r));
}

/// The residual (unconsumed) token list after a grammar parse, reversed via `DESTREV`.
pub fn gResidue(heap_ptr: *heap.Heap, toks2_val: Value) Value {
    return Value.fromRaw(gResidueRaw(heap_ptr, toks2_val.toRaw()));
}

fn gResidueRaw(heap_ptr: *heap.Heap, toks2: Word) Word {
    var curr_toks2 = toks2;
    var toks1 = NIL;
    if (getTag(heap_ptr, curr_toks2) != .CONS) {
        if (getTag(heap_ptr, curr_toks2) == .AP and h(heap_ptr, curr_toks2) == word.I and t(heap_ptr, curr_toks2) == NIL) {
            return cons(heap_ptr, NIL, NIL);
        }
        return cons(heap_ptr, NIL, curr_toks2);
    }
    while (getTag(heap_ptr, t(heap_ptr, curr_toks2)) == .CONS) {
        toks1 = cons(heap_ptr, h(heap_ptr, curr_toks2), toks1);
        curr_toks2 = t(heap_ptr, curr_toks2);
    }
    if (t(heap_ptr, curr_toks2) == NIL or (getTag(heap_ptr, t(heap_ptr, curr_toks2)) == .AP and h(heap_ptr, t(heap_ptr, curr_toks2)) == word.I and t(heap_ptr, t(heap_ptr, curr_toks2)) == NIL)) {
        toks1 = cons(heap_ptr, h(heap_ptr, curr_toks2), toks1);
        return cons(heap_ptr, ap(heap_ptr, word.DESTREV, toks1), NIL);
    }
    return cons(heap_ptr, ap(heap_ptr, word.DESTREV, toks1), t(heap_ptr, curr_toks2));
}

/// 1 if character `c_val` is in the lexer character-class list `x_val` (handles `..` ranges).
///
/// Tests: memclass: character-class membership with ranges
pub fn memclass(heap_ptr: *heap.Heap, c_val: c_int, x_arg: Value) c_int {
    var x = x_arg.toRaw();
    while (x != NIL) {
        if (h(heap_ptr, x) == word.DOTDOT) {
            x = t(heap_ptr, x);
            if (h(heap_ptr, x) <= c_val and c_val <= h(heap_ptr, t(heap_ptr, x))) {
                return 1;
            }
            x = t(heap_ptr, x);
        } else if (c_val == h(heap_ptr, x)) {
            return 1;
        }
        x = t(heap_ptr, x);
    }
    return 0;
}

test "memclass: character-class membership with ranges" {
    tu.freshInterp();
    // a range is encoded as [DOTDOT, low, high]
    const range = cons(heap.heap(), word.DOTDOT, cons(heap.heap(), 'a', cons(heap.heap(), 'z', NIL)));
    try std.testing.expectEqual(@as(c_int, 1), memclass(heap.heap(), 'm', Value.fromRaw(range)));
    try std.testing.expectEqual(@as(c_int, 0), memclass(heap.heap(), 'A', Value.fromRaw(range)));
    // a bare class member
    const single = cons(heap.heap(), 'x', NIL);
    try std.testing.expectEqual(@as(c_int, 1), memclass(heap.heap(), 'x', Value.fromRaw(single)));
    try std.testing.expectEqual(@as(c_int, 0), memclass(heap.heap(), 'y', Value.fromRaw(single)));
}

/// Abort: the lexer hit unrecognised input; prints up to 24 chars of context.
pub fn lexfail(heap_ptr: *heap.Heap, x_arg: Value) void {
    var x = x_arg.toRaw();
    var i: i32 = 24;
    word.printErr("\nLEX FAILS WITH UNRECOGNISED INPUT: \"", .{});
    while (i > 0 and x != NIL and 0 <= lh(heap_ptr, x) and lh(heap_ptr, x) <= 255) {
        i -= 1;
        word.printErr("{s}", .{charname(heap_ptr, @intCast(lh(heap_ptr, x)))});
        x = t(heap_ptr, x);
    }
    word.printErr("{s}\"\n", .{if (x == NIL) @as([*:0]const u8, "") else "..."});
    outstats();
    os.exit(1);
}

/// Split a packed lexer-state value into a `(hi . lo)` cons.
pub fn lexstate(heap_ptr: *heap.Heap, x_val: Value) Value {
    const x = x_val.toRaw();
    const val = h(heap_ptr, h(heap_ptr, x));
    return Value.fromRaw(cons(heap_ptr, big.fromInt(heap_ptr, val >> 8), stosmallint(heap_ptr, val & 255)));
}

/// The error message for a failed `fork`/pipe (used by `system`).
pub fn piperrmess(pid: Word) Value {
    return Value.fromRaw(lex.strConv(if (pid == -1) "cannot create process\n" else "cannot open pipe\n"));
}

/// Structurally compare two values (`<0`/`0`/`>0`); errors on comparing functions.
///
/// Tests: compare: orders ints, chars, and strings; 0 on equal
pub fn compare(heap_ptr: *heap.Heap, arg_a_val: Value, arg_b_val: Value) reduce_core.ReduceError!c_int {
    var a = arg_a_val.toRaw();
    var b = arg_b_val.toRaw();
    while (true) {
        const tag_a = getTag(heap_ptr, a);
        const tag_b = getTag(heap_ptr, b);
        switch (tag_a) {
            .DOUBLE => {
                if (tag_b == .DOUBLE) {
                    return fsign(heap.getDbl(a) - heap.getDbl(b));
                } else {
                    return fsign(heap.getDbl(a) - big.toFloat(heap_ptr, b));
                }
            },
            .INT => {
                if (tag_b == .INT) {
                    return big.cmp(heap_ptr, a, b);
                } else {
                    return fsign(big.toFloat(heap_ptr, a) - heap.getDbl(b));
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
                    return sign(h(heap_ptr, a) - h(heap_ptr, b));
                } else {
                    return -1;
                }
            },
            .CONS, .AP => {
                if (tag_a == tag_b) {
                    hp(heap_ptr, a).* = try reduce(heap_ptr, h(heap_ptr, a));
                    hp(heap_ptr, b).* = try reduce(heap_ptr, h(heap_ptr, b));
                    const temp = try compare(heap_ptr, Value.fromRaw(h(heap_ptr, a)), Value.fromRaw(h(heap_ptr, b)));
                    if (temp != 0) {
                        return temp;
                    }
                    tp(heap_ptr, a).* = try reduce(heap_ptr, t(heap_ptr, a));
                    a = t(heap_ptr, a);
                    tp(heap_ptr, b).* = try reduce(heap_ptr, t(heap_ptr, b));
                    b = t(heap_ptr, b);
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
    try std.testing.expect(try compare(heap.heap(), Value.fromRaw(big.fromInt(heap.heap(), 2)), Value.fromRaw(big.fromInt(heap.heap(), 3))) < 0);
    try std.testing.expect(try compare(heap.heap(), Value.fromRaw(big.fromInt(heap.heap(), 3)), Value.fromRaw(big.fromInt(heap.heap(), 2))) > 0);
    try std.testing.expectEqual(@as(c_int, 0), try compare(heap.heap(), Value.fromRaw(big.fromInt(heap.heap(), 7)), Value.fromRaw(big.fromInt(heap.heap(), 7))));
    // strings (char lists) compare lexicographically, element by element
    try std.testing.expect(try compare(heap.heap(), Value.fromRaw(tu.str("abc")), Value.fromRaw(tu.str("abd"))) < 0);
    try std.testing.expectEqual(@as(c_int, 0), try compare(heap.heap(), Value.fromRaw(tu.str("hi")), Value.fromRaw(tu.str("hi"))));
}

/// Fully evaluate `x` to normal form (deep `reduce`), descending applications and conses.
///
/// Tests: force: deep-evaluates a list of thunks to normal form
pub fn force(heap_ptr: *heap.Heap, x_val: Value) reduce_core.ReduceError!void {
    return forceRaw(heap_ptr, x_val.toRaw());
}

fn forceRaw(heap_ptr: *heap.Heap, x_val: Word) reduce_core.ReduceError!void {
    var x = x_val;
    switch (getTag(heap_ptr, x)) {
        .AP => {
            var curr_h = h(heap_ptr, x);
            while (getTag(heap_ptr, curr_h) == .AP) {
                curr_h = h(heap_ptr, curr_h);
            }
            if (word.S <= curr_h and curr_h <= word.ERROR) {
                return;
            }
            while (getTag(heap_ptr, x) == .AP) {
                tp(heap_ptr, x).* = try reduce(heap_ptr, t(heap_ptr, x));
                try forceRaw(heap_ptr, t(heap_ptr, x));
                x = h(heap_ptr, x);
            }
            return;
        },
        .CONS => {
            while (getTag(heap_ptr, x) == .CONS) {
                hp(heap_ptr, x).* = try reduce(heap_ptr, h(heap_ptr, x));
                try forceRaw(heap_ptr, h(heap_ptr, x));
                tp(heap_ptr, x).* = try reduce(heap_ptr, t(heap_ptr, x));
                x = t(heap_ptr, x);
            }
        },
        else => {},
    }
}

test "force: deep-evaluates a list of thunks to normal form" {
    tu.freshInterp();
    const thunk = ap(heap.heap(), ap(heap.heap(), word.PLUS, big.fromInt(heap.heap(), 2)), big.fromInt(heap.heap(), 3));
    const lst = cons(heap.heap(), thunk, NIL);
    try force(heap.heap(), Value.fromRaw(lst));
    // the head thunk is now reduced to the INT 5 in place
    try std.testing.expectEqual(@as(c_longlong, 5), big.toInt(heap.heap(), h(heap.heap(), lst)));
}

/// The head atom/combinator at the end of a left spine of applications.
///
/// Tests: head: the leftmost atom of an application spine
pub fn head(heap_ptr: *heap.Heap, x_val: Value) Value {
    var x = x_val.toRaw();
    while (getTag(heap_ptr, x) == .AP) {
        x = h(heap_ptr, x);
    }
    return Value.fromRaw(x);
}

test "head: the leftmost atom of an application spine" {
    tu.freshInterp();
    // ((K True) False) → head is K
    const g = ap(heap.heap(), ap(heap.heap(), word.K, word.True), word.False);
    try std.testing.expectEqual(@as(Word, word.K), head(heap.heap(), Value.fromRaw(g)).toRaw());
    // a bare atom is its own head
    try std.testing.expectEqual(@as(Word, word.I), head(heap.heap(), Value.fromRaw(word.I)).toRaw());
}

/// Open `f` for appending (the `Appendfile` directive), recording it in the open-file list.
pub fn apfile(heap_ptr: *heap.Heap, eval: *EvalState, f_val: Value) reduce_core.ReduceError!void {
    var p = eval.outfilq;
    const fil = try getstring(heap_ptr, f_val, "Appendfile");
    const fil_span = std.mem.span(fil.?);
    while (p != NIL and !std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), h(heap_ptr, h(heap_ptr, p)))), fil_span)) {
        p = t(heap_ptr, p);
    }
    if (p == NIL) {
        const s = word.fopen(fil, "a");
        if (s == null) {
            word.printErr("\nAppendfile: cannot write to \"{s}\"\n", .{std.mem.span(fil.?)});
        } else {
            // datapair = (filename string, Stream* handle); the Stream* is a
            // raw cell cast (read back via @ptrFromInt), not a node string.
            eval.outfilq = cons(heap_ptr, datapair(heap_ptr, strtab.strBits(strtab.table(), lex.keep(fil.?)), @as(Word, @intCast(@intFromPtr(s.?)))), eval.outfilq);
        }
    }
}

/// Close the output file named by `f` (the `Closefile` directive).
pub fn closefile(heap_ptr: *heap.Heap, eval: *EvalState, f_val: Value) reduce_core.ReduceError!void {
    var p = &eval.outfilq;
    const fil = try getstring(heap_ptr, f_val, "Closefile");
    const fil_span = std.mem.span(fil.?);
    while (p.* != NIL and !std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), h(heap_ptr, h(heap_ptr, p.*)))), fil_span)) {
        p = tp(heap_ptr, p.*);
    }
    if (p.* != NIL) {
        _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(heap_ptr, h(heap_ptr, p.*))))));
        p.* = t(heap_ptr, p.*);
    }
}

/// Switch output to the file named in `e` (the `Tofile` directive), opening it if needed.
pub fn outf(heap_ptr: *heap.Heap, eval: *EvalState, e_val: Value) reduce_core.ReduceError!void {
    const e = e_val.toRaw();
    var p = eval.outfilq;
    const f = try getstring(heap_ptr, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))), "Tofile");
    const f_span = std.mem.span(f.?);
    while (p != NIL and !std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), h(heap_ptr, h(heap_ptr, p)))), f_span)) {
        p = t(heap_ptr, p);
    }
    if (p == NIL) {
        eval.s_out = word.fopen(f, "w");
        if (eval.s_out == null) {
            word.printErr("\nTofile: cannot write to \"{s}\"\n", .{std.mem.span(f.?)});
            eval.s_out = getStdout();
            return;
        }
        if (os.isatty(word.fileno(eval.s_out.?)) != 0) {
            word.setbuf(eval.s_out.?, null);
        }
        // datapair = (filename string, Stream* handle); Stream* is a raw cell cast.
        eval.outfilq = cons(heap_ptr, datapair(heap_ptr, strtab.strBits(strtab.table(), lex.keep(f.?)), @as(Word, @intCast(@intFromPtr(eval.s_out.?)))), eval.outfilq);
    } else {
        eval.s_out = @ptrFromInt(@as(usize, @intCast(t(heap_ptr, h(heap_ptr, p)))));
    }
}

/// Print a Miranda char-list to the current output stream (`eval.s_out`), honouring UTF-8.
pub fn print(heap_ptr: *heap.Heap, eval: *EvalState, rs: *rt.RuntimeState, arg_e_val: Value) reduce_core.ReduceError!void {
    var e = try reduce(heap_ptr, arg_e_val.toRaw());
    while (getTag(heap_ptr, e) == .CONS) {
        hp(heap_ptr, e).* = try reduce(heap_ptr, h(heap_ptr, e));
        if (!heap.isChar(h(heap_ptr, e))) {
            break;
        }
        const c = @as(u32, @intCast(heap.getChar(h(heap_ptr, e))));
        if (rs.UTF8 != 0) {
            os.outUTF8(c, eval.s_out);
        } else if (word.fitsInByte(c)) {
            _ = word.putc(@intCast(c), eval.s_out.?);
        } else {
            word.printErr("\n warning: non Latin1 char {x} in print, ignored\n", .{c});
        }
        tp(heap_ptr, e).* = try reduce(heap_ptr, t(heap_ptr, e));
        e = t(heap_ptr, e);
    }
    if (e == NIL) {
        return;
    }
    word.printErr("\nimpossible event in print\n", .{});
    _ = word.putc('<', getStderr().?);
    print_mod.outTerm(heap_ptr, getStderr().?, e);
    word.printErr(">\n", .{});
    os.exit(1);
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
pub fn output(heap_ptr: *heap.Heap, eval: *EvalState, rs: *rt.RuntimeState, arg_e_val: Value) reduce_core.ReduceError!void {
    var e = arg_e_val.toRaw();
    const old_cstack = rs.cstack;
    rs.cstack = @ptrCast(&e);
    defer rs.cstack = old_cstack;

    e = try reduce(heap_ptr, e);
    while (getTag(heap_ptr, e) == .CONS) {
        hp(heap_ptr, e).* = try reduce(heap_ptr, h(heap_ptr, e));
        switch (h(heap_ptr, head(heap_ptr, Value.fromRaw(h(heap_ptr, e))).toRaw())) {
            Stdout => {
                try print(heap_ptr, eval, rs, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
            },
            Stdoutb => {
                rs.UTF8OUT = 0;
                try print(heap_ptr, eval, rs, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
                rs.UTF8OUT = rs.UTF8;
            },
            Stderr => {
                eval.s_out = getStderr();
                try print(heap_ptr, eval, rs, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
                eval.s_out = getStdout();
            },
            Tofile => {
                try outf(heap_ptr, eval, Value.fromRaw(h(heap_ptr, e)));
                try print(heap_ptr, eval, rs, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
            },
            Tofileb => {
                rs.UTF8OUT = 0;
                try outf(heap_ptr, eval, Value.fromRaw(h(heap_ptr, e)));
                try print(heap_ptr, eval, rs, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
                rs.UTF8OUT = rs.UTF8;
            },
            Closefile => {
                tp(heap_ptr, h(heap_ptr, e)).* = try reduce(heap_ptr, t(heap_ptr, h(heap_ptr, e)));
                try closefile(heap_ptr, eval, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
            },
            Appendfile => {
                tp(heap_ptr, h(heap_ptr, e)).* = try reduce(heap_ptr, t(heap_ptr, h(heap_ptr, e)));
                try apfile(heap_ptr, eval, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
            },
            Appendfileb => {
                rs.UTF8OUT = 0;
                tp(heap_ptr, h(heap_ptr, e)).* = try reduce(heap_ptr, t(heap_ptr, h(heap_ptr, e)));
                try apfile(heap_ptr, eval, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))));
                rs.UTF8OUT = rs.UTF8;
            },
            System => {
                tp(heap_ptr, h(heap_ptr, e)).* = try reduce(heap_ptr, t(heap_ptr, h(heap_ptr, e)));
                const cmd = try getstring(heap_ptr, Value.fromRaw(t(heap_ptr, h(heap_ptr, e))), "System");
                _ = os.system(cmd);
            },
            Exit => {
                var n = try reduce(heap_ptr, t(heap_ptr, h(heap_ptr, e)));
                if (getTag(heap_ptr, n) == .INT) {
                    n = digit0(heap_ptr, n);
                } else {
                    intError("Exit");
                }
                outstats();
                os.exit(@intCast(n));
            },
            else => {
                word.printErr("\n<impossible event in output list: ", .{});
                print_mod.outTerm(heap_ptr, getStderr().?, h(heap_ptr, e));
                word.printErr(">\n", .{});
            },
        }
        tp(heap_ptr, e).* = try reduce(heap_ptr, t(heap_ptr, e));
        e = t(heap_ptr, e);
    }
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap_ptr.validate();
    }
    if (e == NIL) {
        return;
    }
    word.printErr("\nimpossible event in output\n", .{});
    _ = word.putc('<', getStderr().?);
    print_mod.outTerm(heap_ptr, getStderr().?, e);
    word.printErr(">\n", .{});
    os.exit(1);
}

comptime {
    @setEvalBranchQuota(50000);
    _ = @import("reduce.zig");
    _ = @import("combinators/combinators.zig");
    _ = @import("combinators/ready.zig");
    _ = @import("combinators/io.zig");
    _ = @import("combinators/lex.zig");
}
