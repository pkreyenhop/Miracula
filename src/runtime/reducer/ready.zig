const std = @import("std");
const reduce = @import("reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const clib = reduce.clib;
const platform = @import("../../io/platform.zig");
const main = @import("../../main.zig");
const combinators = @import("combinators.zig");
const io_handlers = @import("io.zig");

extern var tag: [*]u8;
extern var hd: [*]Word;
extern var tl: [*]Word;

inline fn lastarg(ctx: *ReductionCtx) Word {
    return reduce.tl_get(ctx.e);
}
inline fn set_lastarg(ctx: *ReductionCtx, val: Word) void {
    reduce.tl_set(ctx.e, val);
}

pub fn handle_ready_state(ctx: *ReductionCtx) void {
    @setEvalBranchQuota(50000);
    // shadow vars to replicate C macro-mappings
    // #define e (ctx->e)
    // #define s (ctx->s)
    // #define hold (ctx->hold)
    // #define arg1 (ctx->args[0])
    // #define arg2 (ctx->args[1])
    // #define arg3 (ctx->args[2])
    // #define arg4 (ctx->args[3])
    // #define lastarg(ctx) tl(e)

    const e_val = ctx.e;

    switch (e_val) {
        clib.I => {
            reduce.upLeft(ctx);
            ctx.e = reduce.tl_get(ctx.e);
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.SEQ => {
            reduce.upLeft(ctx);
            if (reduce.upleft(ctx)) {
                ctx.action = clib.ACT_DONE;
                return;
            }
            ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.FORCE => {
            reduce.upLeft(ctx);
            reduce.force(lastarg(ctx));
            ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.HD => {
            reduce.upLeft(ctx);
            if (lastarg(ctx) == clib.NIL) {
                _ = clib.fprintf(reduce.getStderr().?, "\nATTEMPT TO TAKE hd OF []\n", .{.{}});
                clib.outstats();
                clib.exit(1);
            }
            reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg(ctx)));
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.TL => {
            reduce.upLeft(ctx);
            if (lastarg(ctx) == clib.NIL) {
                _ = clib.fprintf(reduce.getStderr().?, "\nATTEMPT TO TAKE tl OF []\n", .{.{}});
                clib.outstats();
                clib.exit(1);
            }
            reduce.rewrite_to_value(&ctx.e, reduce.tl_get(lastarg(ctx)));
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.BODY => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg(ctx)));
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.LAST => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, reduce.tl_get(lastarg(ctx)));
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.TAKE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            if (reduce.upleft(ctx)) {
                ctx.action = clib.ACT_DONE;
                return;
            }
            if (!reduce.is_int(ctx.args[0])) {
                clib.int_error("take");
            }
            const n = clib.get_int(ctx.args[0]);
            const lastarg_reduced = reduce.reduce(lastarg(ctx));
            set_lastarg(ctx, lastarg_reduced);
            if (n <= 0 or lastarg_reduced == clib.NIL) {
                reduce.rewrite_to_nil(&ctx.e);
                ctx.action = clib.ACT_DONE;
                return;
            }
            reduce.rewrite_to_cons(ctx.e, reduce.hd_get(lastarg_reduced), reduce.ap2(clib.TAKE, clib.sto_int(n - 1), reduce.tl_get(lastarg_reduced)));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.FILEMODE => {
            reduce.upLeft(ctx);
            if (platform.getFileInfo(reduce.getstring(lastarg(ctx), "filemode"))) |info| {
                const mode = info.mode;
                const d = if ((mode & 0o170000) == 0o040000) @as(Word, 'd') else '-';
                const perm = if (info.uid == platform.geteuid()) (mode & 0o700) >> 6 else if (info.gid == platform.getegid()) (mode & 0o070) >> 3 else mode & 0o007;
                const r = if ((perm & 0o4) != 0) @as(Word, 'r') else '-';
                const w = if ((perm & 0o2) != 0) @as(Word, 'w') else '-';
                const x = if ((perm & 0o1) != 0) @as(Word, 'x') else '-';
                reduce.rewrite_to_cons(ctx.e, d, reduce.cons(r, reduce.cons(w, reduce.cons(x, clib.NIL))));
            } else {
                reduce.rewrite_to_nil(&ctx.e);
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.FILESTAT => {
            reduce.upLeft(ctx);
            if (platform.getFileInfo(reduce.getstring(lastarg(ctx), "filestat"))) |info| {
                reduce.rewrite_to_cons(ctx.e, reduce.cons(clib.sto_int(@intCast(info.ino)), clib.sto_int(@intCast(info.dev))), clib.sto_int(@intCast(info.mtime)));
            } else {
                reduce.rewrite_to_cons(ctx.e, reduce.cons(clib.stosmallint(0), clib.stosmallint(-1)), clib.stosmallint(0));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.GETENV => {
            reduce.upLeft(ctx);
            const a = reduce.getstring(lastarg(ctx), "getenv");
            const p = clib.getenv(a);
            ctx.hold = clib.NIL;
            if (p) |ptr| {
                var i = clib.strlen(ptr);
                if (main.rs.UTF8 != 0) {
                    const qbuf = @as([*]u8, @ptrCast(@alignCast(clib.malloc(i + 1) orelse unreachable)));
                    _ = clib.strcpy(@ptrCast(qbuf), ptr);
                    var q = qbuf;
                    var r = qbuf;
                    while (r[0] != 0) {
                        if (r[0] > 127) {
                            if ((r[0] == 194 or r[0] == 195) and r[1] >= 128 and r[1] <= 191) {
                                q[0] = if (r[0] == 194) r[1] else r[1] + 64;
                                q += 1;
                                r += 2;
                            } else {
                                clib.getenv_error(a);
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
                    i = clib.strlen(@ptrCast(qbuf));
                    while (i > 0) {
                        i -= 1;
                        ctx.hold = reduce.cons(qbuf[i], ctx.hold);
                    }
                    clib.free(qbuf);
                } else {
                    while (i > 0) {
                        i -= 1;
                        ctx.hold = reduce.cons(ptr[i], ctx.hold);
                    }
                }
            }
            reduce.hd_set(ctx.e, clib.I);
            reduce.tl_set(ctx.e, ctx.hold);
            ctx.e = ctx.hold;
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.EXEC => {
            reduce.upLeft(ctx);
            var pid: c_int = -1;
            var fd: [2]c_int = undefined;
            var fd_a: [2]c_int = undefined;
            const cp = reduce.getstring(lastarg(ctx), "system");
            var cond = false;
            if (clib.pipe(&fd) == -1 or clib.pipe(&fd_a) == -1) {
                cond = true;
            } else {
                pid = clib.fork();
                cond = (pid != 0);
            }
            if (cond) {
                var fp: ?*clib.FILE = null;
                var fp_a: ?*clib.FILE = null;
                if (pid != -1) {
                    _ = clib.close(fd[1]);
                    _ = clib.close(fd_a[1]);
                    fp = clib.fdopen(fd[0], "r");
                    fp_a = clib.fdopen(fd_a[0], "r");
                }
                if (pid == -1 or fp == null or fp_a == null) {
                    reduce.rewrite_to_cons(ctx.e, clib.NIL, reduce.cons(clib.piperrmess(pid), clib.sto_int(-1)));
                } else {
                    reduce.rewrite_to_cons(ctx.e, reduce.ap(clib.READ, @intCast(@intFromPtr(fp.?))), reduce.cons(reduce.ap(clib.READ, @intCast(@intFromPtr(fp_a.?))), reduce.ap(clib.WAIT, pid)));
                }
            } else {
                const shell = "/bin/sh";
                _ = clib.dup2(fd[1], 1);
                _ = clib.dup2(fd_a[1], 2);
                _ = clib.close(fd[1]);
                _ = clib.close(fd[0]);
                _ = clib.close(fd_a[1]);
                _ = clib.close(fd_a[0]);
                _ = clib.fclose(reduce.getStdin().?);
                _ = clib.execl(shell, .{shell, "-c", cp});
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.NUMVAL => {
            reduce.upLeft(ctx);
            var x = lastarg(ctx);
            var base: c_int = 10;
            while (x != clib.NIL) {
                reduce.hd_set(x, reduce.reduce(reduce.hd_get(x)));
                const next_tl = reduce.reduce(reduce.tl_get(x));
                reduce.tl_set(x, next_tl);
                x = next_tl;
            }
            while (lastarg(ctx) != clib.NIL and clib.isspace(@intCast(reduce.hd_get(lastarg(ctx)))) != 0) {
                set_lastarg(ctx, reduce.tl_get(lastarg(ctx)));
            }
            x = lastarg(ctx);
            if (x != clib.NIL and reduce.hd_get(x) == '-') {
                x = reduce.tl_get(x);
            }
            if (reduce.hd_get(x) == '0' and reduce.tl_get(x) != clib.NIL) {
                switch (clib.tolower(@intCast(reduce.hd_get(reduce.tl_get(x))))) {
                    'o' => {
                        base = 8;
                        x = reduce.tl_get(reduce.tl_get(x));
                        while (x != clib.NIL and ('0' <= reduce.hd_get(x) and reduce.hd_get(x) <= '7')) {
                            x = reduce.tl_get(x);
                        }
                    },
                    'x' => {
                        base = 16;
                        x = reduce.tl_get(reduce.tl_get(x));
                        while (x != clib.NIL and (clib.isxdigit(@intCast(reduce.hd_get(x))) != 0)) {
                            x = reduce.tl_get(x);
                        }
                    },
                    else => {},
                }
            } else {
                while (x != clib.NIL and (clib.isdigit(@intCast(reduce.hd_get(x))) != 0)) {
                    x = reduce.tl_get(x);
                }
            }
            if (x == clib.NIL) {
                reduce.hd_set(ctx.e, clib.I);
                const val = clib.strtobig(lastarg(ctx), base);
                reduce.tl_set(ctx.e, val);
                ctx.e = val;
            } else {
                var p = &main.rs.linebuf;
                var d: f64 = 0.0;
                var junk: u8 = 0;
                x = lastarg(ctx);
                var p_idx: usize = 0;
                while (x != clib.NIL and p_idx < 1023) {
                    p[p_idx] = @intCast(reduce.hd_get(x));
                    p_idx += 1;
                    x = reduce.tl_get(x);
                }
                p[p_idx] = 0;
                p_idx += 1;
                if (p_idx > 60 or clib.sscanf(@ptrCast(p), "%lf%c", .{&d, &junk}) != 1 or junk != 0) {
                    _ = clib.fprintf(reduce.getStderr().?, "\nbad arg for numval: \"%s\"\n", .{.{@as([*:0]const u8, @ptrCast(p))}});
                    clib.outstats();
                    clib.exit(1);
                } else {
                    reduce.hd_set(ctx.e, clib.I);
                    const val = clib.sto_dbl(d);
                    reduce.tl_set(ctx.e, val);
                    ctx.e = val;
                }
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.STARTREAD => {
            reduce.upLeft(ctx);
            const fil = reduce.getstring(lastarg(ctx), "read");
            const f = clib.fopen(fil, "r");
            if (f == null) {
                _ = clib.fprintf(reduce.getStderr().?, "\nread, cannot open: \"%s\"\n", .{.{fil}});
                clib.outstats();
                clib.exit(1);
            }
            set_lastarg(ctx, @intCast(@intFromPtr(f.?)));
            reduce.hd_set(ctx.e, clib.READ);
            reduce.downLeft(ctx);
            io_handlers.handle_READ(ctx);
            return;
        },
        clib.STARTREADBIN => {
            reduce.upLeft(ctx);
            const fil = reduce.getstring(lastarg(ctx), "readb");
            const f = clib.fopen(fil, "r");
            if (f == null) {
                _ = clib.fprintf(reduce.getStderr().?, "\nreadb, cannot open: \"%s\"\n", .{.{fil}});
                clib.outstats();
                clib.exit(1);
            }
            set_lastarg(ctx, @intCast(@intFromPtr(f.?)));
            reduce.hd_set(ctx.e, clib.READBIN);
            reduce.downLeft(ctx);
            io_handlers.handle_READBIN(ctx);
            return;
        },
        clib.TRY => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (ctx.args[0] == clib.FAIL) {
                ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
                ctx.action = clib.ACT_NEXTREDEX;
                return;
            }
            ctx.hold = reduce.head(ctx.args[0]);
            if (clib.S <= ctx.hold and ctx.hold <= clib.ERROR) {
                ctx.action = clib.ACT_DONE;
                return;
            }
            reduce.rewrite_to_value(&ctx.e, ctx.args[0]);
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.COND => {
            reduce.upLeft(ctx);
            if (lastarg(ctx) == clib.True) {
                reduce.rewrite_to_value(&ctx.e, clib.K);
                combinators.zig_handleK(ctx);
            } else {
                reduce.rewrite_to_value(&ctx.e, clib.KI);
                combinators.zig_handleKI(ctx);
            }
            return;
        },
        clib.APPEND => {
            reduce.GETARG(ctx, &ctx.args[0]);
            if (reduce.upleft(ctx)) {
                ctx.action = clib.ACT_DONE;
                return;
            }
            if (ctx.args[0] == clib.NIL) {
                ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
                ctx.action = clib.ACT_NEXTREDEX;
                return;
            }
            reduce.rewrite_to_cons(ctx.e, reduce.hd_get(ctx.args[0]), reduce.ap2(clib.APPEND, reduce.tl_get(ctx.args[0]), lastarg(ctx)));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.AND => {
            reduce.upLeft(ctx);
            if (lastarg(ctx) == clib.True) {
                ctx.e = clib.I;
                combinators.zig_handle_strict_monadic(ctx);
            } else {
                reduce.hd_set(ctx.e, clib.K);
                reduce.downLeft(ctx);
                combinators.zig_handleK(ctx);
            }
            return;
        },
        clib.OR => {
            reduce.upLeft(ctx);
            if (lastarg(ctx) == clib.True) {
                reduce.hd_set(ctx.e, clib.K);
                reduce.downLeft(ctx);
                combinators.zig_handleK(ctx);
            } else {
                ctx.e = clib.I;
                combinators.zig_handle_strict_monadic(ctx);
            }
            return;
        },
        clib.NOT => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, if (lastarg(ctx) == clib.True) clib.False else clib.True);
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.NEG => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastarg(ctx))) {
                reduce.simpl(ctx, clib.bignegate(lastarg(ctx)));
            } else {
                clib.setdbl(ctx.e, -clib.get_dbl(lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.CODE => {
            reduce.upLeft(ctx);
            reduce.simpl(ctx, clib.make(clib.INT, clib.get_char(lastarg(ctx)), 0));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.DECODE => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastarg(ctx))) {
                clib.int_error("decode");
            }
            const val = clib.get_int(lastarg(ctx));
            if (val < 0 or val > clib.UMAX) {
                _ = clib.fprintf(reduce.getStderr().?, "\nCHARACTER OUT-OF-RANGE decode(%lld)\n", .{.{val}});
                clib.outstats();
                clib.exit(1);
            }
            reduce.hd_set(ctx.e, clib.I);
            const val_char = clib.sto_char(@intCast(val));
            reduce.tl_set(ctx.e, val_char);
            ctx.e = val_char;
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.INTEGER => {
            reduce.upLeft(ctx);
            reduce.rewrite_to_value(&ctx.e, if (reduce.is_int(lastarg(ctx))) clib.True else clib.False);
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.SHOWNUM => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastarg(ctx))) {
                const x = clib.get_dbl(lastarg(ctx));
                _ = clib.sprintf(&main.rs.linebuf, "%.16g", .{x});
                var p_idx: usize = 0;
                while (clib.isdigit(@intCast(main.rs.linebuf[p_idx])) != 0) {
                    p_idx += 1;
                }
                if (main.rs.linebuf[p_idx] == 0) {
                    main.rs.linebuf[p_idx] = '.';
                    main.rs.linebuf[p_idx + 1] = '0';
                    main.rs.linebuf[p_idx + 2] = 0;
                }
                reduce.rewrite_to_string(&ctx.e, @ptrCast(&main.rs.linebuf));
            } else {
                reduce.simpl(ctx, clib.bigtostr(lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.SHOWHEX => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastarg(ctx))) {
                _ = clib.sprintf(&main.rs.linebuf, "%a", .{clib.get_dbl(lastarg(ctx))});
                reduce.rewrite_to_string(&ctx.e, @ptrCast(&main.rs.linebuf));
            } else {
                reduce.simpl(ctx, clib.bigtostrx(lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.SHOWOCT => {
            reduce.upLeft(ctx);
            if (reduce.is_double(lastarg(ctx))) {
                clib.int_error("showoct");
            } else {
                reduce.simpl(ctx, clib.bigtostr8(lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.ARCTAN_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            clib.setdbl(ctx.e, std.math.atan(reduce.force_dbl(lastarg(ctx))));
            if (platform.getErrno() != 0) {
                clib.math_error(@constCast("atan"));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.EXP_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            clib.setdbl(ctx.e, std.math.exp(reduce.force_dbl(lastarg(ctx))));
            if (platform.getErrno() != 0) {
                clib.math_error(@constCast("exp"));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.ENTIER_FN => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastarg(ctx))) {
                reduce.rewrite_to_value(&ctx.e, lastarg(ctx));
            } else {
                reduce.simpl(ctx, clib.dbltobig(clib.get_dbl(lastarg(ctx))));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.LOG_FN => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastarg(ctx))) {
                clib.setdbl(ctx.e, clib.biglog(lastarg(ctx)));
            } else {
                platform.setErrno(0);
                clib.setdbl(ctx.e, @log(reduce.force_dbl(lastarg(ctx))));
                if (platform.getErrno() != 0) {
                    clib.math_error(@constCast("log"));
                }
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.LOG10_FN => {
            reduce.upLeft(ctx);
            if (reduce.is_int(lastarg(ctx))) {
                clib.setdbl(ctx.e, clib.biglog10(lastarg(ctx)));
            } else {
                platform.setErrno(0);
                clib.setdbl(ctx.e, @log10(reduce.force_dbl(lastarg(ctx))));
                if (platform.getErrno() != 0) {
                    clib.math_error(@constCast("log10"));
                }
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.SIN_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            clib.setdbl(ctx.e, std.math.sin(reduce.force_dbl(lastarg(ctx))));
            if (platform.getErrno() != 0) {
                clib.math_error(@constCast("sin"));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.COS_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            clib.setdbl(ctx.e, std.math.cos(reduce.force_dbl(lastarg(ctx))));
            if (platform.getErrno() != 0) {
                clib.math_error(@constCast("cos"));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.SQRT_FN => {
            reduce.upLeft(ctx);
            platform.setErrno(0);
            clib.setdbl(ctx.e, std.math.sqrt(reduce.force_dbl(lastarg(ctx))));
            if (platform.getErrno() != 0) {
                clib.math_error(@constCast("sqrt"));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.ZIP => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            if (ctx.args[0] == clib.NIL or ctx.args[1] == clib.NIL) {
                reduce.rewrite_to_nil(&ctx.e);
                ctx.action = clib.ACT_DONE;
                return;
            }
            reduce.rewrite_to_cons(ctx.e, reduce.cons(reduce.hd_get(ctx.args[0]), reduce.hd_get(ctx.args[1])), reduce.ap2(clib.ZIP, reduce.tl_get(ctx.args[0]), reduce.tl_get(ctx.args[1])));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.STEP => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.hd_set(ctx.e, reduce.ap(clib.GENSEQ, reduce.cons(ctx.args[0], clib.NIL)));
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.EQ => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_eq(&ctx.e, ctx.args[0], lastarg(ctx));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.NEQ => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_neq(&ctx.e, ctx.args[0], lastarg(ctx));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.PLUS => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                clib.setdbl(ctx.e, clib.get_dbl(ctx.args[0]) + reduce.force_dbl(lastarg(ctx)));
            } else if (reduce.is_double(lastarg(ctx))) {
                clib.setdbl(ctx.e, clib.bigtodbl(ctx.args[0]) + clib.get_dbl(lastarg(ctx)));
            } else {
                reduce.simpl(ctx, clib.bigplus(ctx.args[0], lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.MINUS => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                clib.setdbl(ctx.e, clib.get_dbl(ctx.args[0]) - reduce.force_dbl(lastarg(ctx)));
            } else if (reduce.is_double(lastarg(ctx))) {
                clib.setdbl(ctx.e, clib.bigtodbl(ctx.args[0]) - clib.get_dbl(lastarg(ctx)));
            } else {
                reduce.simpl(ctx, clib.bigsub(ctx.args[0], lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.TIMES => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                clib.setdbl(ctx.e, clib.get_dbl(ctx.args[0]) * reduce.force_dbl(lastarg(ctx)));
            } else if (reduce.is_double(lastarg(ctx))) {
                clib.setdbl(ctx.e, clib.bigtodbl(ctx.args[0]) * clib.get_dbl(lastarg(ctx)));
            } else {
                reduce.simpl(ctx, clib.bigtimes(ctx.args[0], lastarg(ctx)));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.INTDIV => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0]) or reduce.is_double(lastarg(ctx))) {
                clib.int_error("div");
            }
            if (reduce.bigzero(lastarg(ctx))) {
                clib.div_error();
            }
            reduce.simpl(ctx, clib.bigdiv(ctx.args[0], lastarg(ctx)));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.FDIV => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            const fa = reduce.force_dbl(ctx.args[0]);
            const fb = reduce.force_dbl(lastarg(ctx));
            if (fb == 0.0) {
                clib.div_error();
            }
            clib.setdbl(ctx.e, fa / fb);
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.MOD => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0]) or reduce.is_double(lastarg(ctx))) {
                clib.int_error("mod");
            }
            if (reduce.bigzero(lastarg(ctx))) {
                clib.div_error();
            }
            reduce.simpl(ctx, clib.bigmod(ctx.args[0], lastarg(ctx)));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.GRE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_ge(&ctx.e, ctx.args[0], lastarg(ctx));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.GR => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            reduce.rewrite_to_compare_gt(&ctx.e, ctx.args[0], lastarg(ctx));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.POWER => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            var fa: f64 = 0.0;
            var fb: f64 = 0.0;
            if (reduce.is_double(lastarg(ctx))) {
                fa = reduce.force_dbl(ctx.args[0]);
                if (fa < 0.0) {
                    platform.setErrno(clib.EDOM);
                    clib.math_error(@constCast("^"));
                }
                fb = clib.get_dbl(lastarg(ctx));
            } else if (reduce.is_double(ctx.args[0])) {
                fa = clib.get_dbl(ctx.args[0]);
                fb = clib.bigtodbl(lastarg(ctx));
            } else if (reduce.neg(lastarg(ctx))) {
                fa = clib.bigtodbl(ctx.args[0]);
                fb = clib.bigtodbl(lastarg(ctx));
            } else {
                reduce.simpl(ctx, clib.bigpow(ctx.args[0], lastarg(ctx)));
                ctx.action = clib.ACT_DONE;
                return;
            }
            platform.setErrno(0);
            clib.setdbl(ctx.e, std.math.pow(f64, fa, fb));
            if (platform.getErrno() != 0) {
                clib.math_error(@constCast("power"));
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.SHOWSCALED => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                clib.int_error("showscaled");
            }
            const arg1_int = reduce.getsmallint(ctx.args[0]);
            _ = clib.sprintf(&main.rs.linebuf, "%.*e", .{@as(c_int, @intCast(arg1_int)), reduce.force_dbl(lastarg(ctx))});
            reduce.rewrite_to_string(&ctx.e, @ptrCast(&main.rs.linebuf));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.SHOWFLOAT => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (reduce.is_double(ctx.args[0])) {
                clib.int_error("showfloat");
            }
            const arg1_int = reduce.getsmallint(ctx.args[0]);
            _ = clib.sprintf(&main.rs.linebuf, "%.*f", .{@as(c_int, @intCast(arg1_int)), reduce.force_dbl(lastarg(ctx))});
            reduce.rewrite_to_string(&ctx.e, @ptrCast(&main.rs.linebuf));
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.MERGE => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.upLeft(ctx);
            if (ctx.args[0] == clib.NIL) {
                reduce.rewrite_to_value(&ctx.e, lastarg(ctx));
            } else if (lastarg(ctx) == clib.NIL) {
                reduce.rewrite_to_value(&ctx.e, ctx.args[0]);
            } else {
                const hd_arg1 = reduce.reduce(reduce.hd_get(ctx.args[0]));
                reduce.hd_set(ctx.args[0], hd_arg1);
                const hd_lastarg = reduce.reduce(reduce.hd_get(lastarg(ctx)));
                reduce.hd_set(lastarg(ctx), hd_lastarg);
                if (clib.compare(hd_arg1, hd_lastarg) <= 0) {
                    reduce.rewrite_to_cons(ctx.e, hd_arg1, reduce.ap2(clib.MERGE, reduce.tl_get(ctx.args[0]), lastarg(ctx)));
                } else {
                    reduce.rewrite_to_cons(ctx.e, hd_lastarg, reduce.ap2(clib.MERGE, reduce.tl_get(lastarg(ctx)), ctx.args[0]));
                }
            }
            ctx.action = clib.ACT_DONE;
            return;
        },
        clib.STEPUNTIL => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            reduce.upLeft(ctx);
            reduce.hd_set(ctx.e, reduce.ap(clib.GENSEQ, reduce.cons(ctx.args[0], ctx.args[1])));
            if (if (reduce.is_int(ctx.args[0])) reduce.poz(ctx.args[0]) else reduce.force_dbl(ctx.args[0]) >= 0.0) {
                tag[reduce.clean_ptr(reduce.tl_get(reduce.hd_get(ctx.e)))] = clib.AP;
            }
            ctx.action = clib.ACT_NEXTREDEX;
            return;
        },
        clib.Ush => {
            reduce.GETARG(ctx, &ctx.args[0]);
            reduce.GETARG(ctx, &ctx.args[1]);
            reduce.GETARG(ctx, &ctx.args[2]);
            if (reduce.hd_get(reduce.head(ctx.args[0])) != reduce.hd_get(reduce.head(ctx.args[2]))) {
                reduce.rewrite_to_fail(&ctx.e);
                ctx.action = clib.ACT_DONE;
                return;
            }
            if (reduce.is_constructor(ctx.args[0])) {
                if (reduce.suppressed(ctx.args[0])) {
                    reduce.rewrite_to_string(&ctx.e, "<unprintable>");
                } else {
                    reduce.rewrite_to_string(&ctx.e, reduce.constr_name(ctx.args[0]));
                }
                ctx.action = clib.ACT_DONE;
                return;
            }
            ctx.hold = if (ctx.args[1] != 0) reduce.cons(')', clib.NIL) else clib.NIL;
            while (!reduce.is_constructor(ctx.args[0])) {
                ctx.hold = reduce.cons(' ', reduce.ap2(clib.APPEND, reduce.ap(reduce.tl_get(ctx.args[0]), reduce.tl_get(ctx.args[2])), ctx.hold));
                ctx.args[0] = reduce.hd_get(ctx.args[0]);
                ctx.args[2] = reduce.hd_get(ctx.args[2]);
            }
            if (reduce.suppressed(ctx.args[0])) {
                reduce.rewrite_to_string(&ctx.e, "<unprintable>");
                ctx.action = clib.ACT_DONE;
                return;
            }
            ctx.hold = reduce.ap2(clib.APPEND, clib.str_conv(reduce.constr_name(ctx.args[0])), ctx.hold);
            if (ctx.args[1] != 0) {
                reduce.rewrite_to_cons(ctx.e, '(', ctx.hold);
                ctx.action = clib.ACT_DONE;
            } else {
                reduce.rewrite_to_value(&ctx.e, ctx.hold);
                ctx.action = clib.ACT_NEXTREDEX;
            }
            return;
        },
        else => {
            const tag_val = tag[reduce.clean_ptr(e_val)];
            _ = clib.fprintf(reduce.getStderr().?, "\nimpossible event in reduce (val: %ld, tag: %d)\n", .{.{e_val, tag_val}});
            std.process.exit(1);
        },
    }
}
