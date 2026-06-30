//! reducer/ready.zig — the "ready state" combinator dispatcher.
//!
//! `handleReadyState` is the heart of the reduction loop: once the spine is
//! unwound and a combinator has all of its arguments in hand, this routine
//! switches on the combinator tag and performs the rewrite — delegating the
//! arithmetic/list combinators to `combinators.zig`, input to `io.zig`, and the
//! lexer/grammar combinators to `reducer/lex.zig`. It is one very large switch,
//! hence the raised eval-branch quota.

const std = @import("std");
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
    return reduce.tl_get(ctx.e);
}
/// Overwrite the focus node's last argument with `val`.
inline fn setLastArg(ctx: *ReductionCtx, val: Word) void {
    reduce.tl_set(ctx.e, val);
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
            ctx.e = reduce.tl_get(ctx.e);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.SEQ => {
            reduce.upLeft(ctx);
            if (reduce.upleft(ctx)) {
                ctx.action = word.ACT_DONE;
                return;
            }
            ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.FORCE => {
            reduce.upLeft(ctx);
            reduce.force(lastArg(ctx));
            ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
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
            reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastArg(ctx)));
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
            reduce.rewrite_to_value(&ctx.e, reduce.tl_get(lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.BODY => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.LAST => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, reduce.tl_get(lastArg(ctx)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.TAKE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            if (reduce.upleft(ctx)) {
                ctx.action = word.ACT_DONE;
                return;
            }
            if (!reduce.is_int(ctx.args[0])) {
                reduce_rt.intError("take");
            }
            const n = big.toInt(ctx.args[0]);
            const lastarg_reduced = reduce.reduce(lastArg(ctx));
            setLastArg(ctx, lastarg_reduced);
            if (n <= 0 or lastarg_reduced == word.NIL) {
                reduce.rewrite_to_nil(&ctx.e);
                ctx.action = word.ACT_DONE;
                return;
            }
            reduce.rewrite_to_cons(ctx.e, reduce.hd_get(lastarg_reduced), reduce.ap2(word.TAKE, big.fromInt(n - 1), reduce.tl_get(lastarg_reduced)));
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
                reduce.rewrite_to_cons(ctx.e, d, reduce.cons(r, reduce.cons(w, reduce.cons(x, word.NIL))));
            } else {
                reduce.rewrite_to_nil(&ctx.e);
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.FILESTAT => {
            reduce.upLeft(ctx);
            if (platform.getFileInfo(reduce.getstring(lastArg(ctx), "filestat"))) |info| {
                reduce.rewrite_to_cons(ctx.e, reduce.cons(big.fromInt(@intCast(info.ino)), big.fromInt(@intCast(info.dev))), big.fromInt(@intCast(info.mtime)));
            } else {
                reduce.rewrite_to_cons(ctx.e, reduce.cons(heap.stosmallint(0), heap.stosmallint(-1)), heap.stosmallint(0));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.GETENV => {
            reduce.upLeft(ctx);
            const a = reduce.getstring(lastArg(ctx), "getenv");
            const p = main_clib.getenv(a);
            ctx.hold = word.NIL;
            if (p) |ptr| {
                var i = word.strlen(ptr);
                if (rt.rs.UTF8 != 0) {
                    const qbuf_slice = rt.allocator.alloc(u8, i + 1) catch heap.mallocPanic("utf8 conversion buffer");
                    const qbuf = qbuf_slice.ptr;
                    _ = word.strcpy(@as([*:0]u8, @ptrCast(qbuf)), ptr);
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
                    i = word.strlen(@as([*:0]const u8, @ptrCast(qbuf)));
                    while (i > 0) {
                        i -= 1;
                        ctx.hold = reduce.cons(qbuf[i], ctx.hold);
                    }
                    rt.allocator.free(qbuf_slice);
                } else {
                    while (i > 0) {
                        i -= 1;
                        ctx.hold = reduce.cons(ptr[i], ctx.hold);
                    }
                }
            }
            reduce.hd_set(ctx.e, word.I);
            reduce.tl_set(ctx.e, ctx.hold);
            ctx.e = ctx.hold;
            ctx.action = word.ACT_DONE;
            return;
        },
        word.EXEC => {
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
                    reduce.rewrite_to_cons(ctx.e, word.NIL, reduce.cons(reduce_rt.piperrmess(pid), big.fromInt(-1)));
                } else {
                    reduce.rewrite_to_cons(ctx.e, reduce.ap(word.READ, @intCast(@intFromPtr(fp.?))), reduce.cons(reduce.ap(word.READ, @intCast(@intFromPtr(fp_a.?))), reduce.ap(word.WAIT, pid)));
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
            return;
        },
        word.NUMVAL => {
            reduce.upLeft(ctx);
            var x = lastArg(ctx);
            var base: c_int = 10;
            while (x != word.NIL) {
                reduce.hd_set(x, reduce.reduce(reduce.hd_get(x)));
                const next_tl = reduce.reduce(reduce.tl_get(x));
                reduce.tl_set(x, next_tl);
                x = next_tl;
            }
            while (lastArg(ctx) != word.NIL and word.isspace(reduce.hd_get(lastArg(ctx)))) {
                setLastArg(ctx, reduce.tl_get(lastArg(ctx)));
            }
            x = lastArg(ctx);
            if (x != word.NIL and reduce.hd_get(x) == '-') {
                x = reduce.tl_get(x);
            }
            if (reduce.hd_get(x) == '0' and reduce.tl_get(x) != word.NIL) {
                switch (word.tolower(reduce.hd_get(reduce.tl_get(x)))) {
                    'o' => {
                        base = 8;
                        x = reduce.tl_get(reduce.tl_get(x));
                        while (x != word.NIL and ('0' <= reduce.hd_get(x) and reduce.hd_get(x) <= '7')) {
                            x = reduce.tl_get(x);
                        }
                    },
                    'x' => {
                        base = 16;
                        x = reduce.tl_get(reduce.tl_get(x));
                        while (x != word.NIL and word.isxdigit(reduce.hd_get(x))) {
                            x = reduce.tl_get(x);
                        }
                    },
                    else => {},
                }
            } else {
                while (x != word.NIL and word.isdigit(reduce.hd_get(x))) {
                    x = reduce.tl_get(x);
                }
            }
            if (x == word.NIL) {
                reduce.hd_set(ctx.e, word.I);
                const val = big.parseString(lastArg(ctx), base);
                reduce.tl_set(ctx.e, val);
                ctx.e = val;
            } else {
                var p = &rt.rs.linebuf;
                var d: f64 = 0.0;
                var junk: u8 = 0;
                x = lastArg(ctx);
                var p_idx: usize = 0;
                while (x != word.NIL and p_idx < 1023) {
                    p[p_idx] = @intCast(reduce.hd_get(x));
                    p_idx += 1;
                    x = reduce.tl_get(x);
                }
                p[p_idx] = 0;
                p_idx += 1;
                if (p_idx > 60 or main_clib.sscanf(@ptrCast(p), "%lf%c", .{ &d, &junk }) != 1 or junk != 0) {
                    word.printErr("\nbad arg for numval: \"{s}\"\n", .{@as([*:0]const u8, @ptrCast(p))});
                    reduce_rt.outstats();
                    main_clib.exit(1);
                } else {
                    reduce.hd_set(ctx.e, word.I);
                    const val = heap.stoDbl(d);
                    reduce.tl_set(ctx.e, val);
                    ctx.e = val;
                }
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.STARTREAD => {
            reduce.upLeft(ctx);
            const fil = reduce.getstring(lastArg(ctx), "read");
            const f = word.fopen(fil, "r");
            if (f == null) {
                word.printErr("\nread, cannot open: \"{s}\"\n", .{std.mem.span(fil.?)});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            setLastArg(ctx, @intCast(@intFromPtr(f.?)));
            reduce.hd_set(ctx.e, word.READ);
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
            setLastArg(ctx, @intCast(@intFromPtr(f.?)));
            reduce.hd_set(ctx.e, word.READBIN);
            reduce.downLeft(ctx);
            io_handlers.handle_READBIN(ctx);
            return;
        },
        word.TRY => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (ctx.args[0] == word.FAIL) {
                ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
                ctx.action = word.ACT_NEXTREDEX;
                return;
            }
            ctx.hold = reduce.head(ctx.args[0]);
            if (word.S <= ctx.hold and ctx.hold <= word.ERROR) {
                ctx.action = word.ACT_DONE;
                return;
            }
            reduce.rewrite_to_value(&ctx.e, ctx.args[0]);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.COND => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.True) {
                reduce.rewrite_to_value(&ctx.e, word.K);
                combinators.handleK(ctx);
            } else {
                reduce.rewrite_to_value(&ctx.e, word.KI);
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
                ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
                ctx.action = word.ACT_NEXTREDEX;
                return;
            }
            reduce.rewrite_to_cons(ctx.e, reduce.hd_get(ctx.args[0]), reduce.ap2(word.APPEND, reduce.tl_get(ctx.args[0]), lastArg(ctx)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.AND => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.True) {
                ctx.e = word.I;
                combinators.handleStrictMonadic(ctx);
            } else {
                reduce.hd_set(ctx.e, word.K);
                reduce.downLeft(ctx);
                combinators.handleK(ctx);
            }
            return;
        },
        word.OR => {
            reduce.upLeft(ctx);
            if (lastArg(ctx) == word.True) {
                reduce.hd_set(ctx.e, word.K);
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
            reduce.rewrite_to_value(&ctx.e, if (lastArg(ctx) == word.True) word.False else word.True);
            ctx.action = word.ACT_DONE;
            return;
        },
        word.NEG => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastArg(ctx))) {
                reduce.simpl(ctx, big.negate(lastArg(ctx)));
            } else {
                heap.setdbl(ctx.e, -heap.getDbl(lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.CODE => {
            reduce.upLeft(ctx);
            reduce.simpl(ctx, heap.make(word.INT, heap.getChar(lastArg(ctx)), 0));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.DECODE => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastArg(ctx))) {
                reduce_rt.intError("decode");
            }
            const val = big.toInt(lastArg(ctx));
            if (val < 0 or val > word.UMAX) {
                word.printErr("\nCHARACTER OUT-OF-RANGE decode({})\n", .{val});
                reduce_rt.outstats();
                main_clib.exit(1);
            }
            reduce.hd_set(ctx.e, word.I);
            const val_char = heap.stoChar(@intCast(val));
            reduce.tl_set(ctx.e, val_char);
            ctx.e = val_char;
            ctx.action = word.ACT_DONE;
            return;
        },
        word.INTEGER => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, if (reduce.is_int(lastArg(ctx))) word.True else word.False);
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.SHOWNUM => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastArg(ctx))) {
                const x = heap.getDbl(lastArg(ctx));
                _ = main_clib.sprintf(&rt.rs.linebuf, "%.16g", .{x});
                var p_idx: usize = 0;
                while (word.isdigit(rt.rs.linebuf[p_idx])) {
                    p_idx += 1;
                }
                if (rt.rs.linebuf[p_idx] == 0) {
                    rt.rs.linebuf[p_idx] = '.';
                    rt.rs.linebuf[p_idx + 1] = '0';
                    rt.rs.linebuf[p_idx + 2] = 0;
                }
                reduce.rewrite_to_string(&ctx.e, @ptrCast(&rt.rs.linebuf));
            } else {
                reduce.simpl(ctx, big.toDecimalList(lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWHEX => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastArg(ctx))) {
                _ = main_clib.sprintf(&rt.rs.linebuf, "%a", .{heap.getDbl(lastArg(ctx))});
                reduce.rewrite_to_string(&ctx.e, @ptrCast(&rt.rs.linebuf));
            } else {
                reduce.simpl(ctx, big.toHexList(lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWOCT => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastArg(ctx))) {
                reduce_rt.intError("showoct");
            } else {
                reduce.simpl(ctx, big.toOctalList(lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.ARCTAN_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.atan(reduce.force_dbl(lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("atan"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.EXP_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.exp(reduce.force_dbl(lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("exp"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.ENTIER_FN => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastArg(ctx))) {
                reduce.rewrite_to_value(&ctx.e, lastArg(ctx));
            } else {
                reduce.simpl(ctx, big.fromFloat(heap.getDbl(lastArg(ctx))));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.LOG_FN => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastArg(ctx))) {
                heap.setdbl(ctx.e, big.ln(lastArg(ctx)));
            } else {
                platform.setErrno(0);
                heap.setdbl(ctx.e, @log(reduce.force_dbl(lastArg(ctx))));
                if (platform.getErrno() != 0) {
                    reduce_rt.mathError(@constCast("log"));
                }
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.LOG10_FN => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastArg(ctx))) {
                heap.setdbl(ctx.e, big.log10(lastArg(ctx)));
            } else {
                platform.setErrno(0);
                heap.setdbl(ctx.e, @log10(reduce.force_dbl(lastArg(ctx))));
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
            heap.setdbl(ctx.e, std.math.sin(reduce.force_dbl(lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("sin"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.COS_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.cos(reduce.force_dbl(lastArg(ctx))));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("cos"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SQRT_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.sqrt(reduce.force_dbl(lastArg(ctx))));
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
                reduce.rewrite_to_nil(&ctx.e);
                ctx.action = word.ACT_DONE;
                return;
            }
            reduce.rewrite_to_cons(ctx.e, reduce.cons(reduce.hd_get(ctx.args[0]), reduce.hd_get(ctx.args[1])), reduce.ap2(word.ZIP, reduce.tl_get(ctx.args[0]), reduce.tl_get(ctx.args[1])));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.STEP => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.hd_set(ctx.e, reduce.ap(word.GENSEQ, reduce.cons(ctx.args[0], word.NIL)));
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.EQ => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_eq(&ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.NEQ => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_neq(&ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.PLUS => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                heap.setdbl(ctx.e, heap.getDbl(ctx.args[0]) + reduce.force_dbl(lastArg(ctx)));
            } else if (reduce.is_double(lastArg(ctx))) {
                heap.setdbl(ctx.e, big.toFloat(ctx.args[0]) + heap.getDbl(lastArg(ctx)));
            } else {
                reduce.simpl(ctx, big.add(ctx.args[0], lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.MINUS => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                heap.setdbl(ctx.e, heap.getDbl(ctx.args[0]) - reduce.force_dbl(lastArg(ctx)));
            } else if (reduce.is_double(lastArg(ctx))) {
                heap.setdbl(ctx.e, big.toFloat(ctx.args[0]) - heap.getDbl(lastArg(ctx)));
            } else {
                reduce.simpl(ctx, big.sub(ctx.args[0], lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.TIMES => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                heap.setdbl(ctx.e, heap.getDbl(ctx.args[0]) * reduce.force_dbl(lastArg(ctx)));
            } else if (reduce.is_double(lastArg(ctx))) {
                heap.setdbl(ctx.e, big.toFloat(ctx.args[0]) * heap.getDbl(lastArg(ctx)));
            } else {
                reduce.simpl(ctx, big.mul(ctx.args[0], lastArg(ctx)));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.INTDIV => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0]) or reduce.is_double(lastArg(ctx))) {
                reduce_rt.intError("div");
            }
            if (reduce.bigzero(lastArg(ctx))) {
                reduce_rt.divError();
            }
            reduce.simpl(ctx, big.div(ctx.args[0], lastArg(ctx)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.FDIV => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            const fa = reduce.force_dbl(ctx.args[0]);
            const fb = reduce.force_dbl(lastArg(ctx));
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
            if (reduce.is_double(ctx.args[0]) or reduce.is_double(lastArg(ctx))) {
                reduce_rt.intError("mod");
            }
            if (reduce.bigzero(lastArg(ctx))) {
                reduce_rt.divError();
            }
            reduce.simpl(ctx, big.mod(ctx.args[0], lastArg(ctx)));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.GRE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_ge(&ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.GR => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_gt(&ctx.e, ctx.args[0], lastArg(ctx));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.POWER => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            var fa: f64 = 0.0;
            var fb: f64 = 0.0;
            if (reduce.is_double(lastArg(ctx))) {
                fa = reduce.force_dbl(ctx.args[0]);
                if (fa < 0.0) {
                    platform.setErrno(main_clib.EDOM);
                    reduce_rt.mathError(@constCast("^"));
                }
                fb = heap.getDbl(lastArg(ctx));
            } else if (reduce.is_double(ctx.args[0])) {
                fa = heap.getDbl(ctx.args[0]);
                fb = big.toFloat(lastArg(ctx));
            } else if (reduce.neg(lastArg(ctx))) {
                fa = big.toFloat(ctx.args[0]);
                fb = big.toFloat(lastArg(ctx));
            } else {
                reduce.simpl(ctx, big.pow(ctx.args[0], lastArg(ctx)));
                ctx.action = word.ACT_DONE;
                return;
            }
            platform.setErrno(0);
            heap.setdbl(ctx.e, std.math.pow(f64, fa, fb));
            if (platform.getErrno() != 0) {
                reduce_rt.mathError(@constCast("power"));
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWSCALED => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                reduce_rt.intError("showscaled");
            }
            const arg1_int = reduce.getsmallint(ctx.args[0]);
            _ = main_clib.sprintf(&rt.rs.linebuf, "%.*e", .{ @as(c_int, @intCast(arg1_int)), reduce.force_dbl(lastArg(ctx)) });
            reduce.rewrite_to_string(&ctx.e, @ptrCast(&rt.rs.linebuf));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.SHOWFLOAT => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                reduce_rt.intError("showfloat");
            }
            const arg1_int = reduce.getsmallint(ctx.args[0]);
            _ = main_clib.sprintf(&rt.rs.linebuf, "%.*f", .{ @as(c_int, @intCast(arg1_int)), reduce.force_dbl(lastArg(ctx)) });
            reduce.rewrite_to_string(&ctx.e, @ptrCast(&rt.rs.linebuf));
            ctx.action = word.ACT_DONE;
            return;
        },
        word.MERGE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (ctx.args[0] == word.NIL) {
                reduce.rewrite_to_value(&ctx.e, lastArg(ctx));
            } else if (lastArg(ctx) == word.NIL) {
                reduce.rewrite_to_value(&ctx.e, ctx.args[0]);
            } else {
                const hd_arg1 = reduce.reduce(reduce.hd_get(ctx.args[0]));
                reduce.hd_set(ctx.args[0], hd_arg1);
                const hd_lastarg = reduce.reduce(reduce.hd_get(lastArg(ctx)));
                reduce.hd_set(lastArg(ctx), hd_lastarg);
                if (reduce_rt.compare(hd_arg1, hd_lastarg) <= 0) {
                    reduce.rewrite_to_cons(ctx.e, hd_arg1, reduce.ap2(word.MERGE, reduce.tl_get(ctx.args[0]), lastArg(ctx)));
                } else {
                    reduce.rewrite_to_cons(ctx.e, hd_lastarg, reduce.ap2(word.MERGE, reduce.tl_get(lastArg(ctx)), ctx.args[0]));
                }
            }
            ctx.action = word.ACT_DONE;
            return;
        },
        word.STEPUNTIL => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            reduce.upLeft(ctx);
            reduce.hd_set(ctx.e, reduce.ap(word.GENSEQ, reduce.cons(ctx.args[0], ctx.args[1])));
            if (if (reduce.is_int(ctx.args[0])) reduce.poz(ctx.args[0]) else reduce.force_dbl(ctx.args[0]) >= 0.0) {
                reduce.setTag(reduce.tl_get(reduce.hd_get(ctx.e)), word.AP);
            }
            ctx.action = word.ACT_NEXTREDEX;
            return;
        },
        word.Ush => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            reduce.GETARG(ctx, &ctx.args[2]);
            if (reduce.hd_get(reduce.head(ctx.args[0])) != reduce.hd_get(reduce.head(ctx.args[2]))) {
                reduce.rewrite_to_fail(&ctx.e);
                ctx.action = word.ACT_DONE;
                return;
            }
            if (reduce.is_constructor(ctx.args[0])) {
                if (reduce.suppressed(ctx.args[0])) {
                    reduce.rewrite_to_string(&ctx.e, "<unprintable>");
                } else {
                    reduce.rewrite_to_string(&ctx.e, reduce.constr_name(ctx.args[0]));
                }
                ctx.action = word.ACT_DONE;
                return;
            }
            ctx.hold = if (ctx.args[1] != 0) reduce.cons(')', word.NIL) else word.NIL;
            while (!reduce.is_constructor(ctx.args[0])) {
                ctx.hold = reduce.cons(' ', reduce.ap2(word.APPEND, reduce.ap(reduce.tl_get(ctx.args[0]), reduce.tl_get(ctx.args[2])), ctx.hold));
                ctx.args[0] = reduce.hd_get(ctx.args[0]);
                ctx.args[2] = reduce.hd_get(ctx.args[2]);
            }
            if (reduce.suppressed(ctx.args[0])) {
                reduce.rewrite_to_string(&ctx.e, "<unprintable>");
                ctx.action = word.ACT_DONE;
                return;
            }
            ctx.hold = reduce.ap2(word.APPEND, lex.strConv(reduce.constr_name(ctx.args[0])), ctx.hold);
            if (ctx.args[1] != 0) {
                reduce.rewrite_to_cons(ctx.e, '(', ctx.hold);
                ctx.action = word.ACT_DONE;
            } else {
                reduce.rewrite_to_value(&ctx.e, ctx.hold);
                ctx.action = word.ACT_NEXTREDEX;
            }
            return;
        },
        else => {
            const tag_val = @intFromEnum(reduce.getTag(e_val));
            word.printErr("\nimpossible event in reduce (val: {}, tag: {})\n", .{e_val, tag_val});
            std.process.exit(1);
        },
    }
}
