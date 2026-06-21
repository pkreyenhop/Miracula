const std = @import("std");
pub const clib = @import("../c_abi.zig");
const core = @import("reduce_core.zig");
const combinators = @import("combinators.zig");
const ready = @import("ready.zig");
const lex_handlers = @import("lex.zig");
const io_handlers = @import("io.zig");

pub const Word = core.Word;
pub const ReductionCtx = core.ReductionCtx;

// Extern globals referenced by reducer helpers
extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;
extern var cycles: i64;
pub extern var stdinuse: Word;

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
            clib.S => combinators.handleS(&ctx),
            clib.B => combinators.handleB(&ctx),
            clib.CB => combinators.handleCB(&ctx),
            clib.C => combinators.handleC(&ctx),
            clib.Y => combinators.handleY(&ctx),
            clib.K => combinators.handleK(&ctx),
            clib.KI => combinators.handleKI(&ctx),
            clib.S1 => combinators.handleS1(&ctx),
            clib.B1 => combinators.handleB1(&ctx),
            clib.C1 => combinators.handleC1(&ctx),
            clib.S_p => combinators.handleS_p(&ctx),
            clib.B_p => combinators.handleB_p(&ctx),
            clib.C_p => combinators.handleC_p(&ctx),
            clib.ITERATE => combinators.handleITERATE(&ctx),
            clib.ITERATE1 => combinators.handleITERATE1(&ctx),
            clib.P, clib.G_RULE => combinators.handleP(&ctx),
            clib.U => combinators.handleU(&ctx),
            clib.Uf => combinators.handleUf(&ctx),
            clib.ATLEAST => combinators.handleATLEAST(&ctx),
            clib.U_ => combinators.handleU_(&ctx),
            clib.Ug => combinators.handleUg(&ctx),
            clib.MATCH => combinators.handleMATCH(&ctx),
            clib.MATCHINT => combinators.handleMATCHINT(&ctx),
            clib.GENSEQ => combinators.handleGENSEQ(&ctx),
            clib.MAP => combinators.handleMAP(&ctx),
            clib.FLATMAP => combinators.handleFLATMAP(&ctx),
            clib.FILTER => combinators.handleFILTER(&ctx),
            clib.LIST_LAST => combinators.handleLIST_LAST(&ctx),
            clib.LENGTH => combinators.handleLENGTH(&ctx),
            clib.DROP => combinators.handleDROP(&ctx),
            clib.SUBSCRIPT => combinators.handleSUBSCRIPT(&ctx),
            clib.FOLDL1 => combinators.handleFOLDL1(&ctx),
            clib.FOLDL => combinators.handleFOLDL(&ctx),
            clib.FOLDR => combinators.handleFOLDR(&ctx),
            clib.BADCASE => combinators.handleBADCASE(&ctx),
            clib.GETARGS => combinators.handleGETARGS(&ctx),
            clib.CONFERROR => combinators.handleCONFERROR(&ctx),
            clib.ERROR => combinators.handleERROR(&ctx),
            clib.WAIT => combinators.handleWAIT(&ctx),
            clib.TRY => combinators.handleTRY(&ctx),
            clib.FAIL => combinators.handleFAIL(&ctx),
            clib.Ush1 => combinators.handleUsh1(&ctx),
            clib.MKSTRICT => combinators.handleMKSTRICT(&ctx),

            clib.I => combinators.handleI(&ctx),

            clib.SEQ, clib.FORCE, clib.HD, clib.TL, clib.BODY, clib.LAST, clib.EXEC, clib.FILEMODE, clib.FILESTAT, clib.GETENV, clib.INTEGER, clib.NUMVAL, clib.TAKE, clib.STARTREAD, clib.STARTREADBIN, clib.NB_STARTREAD, clib.COND, clib.APPEND, clib.AND, clib.OR, clib.NOT, clib.NEG, clib.CODE, clib.DECODE, clib.SHOWNUM, clib.SHOWHEX, clib.SHOWOCT, clib.ARCTAN_FN, clib.EXP_FN, clib.ENTIER_FN, clib.LOG_FN, clib.LOG10_FN, clib.SIN_FN, clib.COS_FN, clib.SQRT_FN => combinators.handle_strict_monadic(&ctx),

            clib.ZIP, clib.STEP, clib.EQ, clib.NEQ, clib.PLUS, clib.MINUS, clib.TIMES, clib.INTDIV, clib.FDIV, clib.MOD, clib.GRE, clib.GR, clib.POWER, clib.SHOWSCALED, clib.SHOWFLOAT, clib.MERGE => combinators.handle_strict_diadic(&ctx),

            clib.Ush, clib.STEPUNTIL => combinators.handle_strict_triadic(&ctx),

            // Grammar Combinators (lex.zig)
            clib.G_ERROR => lex_handlers.handle_G_ERROR(&ctx),
            clib.G_ALT => lex_handlers.handle_G_ALT(&ctx),
            clib.G_OPT => lex_handlers.handle_G_OPT(&ctx),
            clib.G_STAR => lex_handlers.handle_G_STAR(&ctx),
            clib.G_FBSTAR => lex_handlers.handle_G_FBSTAR(&ctx),
            clib.G_SYMB => lex_handlers.handle_G_SYMB(&ctx),
            clib.G_ANY => lex_handlers.handle_G_ANY(&ctx),
            clib.G_SUCHTHAT => lex_handlers.handle_G_SUCHTHAT(&ctx),
            clib.G_END => lex_handlers.handle_G_END(&ctx),
            clib.G_STATE => lex_handlers.handle_G_STATE(&ctx),
            clib.G_SEQ => lex_handlers.handle_G_SEQ(&ctx),
            clib.G_UNIT => lex_handlers.handle_G_UNIT(&ctx),
            clib.G_ZERO => lex_handlers.handle_G_ZERO(&ctx),
            clib.G_CLOSE => lex_handlers.handle_G_CLOSE(&ctx),
            clib.G_COUNT => lex_handlers.handle_G_COUNT(&ctx),

            // Lexer Combinators (lex.zig)
            clib.LEX_RPT1 => lex_handlers.handle_LEX_RPT1(&ctx),
            clib.LEX_RPT => lex_handlers.handle_LEX_RPT(&ctx),
            clib.LEX_TRY => lex_handlers.handle_LEX_TRY(&ctx),
            clib.LEX_TRY_ => lex_handlers.handle_LEX_TRY_(&ctx),
            clib.LEX_TRY1 => lex_handlers.handle_LEX_TRY1(&ctx),
            clib.LEX_TRY1_ => lex_handlers.handle_LEX_TRY1_(&ctx),
            clib.DESTREV => lex_handlers.handle_DESTREV(&ctx),
            clib.LEX_COUNT0 => lex_handlers.handle_LEX_COUNT0(&ctx),
            clib.LEX_COUNT => lex_handlers.handle_LEX_COUNT(&ctx),
            clib.LEX_STRING => lex_handlers.handle_LEX_STRING(&ctx),
            clib.LEX_CLASS => lex_handlers.handle_LEX_CLASS(&ctx),
            clib.LEX_DOT => lex_handlers.handle_LEX_DOT(&ctx),
            clib.LEX_CHAR => lex_handlers.handle_LEX_CHAR(&ctx),
            clib.LEX_SEQ => lex_handlers.handle_LEX_SEQ(&ctx),
            clib.LEX_OR => lex_handlers.handle_LEX_OR(&ctx),
            clib.LEX_RCONTEXT => lex_handlers.handle_LEX_RCONTEXT(&ctx),
            clib.LEX_STAR => lex_handlers.handle_LEX_STAR(&ctx),
            clib.LEX_OPT => lex_handlers.handle_LEX_OPT(&ctx),

            // IO (io.zig)
            clib.READ => io_handlers.handle_READ(&ctx),
            clib.READBIN => io_handlers.handle_READBIN(&ctx),
            clib.READVALS => io_handlers.handle_READVALS(&ctx),

            else => {
                cycles -= 1;
                if (abnormal(ctx.e)) {
                    _ = clib.fprintf(getStderr().?, "\nBLACK HOLE\n", .{.{}});
                    clib.outstats();
                    clib.exit(1);
                }

                switch (tag[@as(usize, @intCast(ctx.e))]) {
                    clib.STRCONS => {
                        ctx.e = pn_val(ctx.e);
                        if (ctx.e == clib.UNDEF or ctx.e == clib.FREE) {
                            _ = clib.fprintf(getStderr().?, "\nimpossible event in reduce - undefined pname\n", .{.{}});
                            clib.exit(1);
                        }
                        ctx.action = clib.ACT_NEXTREDEX;
                    },
                    clib.DATAPAIR => {
                        upLeft(&ctx);
                        _ = clib.fprintf(getStderr().?, "\nUNDEFINED NAME (specified as \"%s\" in %s)\n", .{.{ @as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(hd_get(hd_get(ctx.e)))))))), @as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(tl_get(ctx.e))))))) }});
                        clib.outstats();
                        clib.exit(1);
                    },
                    clib.ID => {
                        if (id_val(ctx.e) == clib.UNDEF or id_val(ctx.e) == clib.FREE) {
                            _ = clib.fprintf(getStderr().?, "\nUNDEFINED NAME - %s\n", .{.{get_id(ctx.e)}});
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
                        io_handlers.handle_STARTREADVALS(&ctx);
                    },
                    clib.ATOM, clib.INT, clib.UNICODE, clib.DOUBLE, clib.CONS => {
                        ctx.action = clib.ACT_DONE;
                    },
                    else => {
                        _ = clib.fprintf(getStderr().?, "\nimpossible tag (%d) in reduce\n", .{.{tag[@as(usize, @intCast(ctx.e))]}});
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

            ready.handle_ready_state(&ctx);
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
