//! reducer/ready.zig — the "ready state" combinator dispatcher.
//!
//! `handleReadyState` is the heart of the reduction loop: once the spine is
//! unwound and a combinator has all of its arguments in hand, this routine
//! switches on the combinator tag and performs the rewrite — delegating the
//! arithmetic/list combinators to `combinators.zig`, input to `io.zig`, and the
//! lexer/grammar combinators to `reducer/lex.zig`. It is one very large switch,
//! hence the raised eval-branch quota.

const std = @import("std");
const options = @import("version_options");
const word = @import("../word.zig");
const reduce = @import("reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const platform = @import("../../io/platform.zig");
const combinators = @import("combinators.zig");
const io_handlers = @import("io.zig");
const rt = @import("../runtime_state.zig");
const big = @import("../big.zig");
const heap = @import("../heap.zig");
const lex = @import("../../parser/lex.zig");
const main_clib = @import("../main_clib.zig");
const reduce_rt = @import("../reduce.zig");

/// The current combinator's last (rightmost) argument: the tail of the focus node.
inline fn lastArg(ctx: *ReductionCtx) Word {
    return reduce.tlGet(ctx.heap, ctx.e);
}
/// Overwrite the focus node's last argument with `val`.
inline fn setLastArg(ctx: *ReductionCtx, val: Word) void {
    reduce.tlSet(ctx.heap, ctx.e, val);
}

/// A heap-stored character code, narrowed to a byte iff it's in ASCII-byte
/// range (Phase 2 step 5: heap cells are `Word`/`i64` and can hold values
/// outside 0-255, which `std.ascii`'s predicates can't accept directly).
inline fn charOfWord(w: Word) ?u8 {
    return if (w >= 0 and w <= 255) @intCast(w) else null;
}
inline fn isSpaceW(w: Word) bool {
    return if (charOfWord(w)) |b| std.ascii.isWhitespace(b) else false;
}
inline fn isDigitW(w: Word) bool {
    return if (charOfWord(w)) |b| std.ascii.isDigit(b) else false;
}
inline fn isHexW(w: Word) bool {
    return if (charOfWord(w)) |b| std.ascii.isHex(b) else false;
}
inline fn toLowerW(w: Word) u8 {
    return if (charOfWord(w)) |b| std.ascii.toLower(b) else 0;
}

/// Miranda's `shownum` on a double: the shortest decimal string that
/// round-trips exactly, with a guaranteed ".0" suffix if it would
/// otherwise look like an integer (`show 2.0` must print "2.0", not "2").
/// Verified byte-identical to the old `sprintf(..., "%.16g", ...)` path
/// across a range of representative values (both already delegated to
/// Zig's own `{d}` float formatter under the hood — `main_clib.zig`'s
/// `formatC`'s `'f'/'g'/'e'/'a'` case ignored the requested C specifier
/// and precision entirely, always calling `std.fmt.bufPrint(&buf, "{d}",
/// .{val})` — so this is a direct, behavior-preserving port of what was
/// already happening, minus the pointless C-format-string round trip).
///
/// Tests: formatMiraShowNum matches shownum's ".0"-suffix rule
fn formatMiraShowNum(buf: []u8, value: f64) []const u8 {
    const s = std.fmt.bufPrint(buf, "{d}", .{value}) catch return bufFallback(buf, "0.0");
    if (std.mem.indexOfAny(u8, s, ".eE") != null) return s;
    // No '.'/exponent -- looks like a bare integer; append ".0" in place.
    if (s.len + 2 > buf.len) return s;
    buf[s.len] = '.';
    buf[s.len + 1] = '0';
    return buf[0 .. s.len + 2];
}

/// A buffer-backed fallback string (so callers that index into the
/// returned slice's own backing `buf` — to place a NUL terminator right
/// after it, matching `sprintf`'s convention — stay correct even on the
/// rare error path, where returning a bare string literal instead would
/// leave `buf` holding stale bytes before the terminator).
fn bufFallback(buf: []u8, text: []const u8) []const u8 {
    const n = @min(text.len, buf.len);
    @memcpy(buf[0..n], text[0..n]);
    return buf[0..n];
}

/// Miranda's `showfloat n x`: `x` fixed to exactly `n` decimal places
/// (`%.*f`). The old `sprintf(..., "%.*f", .{n, x})` call silently
/// discarded `n` (`formatC`'s float case never read its `precision`
/// argument — confirmed via `_ = precision;` in `formatArg`) and, worse,
/// `formatC`'s own `%.*` width/precision parsing didn't handle the `*`
/// (read-precision-from-args) form at all, producing literal garbage
/// (`?INVALID_SPECIFIER?f`) for every call — a real, pre-existing,
/// completely broken builtin, not merely an imprecise one. Fixed here
/// using Zig's own precision-aware float formatting, which needs no
/// C-convention translation (unlike scientific notation's exponent sign).
///
/// Tests: formatMiraFixed matches a fixed decimal-places count
fn formatMiraFixed(buf: []u8, precision: usize, value: f64) []const u8 {
    return std.fmt.bufPrint(buf, "{d:.[1]}", .{ value, precision }) catch bufFallback(buf, "0.0");
}

/// Miranda's `showscaled n x`: `x` in scientific notation with `n`
/// digits after the mantissa's decimal point (`%.*e`) — same
/// precision-discarding/garbage-output bug as `showfloat` (see
/// `formatMiraFixed`'s doc comment), fixed here the same way, plus one
/// extra step: Zig's `{e}` exponent is bare (`e5`, `e-4`), where C's `%e`
/// requires an explicit sign and a minimum of two digits (`e+05`,
/// `e-04`) — `toCScientificExponent` bridges that gap. Verified against
/// the C standard's own `%e` specification (mandatory sign, zero-padded
/// to at least 2 digits), not a live reference binary (none was
/// available in this sandbox) — flagged as the one part of this
/// conversion without an executable oracle to check against.
///
/// Tests: formatMiraScaled produces a C-style signed, zero-padded exponent
fn formatMiraScaled(buf: []u8, precision: usize, value: f64) []const u8 {
    var zig_buf: [64]u8 = undefined;
    const zig_sci = std.fmt.bufPrint(&zig_buf, "{e:.[1]}", .{ value, precision }) catch return bufFallback(buf, "0.0e+00");
    return toCScientificExponent(buf, zig_sci) catch bufFallback(buf, "0.0e+00");
}

/// Reformat Zig's `{e:.N}` output (`"1.235e5"`, `"1.234e-4"`) into C's
/// `%.*e` convention (`"1.235e+05"`, `"1.234e-04"`).
fn toCScientificExponent(buf: []u8, zig_sci: []const u8) ![]const u8 {
    const e_idx = std.mem.indexOfScalar(u8, zig_sci, 'e').?;
    const mantissa = zig_sci[0..e_idx];
    const exp = try std.fmt.parseInt(i32, zig_sci[e_idx + 1 ..], 10);
    return std.fmt.bufPrint(buf, "{s}e{c}{:0>2}", .{ mantissa, @as(u8, if (exp < 0) '-' else '+'), @abs(exp) });
}

/// Miranda's `showhex x`: `x` as a C99 hex-float literal (`%a`) — per the
/// manual (`docs/man/mira.man.ms`), `showhex pi => 0x1.921fb54442d18p+1`.
/// The old `sprintf(..., "%a", ...)` call hit the same `formatC` fallback
/// as `shownum`'s `%.16g` (see `formatMiraShowNum`'s doc comment) and
/// printed a plain *decimal* number instead — not merely imprecise, the
/// wrong notation entirely. Fixed here with Zig's own `{x}` float
/// formatting, verified to match the manual's own worked example exactly
/// (`0x1.921fb54442d18` — a real `f64`'s 52-bit mantissa is exactly 13
/// hex digits, and C99 specifies `%a` prints the *exact*, non-shortened
/// mantissa when no precision is given, same as Zig's default): the only
/// gap is the exponent's mandatory sign (`p+1`, not Zig's bare `p1`) —
/// `%a`'s exponent has no minimum-digit-count requirement (unlike `%e`'s
/// 2-digit floor), so no zero-padding is needed here.
///
/// Tests: formatMiraHex matches the manual's showhex pi example
fn formatMiraHex(buf: []u8, value: f64) []const u8 {
    var zig_buf: [64]u8 = undefined;
    const zig_hex = std.fmt.bufPrint(&zig_buf, "{x}", .{value}) catch return bufFallback(buf, "0x0p+0");
    const p_idx = std.mem.indexOfScalar(u8, zig_hex, 'p') orelse return bufFallback(buf, zig_hex);
    if (zig_hex[p_idx + 1] == '-') return bufFallback(buf, zig_hex);
    return std.fmt.bufPrint(buf, "{s}+{s}", .{ zig_hex[0 .. p_idx + 1], zig_hex[p_idx + 1 ..] }) catch bufFallback(buf, zig_hex);
}

test "formatMiraShowNum matches shownum's \".0\"-suffix rule" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("2.0", formatMiraShowNum(&buf, 2.0));
    try std.testing.expectEqualStrings("12.34", formatMiraShowNum(&buf, 12.34));
    try std.testing.expectEqualStrings("0.3333333333333333", formatMiraShowNum(&buf, 1.0 / 3.0));
    try std.testing.expectEqualStrings("-12.5", formatMiraShowNum(&buf, -12.5));
    try std.testing.expectEqualStrings("0.0", formatMiraShowNum(&buf, 0.0));
}

test "formatMiraFixed matches a fixed decimal-places count" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("3.142", formatMiraFixed(&buf, 3, 3.14159265358979));
    try std.testing.expectEqualStrings("3", formatMiraFixed(&buf, 0, 3.14159265358979));
    try std.testing.expectEqualStrings("3.14159", formatMiraFixed(&buf, 5, 3.14159265358979));
}

test "formatMiraScaled produces a C-style signed, zero-padded exponent" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("1.235e+05", formatMiraScaled(&buf, 3, 123456.789));
    try std.testing.expectEqualStrings("1.234e-04", formatMiraScaled(&buf, 3, 0.0001234));
    try std.testing.expectEqualStrings("1.000e+00", formatMiraScaled(&buf, 3, 1.0));
    try std.testing.expectEqualStrings("-5.50e+00", formatMiraScaled(&buf, 2, -5.5));
}

test "formatMiraHex matches the manual's showhex pi example" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("0x1.921fb54442d18p+1", formatMiraHex(&buf, std.math.pi));
    try std.testing.expectEqualStrings("0x1p+0", formatMiraHex(&buf, 1.0));
    try std.testing.expectEqualStrings("0x1p-1", formatMiraHex(&buf, 0.5));
}

/// Dispatch a combinator that now has all its arguments: switch on its tag and
/// perform the in-place rewrite (or delegate to `combinators`/`io`/`lex`).
pub fn handleReadyState(ctx: *ReductionCtx) void {
    @setEvalBranchQuota(50000);
    // shadow vars to replicate C macro-mappings
    // #define e (ctx->e)
    // #define s (ctx->s)
    // #define hold (ctx->hold)
    // #define arg1 (ctx->args[0])
    // #define arg2 (ctx->args[1])
    // #define arg3 (ctx->args[2])
    // #define arg4 (ctx->args[3])
    // #define lastArg(ctx) tl(e)

    const e_val = ctx.e;

    switch (e_val) {
        word.I => {
            reduce.upLeft(ctx);
            ctx.e = reduce.tlGet(ctx.heap, ctx.e);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.SEQ => {
            reduce.upLeft(ctx);
            if (reduce.upleft(ctx)) {
                ctx.action = word.ACT_DONE;
                return;
            }
            ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.FORCE => {
            reduce.upLeft(ctx);
            reduce.force(lastArg(ctx));
            ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.HD => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.NIL) {
                word.printErr("\nATTEMPT TO TAKE hd OF nil\n", .{});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.hdGet(ctx.heap, lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.TL => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.NIL) {
                word.printErr("\nATTEMPT TO TAKE tl OF nil\n", .{});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.tlGet(ctx.heap, lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.BODY => {
            reduce.upLeft(ctx);
            reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.hdGet(ctx.heap, lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.LAST => {
            reduce.upLeft(ctx);
            reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.tlGet(ctx.heap, lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.TAKE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            if (reduce.upleft(ctx)) {
                ctx.action = word.ACT_DONE;
                return;
            }
            if (!reduce.isInt(ctx.heap, ctx.args[0])) {
                reduce_rt.intError("take");
            }
            const n = big.toInt(heap.heap(), ctx.args[0]);
            const lastarg_reduced = reduce.reduce(lastArg(ctx));
            setLastArg(ctx, lastarg_reduced);
            if (n <= 0 or lastarg_reduced == word.NIL) {
                reduce.rewriteToNil(ctx.heap, &ctx.e);
                ctx.action = word.ACT_DONE;
                return;
            }
            reduce.rewriteToCons(ctx.heap, ctx.e, reduce.hdGet(ctx.heap, lastarg_reduced), reduce.ap2(ctx.heap, word.TAKE, big.fromInt(heap.heap(), n - 1), reduce.tlGet(ctx.heap, lastarg_reduced)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.FILEMODE => {
            reduce.upLeft(ctx);
            if (platform.getFileInfo(reduce.getstring(lastArg(ctx), "filemode"))) |info| {
                const mode = info.mode;
                const d = if ((mode & 0o170000) == 0o040000) @as(Word, 'd') else '-';
                const perm = if (info.uid == platform.geteuid()) (mode & 0o700) >> 6 else if (info.gid == platform.getegid()) (mode & 0o070) >> 3 else mode & 0o007;
                const r = if ((perm & 0o4) != 0) @as(Word, 'r') else '-';
                const w = if ((perm & 0o2) != 0) @as(Word, 'w') else '-';
                const x = if ((perm & 0o1) != 0) @as(Word, 'x') else '-';
                reduce.rewriteToCons(ctx.heap, ctx.e, d, reduce.cons(ctx.heap, r, reduce.cons(ctx.heap, w, reduce.cons(ctx.heap, x, word.NIL))));
            } else {
                reduce.rewriteToNil(ctx.heap, &ctx.e);
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.FILESTAT => {
            reduce.upLeft(ctx);
            if (platform.getFileInfo(reduce.getstring(lastArg(ctx), "filestat"))) |info| {
                reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, big.fromInt(heap.heap(), @intCast(info.ino)), big.fromInt(heap.heap(), @intCast(info.dev))), big.fromInt(heap.heap(), @intCast(info.mtime)));
            } else {
                reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, heap.stosmallint(0), heap.stosmallint(-1)), heap.stosmallint(0));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.GETENV => return handleReadyGETENV(ctx),
        word.EXEC => return handleReadyEXEC(ctx),
        word.NUMVAL => return handleReadyNUMVAL(ctx),
        word.STARTREAD => {
            reduce.upLeft(ctx);
            const fil = reduce.getstring(lastArg(ctx), "read");
            const f = word.fopen(fil, "r");
            if (f == null) {
                word.printErr("\nread, cannot open: \"{s}\"\n", .{std.mem.span(fil.?)});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            setLastArg(ctx, reduce_rt.wrapPtr(@intCast(@intFromPtr(f.?))));
            reduce.hdSet(ctx.heap, ctx.e, word.READ);
            reduce.downLeft(ctx);
            io_handlers.handle_READ(ctx);
            return;
        },
        word.STARTREADBIN => {
            reduce.upLeft(ctx);
            const fil = reduce.getstring(lastArg(ctx), "readb");
            const f = word.fopen(fil, "r");
            if (f == null) {
                word.printErr("\nreadb, cannot open: \"{s}\"\n", .{std.mem.span(fil.?)});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            setLastArg(ctx, reduce_rt.wrapPtr(@intCast(@intFromPtr(f.?))));
            reduce.hdSet(ctx.heap, ctx.e, word.READBIN);
            reduce.downLeft(ctx);
            io_handlers.handle_READBIN(ctx);
            return;
        },
        word.TRY => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (ctx.args[0] == word.FAIL) {
                ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
                ctx.action = word.ACT_NEXTREDEX;
                return;
            }
            ctx.hold = reduce.head(ctx.args[0]);
            if (word.S <= ctx.hold and ctx.hold <= word.ERROR) {
                ctx.action = word.ACT_DONE;
                return;
            }
            reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.args[0]);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.COND => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.True) {
                reduce.rewriteToValue(ctx.heap, &ctx.e, word.K);
                combinators.handleK(ctx);
            } else {
                reduce.rewriteToValue(ctx.heap, &ctx.e, word.KI);
                combinators.handleKI(ctx);
            }
            return;
        },
        word.APPEND => {
            reduce.GETARG(ctx, &ctx.args[0]);
            if (reduce.upleft(ctx)) {
                ctx.action = word.ACT_DONE;
                return;
            }
            if (ctx.args[0] == word.NIL) {
                ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
                ctx.action = word.ACT_NEXTREDEX;
                return;
            }
            reduce.rewriteToCons(ctx.heap, ctx.e, reduce.hdGet(ctx.heap, ctx.args[0]), reduce.ap2(ctx.heap, word.APPEND, reduce.tlGet(ctx.heap, ctx.args[0]), lastArg(ctx)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.AND => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.True) {
                ctx.e = word.I;
                combinators.handleStrictMonadic(ctx);
            } else {
                reduce.hdSet(ctx.heap, ctx.e, word.K);
                reduce.downLeft(ctx);
                combinators.handleK(ctx);
            }
            return;
        },
        word.OR => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.True) {
                reduce.hdSet(ctx.heap, ctx.e, word.K);
                reduce.downLeft(ctx);
                combinators.handleK(ctx);
            } else {
                ctx.e = word.I;
                combinators.handleStrictMonadic(ctx);
            }
            return;
        },
        word.NOT => {
            reduce.upLeft(ctx);
            reduce.rewriteToValue(ctx.heap, &ctx.e, if (lastArg(ctx) == word.True) word.False else word.True);
            ctx.action = word.ACT_DONE;
            return;
        },
        word.NEG => {
            reduce.upLeft(ctx);
            if (reduce.isInt(ctx.heap, lastArg(ctx))) {
                reduce.simpl(ctx, big.negate(heap.heap(), lastArg(ctx)));
            } else {
                heap.setdbl(ctx.e, -heap.getDbl(lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.CODE => {
            reduce.upLeft(ctx);
            reduce.simpl(ctx, heap.make(.INT, heap.getChar(lastArg(ctx)), 0));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.DECODE => {
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                reduce_rt.intError("decode");
            }
            const val = big.toInt(heap.heap(), lastArg(ctx));
            if (val < 0 or val > word.UMAX) {
                word.printErr("\nCHARACTER OUT-OF-RANGE decode({})\n", .{val});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            reduce.hdSet(ctx.heap, ctx.e, word.I);
            const val_char = heap.stoChar(@intCast(val));
            reduce.tlSet(ctx.heap, ctx.e, val_char);
            ctx.e = val_char;
            ctx.action = word.ACT_DONE;
            return;
        },
        word.INTEGER => {
            reduce.upLeft(ctx);
            reduce.rewriteToValue(ctx.heap, &ctx.e, if (reduce.isInt(ctx.heap, lastArg(ctx))) word.True else word.False);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.SHOWNUM => {
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                const x = heap.getDbl(lastArg(ctx));
                const s = formatMiraShowNum(&ctx.rs.linebuf, x);
                ctx.rs.linebuf[s.len] = 0;
                reduce.rewriteToString(ctx.heap, &ctx.e, @ptrCast(&ctx.rs.linebuf));
            } else {
                reduce.simpl(ctx, big.toDecimalList(heap.heap(), lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWHEX => {
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                const s = formatMiraHex(&ctx.rs.linebuf, heap.getDbl(lastArg(ctx)));
                ctx.rs.linebuf[s.len] = 0;
                reduce.rewriteToString(ctx.heap, &ctx.e, @ptrCast(&ctx.rs.linebuf));
            } else {
                reduce.simpl(ctx, big.toHexList(heap.heap(), lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWOCT => {
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                reduce_rt.intError("showoct");
            } else {
                reduce.simpl(ctx, big.toOctalList(heap.heap(), lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.ARCTAN_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.atan(reduce.forceDbl(ctx.heap, lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("atan"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.EXP_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.exp(reduce.forceDbl(ctx.heap, lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("exp"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.ENTIER_FN => {
            reduce.upLeft(ctx);
            if (reduce.isInt(ctx.heap, lastArg(ctx))) {
                reduce.rewriteToValue(ctx.heap, &ctx.e, lastArg(ctx));
            } else {
                reduce.simpl(ctx, big.fromFloat(heap.heap(), heap.getDbl(lastArg(ctx))));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.LOG_FN => {
            reduce.upLeft(ctx);
            if (reduce.isInt(ctx.heap, lastArg(ctx))) {
                heap.setdbl(ctx.e, big.ln(heap.heap(), big.bn(), lastArg(ctx)));
            } else {
                platform.setErrno(0);
                heap.setdbl(ctx.e, @log(reduce.forceDbl(ctx.heap, lastArg(ctx))));
                if (platform.getErrno() != 0) {
                    reduce_rt.mathError(@constCast("log"));
                }
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.LOG10_FN => {
            reduce.upLeft(ctx);
            if (reduce.isInt(ctx.heap, lastArg(ctx))) {
                heap.setdbl(ctx.e, big.log10(heap.heap(), big.bn(), lastArg(ctx)));
            } else {
                platform.setErrno(0);
                heap.setdbl(ctx.e, @log10(reduce.forceDbl(ctx.heap, lastArg(ctx))));
                if (platform.getErrno() != 0) {
                    reduce_rt.mathError(@constCast("log10"));
                }
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SIN_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.sin(reduce.forceDbl(ctx.heap, lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("sin"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.COS_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.cos(reduce.forceDbl(ctx.heap, lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("cos"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SQRT_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.sqrt(reduce.forceDbl(ctx.heap, lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("sqrt"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.ZIP => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            if (ctx.args[0] == word.NIL or ctx.args[1] == word.NIL) {
                reduce.rewriteToNil(ctx.heap, &ctx.e);
                ctx.action = word.ACT_DONE;
                return;
            }
            reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0]), reduce.hdGet(ctx.heap, ctx.args[1])), reduce.ap2(ctx.heap, word.ZIP, reduce.tlGet(ctx.heap, ctx.args[0]), reduce.tlGet(ctx.heap, ctx.args[1])));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.STEP => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.GENSEQ, reduce.cons(ctx.heap, ctx.args[0], word.NIL)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.EQ => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewriteToCompareEq(ctx.heap, &ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.NEQ => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewriteToCompareNeq(ctx.heap, &ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.PLUS => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0])) {
                heap.setdbl(ctx.e, heap.getDbl(ctx.args[0]) + reduce.forceDbl(ctx.heap, lastArg(ctx)));
            } else if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                heap.setdbl(ctx.e, big.toFloat(heap.heap(), ctx.args[0]) + heap.getDbl(lastArg(ctx)));
            } else {
                reduce.simpl(ctx, big.add(heap.heap(), ctx.args[0], lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.MINUS => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0])) {
                heap.setdbl(ctx.e, heap.getDbl(ctx.args[0]) - reduce.forceDbl(ctx.heap, lastArg(ctx)));
            } else if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                heap.setdbl(ctx.e, big.toFloat(heap.heap(), ctx.args[0]) - heap.getDbl(lastArg(ctx)));
            } else {
                reduce.simpl(ctx, big.sub(heap.heap(), ctx.args[0], lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.TIMES => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0])) {
                heap.setdbl(ctx.e, heap.getDbl(ctx.args[0]) * reduce.forceDbl(ctx.heap, lastArg(ctx)));
            } else if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
                heap.setdbl(ctx.e, big.toFloat(heap.heap(), ctx.args[0]) * heap.getDbl(lastArg(ctx)));
            } else {
                reduce.simpl(ctx, big.mul(heap.heap(), ctx.args[0], lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.INTDIV => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0]) or reduce.isDouble(ctx.heap, lastArg(ctx))) {
                reduce_rt.intError("div");
            }
            if (reduce.bigzero(ctx.heap, lastArg(ctx))) {
                reduce_rt.divError();
            }
            reduce.simpl(ctx, big.div(heap.heap(), big.bn(), ctx.args[0], lastArg(ctx)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.FDIV => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            const fa = reduce.forceDbl(ctx.heap, ctx.args[0]);
            const fb = reduce.forceDbl(ctx.heap, lastArg(ctx));
            if (fb == 0.0) {
                reduce_rt.divError();
            }
            heap.setdbl(ctx.e, fa / fb);
            ctx.action = word.ACT_DONE;
            return;
        },
        word.MOD => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0]) or reduce.isDouble(ctx.heap, lastArg(ctx))) {
                reduce_rt.intError("mod");
            }
            if (reduce.bigzero(ctx.heap, lastArg(ctx))) {
                reduce_rt.divError();
            }
            reduce.simpl(ctx, big.mod(heap.heap(), big.bn(), ctx.args[0], lastArg(ctx)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.GRE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewriteToCompareGe(ctx.heap, &ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.GR => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewriteToCompareGt(ctx.heap, &ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.POWER => return handleReadyPOWER(ctx),
        word.SHOWSCALED => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0])) {
                reduce_rt.intError("showscaled");
            }
            const arg1_int = reduce.getsmallint(ctx.heap, ctx.args[0]);
            const precision: usize = if (arg1_int < 0) 0 else @intCast(arg1_int);
            const s = formatMiraScaled(&ctx.rs.linebuf, precision, reduce.forceDbl(ctx.heap, lastArg(ctx)));
            ctx.rs.linebuf[s.len] = 0;
            reduce.rewriteToString(ctx.heap, &ctx.e, @ptrCast(&ctx.rs.linebuf));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWFLOAT => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.isDouble(ctx.heap, ctx.args[0])) {
                reduce_rt.intError("showfloat");
            }
            const arg1_int = reduce.getsmallint(ctx.heap, ctx.args[0]);
            const precision: usize = if (arg1_int < 0) 0 else @intCast(arg1_int);
            const s = formatMiraFixed(&ctx.rs.linebuf, precision, reduce.forceDbl(ctx.heap, lastArg(ctx)));
            ctx.rs.linebuf[s.len] = 0;
            reduce.rewriteToString(ctx.heap, &ctx.e, @ptrCast(&ctx.rs.linebuf));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.MERGE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (ctx.args[0] == word.NIL) {
                reduce.rewriteToValue(ctx.heap, &ctx.e, lastArg(ctx));
            } else if (lastArg(ctx) == word.NIL) {
                reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.args[0]);
            } else {
                const hd_arg1 = reduce.reduce(reduce.hdGet(ctx.heap, ctx.args[0]));
                reduce.hdSet(ctx.heap, ctx.args[0], hd_arg1);
                const hd_lastarg = reduce.reduce(reduce.hdGet(ctx.heap, lastArg(ctx)));
                reduce.hdSet(ctx.heap, lastArg(ctx), hd_lastarg);
                if (reduce_rt.compare(hd_arg1, hd_lastarg) <= 0) {
                    reduce.rewriteToCons(ctx.heap, ctx.e, hd_arg1, reduce.ap2(ctx.heap, word.MERGE, reduce.tlGet(ctx.heap, ctx.args[0]), lastArg(ctx)));
                } else {
                    reduce.rewriteToCons(ctx.heap, ctx.e, hd_lastarg, reduce.ap2(ctx.heap, word.MERGE, reduce.tlGet(ctx.heap, lastArg(ctx)), ctx.args[0]));
                }
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.STEPUNTIL => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            reduce.upLeft(ctx);
            reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.GENSEQ, reduce.cons(ctx.heap, ctx.args[0], ctx.args[1])));
            if (if (reduce.isInt(ctx.heap, ctx.args[0])) reduce.poz(ctx.heap, ctx.args[0]) else reduce.forceDbl(ctx.heap, ctx.args[0]) >= 0.0) {
                reduce.setTag(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)), .AP);
            }
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.Ush => return handleReadyUsh(ctx),
        else => {
            const tag_val = @intFromEnum(reduce.getTag(ctx.heap, e_val));
            word.printErr("\nimpossible event in reduce (val: {}, tag: {})\n", .{ e_val, tag_val });
            if (options.is_strict) {
                std.debug.panic("impossible event in reduce (val: {}, tag: {})", .{ e_val, tag_val });
            } else {
                std.process.exit(1);
            }
        },
    }
}

/// `getenv`: looks up the last argument (a Miranda string) in the process
/// environment, converting UTF-8 bytes to Miranda's internal char
/// representation if `$UTF8` output is on, then rewrites to the result string
/// (or `nil` if unset).
fn handleReadyGETENV(ctx: *ReductionCtx) void {
    reduce.upLeft(ctx);
    const a = reduce.getstring(lastArg(ctx), "getenv");
    const p = main_clib.getenv(a);
    ctx.hold = word.NIL;
    if (p) |ptr| {
        var i = std.mem.len(ptr);
        if (ctx.rs.UTF8 != 0) {
            const qbuf_slice = rt.allocator.alloc(u8, i + 1) catch heap.mallocPanic("utf8 conversion buffer");
            const qbuf = qbuf_slice.ptr;
            {
                const ptr_span = std.mem.span(ptr);
                @memcpy(qbuf[0..ptr_span.len], ptr_span);
                qbuf[ptr_span.len] = 0;
            }
            var q = qbuf;
            var r = qbuf;
            while (r[0] != 0) {
                if (r[0] > 127) {
                    if ((r[0] == 194 or r[0] == 195) and r[1] >= 128 and r[1] <= 191) {
                        q[0] = if (r[0] == 194) r[1] else r[1] + 64;
                        q += 1;
                        r += 2;
                    } else {
                        reduce_rt.getenvError(a.?);
                        q[0] = r[0];
                        q += 1;
                        r += 1;
                    }
                } else {
                    q[0] = r[0];
                    q += 1;
                    r += 1;
                }
            }
            q[0] = 0;
            i = std.mem.len(@as([*:0]const u8, @ptrCast(qbuf)));
            while (i > 0) {
                i -= 1;
                ctx.hold = reduce.cons(ctx.heap, qbuf[i], ctx.hold);
            }
            rt.allocator.free(qbuf_slice);
        } else {
            while (i > 0) {
                i -= 1;
                ctx.hold = reduce.cons(ctx.heap, ptr[i], ctx.hold);
            }
        }
    }
    reduce.hdSet(ctx.heap, ctx.e, word.I);
    reduce.tlSet(ctx.heap, ctx.e, ctx.hold);
    ctx.e = ctx.hold;
    ctx.action = word.ACT_DONE;
}

/// `system`: forks a `/bin/sh -c <cmd>` child, piping its stdout/stderr back
/// as two lazy Miranda read-streams plus a `WAIT` thunk for its exit code (the
/// child never returns from this function -- it `execl`s directly).
fn handleReadyEXEC(ctx: *ReductionCtx) void {
    reduce.upLeft(ctx);
    var pid: c_int = -1;
    var fd: [2]c_int = undefined;
    var fd_a: [2]c_int = undefined;
    const cp = reduce.getstring(lastArg(ctx), "system");
    var cond = false;
    if (main_clib.pipe(&fd) == -1 or main_clib.pipe(&fd_a) == -1) {
        cond = true;
    } else {
        pid = main_clib.fork();
        cond = (pid != 0);
    }
    if (cond) {
        var fp: ?*word.FILE = null;
        var fp_a: ?*word.FILE = null;
        if (pid != -1) {
            _ = main_clib.close(fd[1]);
            _ = main_clib.close(fd_a[1]);
            fp = word.fdopen(fd[0], "r");
            fp_a = word.fdopen(fd_a[0], "r");
        }
        if (pid == -1 or fp == null or fp_a == null) {
            reduce.rewriteToCons(ctx.heap, ctx.e, word.NIL, reduce.cons(ctx.heap, reduce_rt.piperrmess(pid), big.fromInt(heap.heap(), -1)));
        } else {
            reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.READ, reduce_rt.wrapPtr(@intCast(@intFromPtr(fp.?)))), reduce.cons(ctx.heap, reduce.ap(ctx.heap, word.READ, reduce_rt.wrapPtr(@intCast(@intFromPtr(fp_a.?)))), reduce.ap(ctx.heap, word.WAIT, pid)));
        }
    } else {
        const shell = "/bin/sh";
        _ = main_clib.dup2(fd[1], 1);
        _ = main_clib.dup2(fd_a[1], 2);
        _ = main_clib.close(fd[1]);
        _ = main_clib.close(fd[0]);
        _ = main_clib.close(fd_a[1]);
        _ = main_clib.close(fd_a[0]);
        _ = word.fclose(reduce.getStdin().?);
        _ = main_clib.execl(shell, .{ shell, "-c", cp });
    }
    ctx.action = word.ACT_DONE;
}

/// `numval`: parses the last argument (a Miranda string) as a number,
/// recognizing `0o`/`0x` integer prefixes and falling back to a float scan
/// (via `sscanf`) if the string doesn't fully parse as an integer.
fn handleReadyNUMVAL(ctx: *ReductionCtx) void {
    reduce.upLeft(ctx);
    var x = lastArg(ctx);
    var base: c_int = 10;
    while (x != word.NIL) {
        reduce.hdSet(ctx.heap, x, reduce.reduce(reduce.hdGet(ctx.heap, x)));
        const next_tl = reduce.reduce(reduce.tlGet(ctx.heap, x));
        reduce.tlSet(ctx.heap, x, next_tl);
        x = next_tl;
    }
    while (lastArg(ctx) != word.NIL and isSpaceW(reduce.hdGet(ctx.heap, lastArg(ctx)))) {
        setLastArg(ctx, reduce.tlGet(ctx.heap, lastArg(ctx)));
    }
    x = lastArg(ctx);
    if (x != word.NIL and reduce.hdGet(ctx.heap, x) == '-') {
        x = reduce.tlGet(ctx.heap, x);
    }
    if (reduce.hdGet(ctx.heap, x) == '0' and reduce.tlGet(ctx.heap, x) != word.NIL) {
        switch (toLowerW(reduce.hdGet(ctx.heap, reduce.tlGet(ctx.heap, x)))) {
            'o' => {
                base = 8;
                x = reduce.tlGet(ctx.heap, reduce.tlGet(ctx.heap, x));
                while (x != word.NIL and ('0' <= reduce.hdGet(ctx.heap, x) and reduce.hdGet(ctx.heap, x) <= '7')) {
                    x = reduce.tlGet(ctx.heap, x);
                }
            },
            'x' => {
                base = 16;
                x = reduce.tlGet(ctx.heap, reduce.tlGet(ctx.heap, x));
                while (x != word.NIL and isHexW(reduce.hdGet(ctx.heap, x))) {
                    x = reduce.tlGet(ctx.heap, x);
                }
            },
            else => {},
        }
    } else {
        while (x != word.NIL and isDigitW(reduce.hdGet(ctx.heap, x))) {
            x = reduce.tlGet(ctx.heap, x);
        }
    }
    if (x == word.NIL) {
        reduce.hdSet(ctx.heap, ctx.e, word.I);
        const val = big.parseString(heap.heap(), lastArg(ctx), base);
        reduce.tlSet(ctx.heap, ctx.e, val);
        ctx.e = val;
    } else {
        var p = &ctx.rs.linebuf;
        var d: f64 = 0.0;
        var junk: u8 = 0;
        x = lastArg(ctx);
        var p_idx: usize = 0;
        while (x != word.NIL and p_idx < 1023) {
            p[p_idx] = @intCast(reduce.hdGet(ctx.heap, x));
            p_idx += 1;
            x = reduce.tlGet(ctx.heap, x);
        }
        p[p_idx] = 0;
        p_idx += 1;
        if (p_idx > 60 or main_clib.sscanf(@ptrCast(p), "%lf%c", .{ &d, &junk }) != 1 or junk != 0) {
            word.printErr("\nbad arg for numval: \"{s}\"\n", .{@as([*:0]const u8, @ptrCast(p))});
            reduce_rt.outstats();
            main_clib.exit(1);
        } else {
            reduce.hdSet(ctx.heap, ctx.e, word.I);
            const val = heap.stoDbl(d);
            reduce.tlSet(ctx.heap, ctx.e, val);
            ctx.e = val;
        }
    }
    ctx.action = word.ACT_DONE;
}

/// `^` (power): integer exponentiation via `big.pow` when both operands are
/// non-negative integers; otherwise falls back to `f64` `pow`, reporting a
/// domain error for a negative double base.
fn handleReadyPOWER(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.upLeft(ctx);
    var fa: f64 = 0.0;
    var fb: f64 = 0.0;
    if (reduce.isDouble(ctx.heap, lastArg(ctx))) {
        fa = reduce.forceDbl(ctx.heap, ctx.args[0]);
        if (fa < 0.0) {
            platform.setErrno(main_clib.EDOM);
            reduce_rt.mathError(@constCast("^"));
        }
        fb = heap.getDbl(lastArg(ctx));
    } else if (reduce.isDouble(ctx.heap, ctx.args[0])) {
        fa = heap.getDbl(ctx.args[0]);
        fb = big.toFloat(heap.heap(), lastArg(ctx));
    } else if (reduce.neg(ctx.heap, lastArg(ctx))) {
        fa = big.toFloat(heap.heap(), ctx.args[0]);
        fb = big.toFloat(heap.heap(), lastArg(ctx));
    } else {
        reduce.simpl(ctx, big.pow(heap.heap(), ctx.args[0], lastArg(ctx)));
        ctx.action = word.ACT_DONE;
        return;
    }
    platform.setErrno(0);
    heap.setdbl(ctx.e, std.math.pow(f64, fa, fb));
    if (platform.getErrno() != 0) {
        reduce_rt.mathError(@constCast("power"));
    }
    ctx.action = word.ACT_DONE;
}

/// `show` on a saturated constructor application (`Ush`, the "unshow"
/// combinator): renders the constructor name and its arguments (space- or
/// parenthesis-separated per `ctx.args[1]`, the "needs parens" flag),
/// short-circuiting to `"<unprintable>"` for a suppressed/hidden constructor.
fn handleReadyUsh(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.hdGet(ctx.heap, reduce.head(ctx.args[0])) != reduce.hdGet(ctx.heap, reduce.head(ctx.args[2]))) {
        reduce.rewriteToFail(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.isConstructor(ctx.heap, ctx.args[0])) {
        if (reduce.suppressed(ctx.heap, ctx.args[0])) {
            reduce.rewriteToString(ctx.heap, &ctx.e, "<unprintable>");
        } else {
            reduce.rewriteToString(ctx.heap, &ctx.e, reduce.constrName(ctx.heap, ctx.args[0]));
        }
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = if (ctx.args[1] != 0) reduce.cons(ctx.heap, ')', word.NIL) else word.NIL;
    while (!reduce.isConstructor(ctx.heap, ctx.args[0])) {
        ctx.hold = reduce.cons(ctx.heap, ' ', reduce.ap2(ctx.heap, word.APPEND, reduce.ap(ctx.heap, reduce.tlGet(ctx.heap, ctx.args[0]), reduce.tlGet(ctx.heap, ctx.args[2])), ctx.hold));
        ctx.args[0] = reduce.hdGet(ctx.heap, ctx.args[0]);
        ctx.args[2] = reduce.hdGet(ctx.heap, ctx.args[2]);
    }
    if (reduce.suppressed(ctx.heap, ctx.args[0])) {
        reduce.rewriteToString(ctx.heap, &ctx.e, "<unprintable>");
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, word.APPEND, lex.strConv(reduce.constrName(ctx.heap, ctx.args[0])), ctx.hold);
    if (ctx.args[1] != 0) {
        reduce.rewriteToCons(ctx.heap, ctx.e, '(', ctx.hold);
        ctx.action = word.ACT_DONE;
    } else {
        reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.hold);
        ctx.action = word.ACT_NEXTREDEX;
    }
}
