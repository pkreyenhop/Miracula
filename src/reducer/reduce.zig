const std = @import("std");
pub const clib = @cImport({
    @cInclude("sys/types.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("data.h");
    @cInclude("big.h");
    @cInclude("lex.h");
    @cInclude("combs.h");
    @cInclude("reduce_internal.h");
});

pub const Word = c_long;

pub const ReductionCtx = extern struct {
    e: Word,
    s: Word,
    hold: Word,
    args: [4]Word,
    action: c_int,
};

// Extern globals referenced by reducer helpers
extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;
extern var cycles: i64;

extern fn handle_ready_state(ctx: *ReductionCtx) void;

pub export fn reduce(e_val: Word) Word {
    var ctx: ReductionCtx = undefined;
    ctx.e = e_val;
    ctx.s = clib.BACKSTOP;
    ctx.hold = 0;
    ctx.args[0] = 0;
    ctx.args[1] = 0;
    ctx.args[2] = 0;
    ctx.args[3] = 0;
    ctx.action = clib.ACT_NONE;

    main_loop: while (true) {
        while (is_ap(ctx.e)) {
            downLeft(&ctx);
        }

        cycles += 1;
        ctx.action = clib.ACT_NONE;

        switch (ctx.e) {
            clib.S => clib.zig_handleS(@ptrCast(&ctx)),
            clib.B => clib.zig_handleB(@ptrCast(&ctx)),
            clib.CB => clib.zig_handleCB(@ptrCast(&ctx)),
            clib.C => clib.zig_handleC(@ptrCast(&ctx)),
            clib.Y => clib.zig_handleY(@ptrCast(&ctx)),
            clib.K => clib.zig_handleK(@ptrCast(&ctx)),
            clib.KI => clib.zig_handleKI(@ptrCast(&ctx)),
            clib.S1 => clib.zig_handleS1(@ptrCast(&ctx)),
            clib.B1 => clib.zig_handleB1(@ptrCast(&ctx)),
            clib.C1 => clib.zig_handleC1(@ptrCast(&ctx)),
            clib.S_p => clib.zig_handleS_p(@ptrCast(&ctx)),
            clib.B_p => clib.zig_handleB_p(@ptrCast(&ctx)),
            clib.C_p => clib.zig_handleC_p(@ptrCast(&ctx)),
            clib.ITERATE => clib.zig_handleITERATE(@ptrCast(&ctx)),
            clib.ITERATE1 => clib.zig_handleITERATE1(@ptrCast(&ctx)),
            clib.P, clib.G_RULE => clib.zig_handleP(@ptrCast(&ctx)),
            clib.U => clib.zig_handleU(@ptrCast(&ctx)),
            clib.Uf => clib.zig_handleUf(@ptrCast(&ctx)),
            clib.ATLEAST => clib.zig_handleATLEAST(@ptrCast(&ctx)),
            clib.U_ => clib.zig_handleU_(@ptrCast(&ctx)),
            clib.Ug => clib.zig_handleUg(@ptrCast(&ctx)),
            clib.MATCH => clib.zig_handleMATCH(@ptrCast(&ctx)),
            clib.MATCHINT => clib.zig_handleMATCHINT(@ptrCast(&ctx)),
            clib.GENSEQ => clib.zig_handleGENSEQ(@ptrCast(&ctx)),
            clib.MAP => clib.zig_handleMAP(@ptrCast(&ctx)),
            clib.FLATMAP => clib.zig_handleFLATMAP(@ptrCast(&ctx)),
            clib.FILTER => clib.zig_handleFILTER(@ptrCast(&ctx)),
            clib.LIST_LAST => clib.zig_handleLIST_LAST(@ptrCast(&ctx)),
            clib.LENGTH => clib.zig_handleLENGTH(@ptrCast(&ctx)),
            clib.DROP => clib.zig_handleDROP(@ptrCast(&ctx)),
            clib.SUBSCRIPT => clib.zig_handleSUBSCRIPT(@ptrCast(&ctx)),
            clib.FOLDL1 => clib.zig_handleFOLDL1(@ptrCast(&ctx)),
            clib.FOLDL => clib.zig_handleFOLDL(@ptrCast(&ctx)),
            clib.FOLDR => clib.zig_handleFOLDR(@ptrCast(&ctx)),
            clib.BADCASE => clib.zig_handleBADCASE(@ptrCast(&ctx)),
            clib.GETARGS => clib.zig_handleGETARGS(@ptrCast(&ctx)),
            clib.CONFERROR => clib.zig_handleCONFERROR(@ptrCast(&ctx)),
            clib.ERROR => clib.zig_handleERROR(@ptrCast(&ctx)),
            clib.WAIT => clib.zig_handleWAIT(@ptrCast(&ctx)),
            clib.TRY => clib.zig_handleTRY(@ptrCast(&ctx)),
            clib.FAIL => clib.zig_handleFAIL(@ptrCast(&ctx)),
            clib.Ush1 => clib.zig_handleUsh1(@ptrCast(&ctx)),
            clib.MKSTRICT => clib.zig_handleMKSTRICT(@ptrCast(&ctx)),

            clib.I => clib.zig_handleI(@ptrCast(&ctx)),

            clib.SEQ,
            clib.FORCE,
            clib.HD,
            clib.TL,
            clib.BODY,
            clib.LAST,
            clib.EXEC,
            clib.FILEMODE,
            clib.FILESTAT,
            clib.GETENV,
            clib.INTEGER,
            clib.NUMVAL,
            clib.TAKE,
            clib.STARTREAD,
            clib.STARTREADBIN,
            clib.NB_STARTREAD,
            clib.COND,
            clib.APPEND,
            clib.AND,
            clib.OR,
            clib.NOT,
            clib.NEG,
            clib.CODE,
            clib.DECODE,
            clib.SHOWNUM,
            clib.SHOWHEX,
            clib.SHOWOCT,
            clib.ARCTAN_FN,
            clib.EXP_FN,
            clib.ENTIER_FN,
            clib.LOG_FN,
            clib.LOG10_FN,
            clib.SIN_FN,
            clib.COS_FN,
            clib.SQRT_FN => clib.zig_handle_strict_monadic(@ptrCast(&ctx)),

            clib.ZIP,
            clib.STEP,
            clib.EQ,
            clib.NEQ,
            clib.PLUS,
            clib.MINUS,
            clib.TIMES,
            clib.INTDIV,
            clib.FDIV,
            clib.MOD,
            clib.GRE,
            clib.GR,
            clib.POWER,
            clib.SHOWSCALED,
            clib.SHOWFLOAT,
            clib.MERGE => clib.zig_handle_strict_diadic(@ptrCast(&ctx)),

            clib.Ush,
            clib.STEPUNTIL => clib.zig_handle_strict_triadic(@ptrCast(&ctx)),

            // Grammar Combinators (reduce_lex.c)
            clib.G_ERROR => clib.handle_G_ERROR(@ptrCast(&ctx)),
            clib.G_ALT => clib.handle_G_ALT(@ptrCast(&ctx)),
            clib.G_OPT => clib.handle_G_OPT(@ptrCast(&ctx)),
            clib.G_STAR => clib.handle_G_STAR(@ptrCast(&ctx)),
            clib.G_FBSTAR => clib.handle_G_FBSTAR(@ptrCast(&ctx)),
            clib.G_SYMB => clib.handle_G_SYMB(@ptrCast(&ctx)),
            clib.G_ANY => clib.handle_G_ANY(@ptrCast(&ctx)),
            clib.G_SUCHTHAT => clib.handle_G_SUCHTHAT(@ptrCast(&ctx)),
            clib.G_END => clib.handle_G_END(@ptrCast(&ctx)),
            clib.G_STATE => clib.handle_G_STATE(@ptrCast(&ctx)),
            clib.G_SEQ => clib.handle_G_SEQ(@ptrCast(&ctx)),
            clib.G_UNIT => clib.handle_G_UNIT(@ptrCast(&ctx)),
            clib.G_ZERO => clib.handle_G_ZERO(@ptrCast(&ctx)),
            clib.G_CLOSE => clib.handle_G_CLOSE(@ptrCast(&ctx)),
            clib.G_COUNT => clib.handle_G_COUNT(@ptrCast(&ctx)),

            // Lexer Combinators (reduce_lex.c)
            clib.LEX_RPT1 => clib.handle_LEX_RPT1(@ptrCast(&ctx)),
            clib.LEX_RPT => clib.handle_LEX_RPT(@ptrCast(&ctx)),
            clib.LEX_TRY => clib.handle_LEX_TRY(@ptrCast(&ctx)),
            clib.LEX_TRY_ => clib.handle_LEX_TRY_(@ptrCast(&ctx)),
            clib.LEX_TRY1 => clib.handle_LEX_TRY1(@ptrCast(&ctx)),
            clib.LEX_TRY1_ => clib.handle_LEX_TRY1_(@ptrCast(&ctx)),
            clib.DESTREV => clib.handle_DESTREV(@ptrCast(&ctx)),
            clib.LEX_COUNT0 => clib.handle_LEX_COUNT0(@ptrCast(&ctx)),
            clib.LEX_COUNT => clib.handle_LEX_COUNT(@ptrCast(&ctx)),
            clib.LEX_STRING => clib.handle_LEX_STRING(@ptrCast(&ctx)),
            clib.LEX_CLASS => clib.handle_LEX_CLASS(@ptrCast(&ctx)),
            clib.LEX_DOT => clib.handle_LEX_DOT(@ptrCast(&ctx)),
            clib.LEX_CHAR => clib.handle_LEX_CHAR(@ptrCast(&ctx)),
            clib.LEX_SEQ => clib.handle_LEX_SEQ(@ptrCast(&ctx)),
            clib.LEX_OR => clib.handle_LEX_OR(@ptrCast(&ctx)),
            clib.LEX_RCONTEXT => clib.handle_LEX_RCONTEXT(@ptrCast(&ctx)),
            clib.LEX_STAR => clib.handle_LEX_STAR(@ptrCast(&ctx)),
            clib.LEX_OPT => clib.handle_LEX_OPT(@ptrCast(&ctx)),

            // IO (reduce_io.c)
            clib.READ => clib.handle_READ(@ptrCast(&ctx)),
            clib.READBIN => clib.handle_READBIN(@ptrCast(&ctx)),
            clib.READVALS => clib.handle_READVALS(@ptrCast(&ctx)),

            else => {
                cycles -= 1;
                if (abnormal(ctx.e)) {
                    _ = clib.fprintf(getStderr().?, "\nBLACK HOLE\n");
                    clib.outstats();
                    clib.exit(1);
                }

                switch (tag[@as(usize, @intCast(ctx.e))]) {
                    clib.STRCONS => {
                        ctx.e = pn_val(ctx.e);
                        if (ctx.e == clib.UNDEF or ctx.e == clib.FREE) {
                            _ = clib.fprintf(getStderr().?, "\nimpossible event in reduce - undefined pname\n");
                            clib.exit(1);
                        }
                        ctx.action = clib.ACT_NEXTREDEX;
                    },
                    clib.DATAPAIR => {
                        upLeft(&ctx);
                        _ = clib.fprintf(getStderr().?, "\nUNDEFINED NAME (specified as \"%s\" in %s)\n", @as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(hd_get(hd_get(ctx.e)))))))), @as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(tl_get(ctx.e))))))));
                        clib.outstats();
                        clib.exit(1);
                    },
                    clib.ID => {
                        if (id_val(ctx.e) == clib.UNDEF or id_val(ctx.e) == clib.FREE) {
                            _ = clib.fprintf(getStderr().?, "\nUNDEFINED NAME - %s\n", get_id(ctx.e));
                            clib.outstats();
                            clib.exit(1);
                        }
                        ctx.e = id_val(ctx.e);
                        ctx.action = clib.ACT_NEXTREDEX;
                    },
                    clib.CONSTRUCTOR => {
                        while (true) {
                            if (upleft(&ctx)) {
                                ctx.action = clib.ACT_DONE;
                                break;
                            }
                        }
                    },
                    clib.STARTREADVALS => {
                        clib.handle_STARTREADVALS(@ptrCast(&ctx));
                    },
                    clib.ATOM, clib.INT, clib.UNICODE, clib.DOUBLE, clib.CONS => {
                        ctx.action = clib.ACT_DONE;
                    },
                    else => {
                        _ = clib.fprintf(getStderr().?, "\nimpossible tag (%d) in reduce\n", tag[@as(usize, @intCast(ctx.e))]);
                        clib.exit(1);
                    },
                }
            },
        }

        if (ctx.action == clib.ACT_NEXTREDEX) {
            continue :main_loop;
        }

        while (true) {
            if (ctx.s == clib.BACKSTOP) {
                return ctx.e;
            }

            upRight(&ctx);

            if (is_ap(ctx.e)) {
                downLeft(&ctx);
                downRight(&ctx);
                continue :main_loop;
            }

            handle_ready_state(&ctx);
            if (ctx.action == clib.ACT_NEXTREDEX) {
                continue :main_loop;
            }
        }
    }
}
pub extern fn print(e_val: Word) void;
pub extern var waiting: Word;
pub extern var errtrap: Word;
pub extern var s_out: ?*clib.FILE;
pub extern fn reduce_badcase_error(arg_info: Word) void;
pub extern fn reduce_conf_error(arg_info: Word) void;
pub extern fn conv_args() Word;
pub extern fn getstring(x: Word, cmd: ?[*:0]const u8) ?[*:0]u8;
pub extern fn head(x_val: Word) Word;
pub extern fn force(x_val: Word) void;

pub inline fn clean_ptr(x: Word) usize {
    return @as(usize, @intCast(x & ~clib.tlptrbits));
}

pub inline fn hd_get(x: Word) Word {
    return hd[clean_ptr(x) * 2];
}

pub inline fn hd_set(x: Word, val: Word) void {
    hd[clean_ptr(x) * 2] = val;
}

pub inline fn tl_get(x: Word) Word {
    return tl[clean_ptr(x) * 2];
}

pub inline fn tl_set(x: Word, val: Word) void {
    tl[clean_ptr(x) * 2] = val;
}

// Traversal Helpers matching C exactly

pub inline fn downLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = ctx.e;
    ctx.e = hd_get(ctx.e);
    hd_set(ctx.s, ctx.hold);
}

pub inline fn downRight(ctx: *ReductionCtx) void {
    ctx.hold = hd_get(ctx.s);
    hd_set(ctx.s, ctx.e);
    ctx.e = tl_get(ctx.s);
    tl_set(ctx.s, ctx.hold);
    ctx.s |= clib.tlptrbit;
}

pub inline fn downright(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    downRight(ctx);
    return false;
}

pub inline fn upLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = hd_get(ctx.s);
    hd_set(ctx.hold, ctx.e);
    ctx.e = ctx.hold;
}

pub inline fn upleft(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    upLeft(ctx);
    return false;
}

pub inline fn upRight(ctx: *ReductionCtx) void {
    ctx.s &= ~clib.tlptrbits;
    ctx.hold = tl_get(ctx.s);
    tl_set(ctx.s, ctx.e);
    ctx.e = hd_get(ctx.s);
    hd_set(ctx.s, ctx.hold);
}

pub inline fn GETARG(ctx: *ReductionCtx, a: *Word) void {
    upLeft(ctx);
    a.* = tl_get(ctx.e);
}

pub inline fn getarg(ctx: *ReductionCtx, a: *Word) bool {
    if (upleft(ctx)) {
        return true;
    }
    a.* = tl_get(ctx.e);
    return false;
}

pub inline fn simpl(ctx: *ReductionCtx, r: Word) void {
    hd_set(ctx.e, clib.I);
    tl_set(ctx.e, r);
    ctx.e = r;
}

pub inline fn abnormal(x: Word) bool {
    return x < 0;
}
pub inline fn is_ap(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.AP;
}
pub inline fn is_num(x: Word) bool {
    if (abnormal(x)) return false;
    const t = tag[@as(usize, @intCast(x))];
    return t == clib.INT or t == clib.DOUBLE;
}
pub inline fn is_constructor(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.CONSTRUCTOR;
}
pub inline fn is_int(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.INT;
}
pub inline fn is_double(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.DOUBLE;
}
pub inline fn is_atom(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.ATOM;
}
pub inline fn is_strcons(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.STRCONS;
}
pub inline fn is_id(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.ID;
}
pub inline fn id_val(x: Word) Word {
    return tl_get(x);
}
pub inline fn is_datapair(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.DATAPAIR;
}
pub inline fn is_startreadvals(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.STARTREADVALS;
}
pub inline fn is_cons(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.CONS;
}
pub inline fn is_unicode(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == clib.UNICODE;
}

pub inline fn rewrite_to_value(expr: *Word, value: Word) void {
    hd_set(expr.*, clib.I);
    tl_set(expr.*, value);
    expr.* = value;
}

pub inline fn rewrite_to_nil(expr: *Word) void {
    rewrite_to_value(expr, clib.NIL);
}

pub inline fn rewrite_to_fail(expr: *Word) void {
    rewrite_to_value(expr, clib.FAIL);
}

pub inline fn rewrite_to_failure(expr: *Word) void {
    rewrite_to_value(expr, clib.NIL);
}

pub inline fn rewrite_to_cons_head(expr: Word, head_value: Word) void {
    tag[@as(usize, @intCast(expr))] = clib.CONS;
    hd_set(expr, head_value);
}

pub inline fn rewrite_to_cons(expr: Word, head_value: Word, tail_value: Word) void {
    tag[@as(usize, @intCast(expr))] = clib.CONS;
    hd_set(expr, head_value);
    tl_set(expr, tail_value);
}

pub inline fn rewrite_to_existing_tail(expr: Word) Word {
    hd_set(expr, clib.I);
    return tl_get(expr);
}

pub inline fn ap(x: Word, y: Word) Word {
    return clib.make(clib.AP, x, y);
}

pub inline fn rewrite_to_match_result(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hd_set(expr.*, clib.I);
    const val = if (clib.compare(left, right) == 0) success_value else clib.FAIL;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_int_match_result(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hd_set(expr.*, clib.I);
    const val = if (!is_int(value) or clib.bigcmp(literal, value) != 0) clib.FAIL else success_value;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_string(expr: *Word, value: [*:0]const u8) void {
    hd_set(expr.*, clib.I);
    const val = clib.str_conv(value);
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn cons(x: Word, y: Word) Word {
    return clib.make(clib.CONS, x, y);
}

pub inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

pub inline fn neg(x: Word) bool {
    return (hd_get(x) & clib.SIGNBIT) != 0;
}
pub inline fn poz(x: Word) bool {
    return !neg(x);
}
pub inline fn pn_val(x: Word) Word {
    return tl_get(x);
}
pub inline fn get_id(x: Word) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(hd_get(hd_get(hd_get(x))))))))));
}
pub inline fn constr_name(x: Word) [*:0]const u8 {
    const tlx = tl_get(x);
    if (is_id(tlx)) {
        return get_id(tlx);
    } else {
        return get_id(pn_val(tlx));
    }
}
pub inline fn suppressed(x: Word) bool {
    const tlx = tl_get(x);
    return is_strcons(tlx) and !is_id(pn_val(tlx));
}

pub fn getStderr() ?*clib.FILE {
    const T = @TypeOf(clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stderr();
    } else {
        return clib.stderr;
    }
}
pub fn getStdout() ?*clib.FILE {
    const T = @TypeOf(clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stdout();
    } else {
        return clib.stdout;
    }
}
pub fn getStdin() ?*clib.FILE {
    const T = @TypeOf(clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stdin();
    } else {
        return clib.stdin;
    }
}

pub inline fn force_dbl(x: Word) f64 {
    if (is_int(x)) {
        return clib.bigtodbl(x);
    } else {
        return clib.get_dbl(x);
    }
}

pub inline fn coerce_dbl(x: Word) Word {
    if (is_double(x)) return x;
    return clib.sto_dbl(clib.bigtodbl(x));
}

pub inline fn rewrite_to_compare_eq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, clib.I);
    const val = if (clib.compare(left, right) == 0) clib.True else clib.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_neq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, clib.I);
    const val = if (clib.compare(left, right) != 0) clib.True else clib.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_gt(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, clib.I);
    const val = if (clib.compare(left, right) > 0) clib.True else clib.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_ge(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, clib.I);
    const val = if (clib.compare(left, right) >= 0) clib.True else clib.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn bigzero(x: Word) bool {
    return hd_get(x) == 0 and tl_get(x) == 0;
}

pub inline fn getsmallint(x: Word) Word {
    const h_val = hd_get(x);
    return if ((h_val & clib.SIGNBIT) != 0) -(h_val & clib.MAXDIGIT) else h_val;
}





