const std = @import("std");
const word = @import("../word.zig");
pub const abi = @import("../c_abi.zig");
const core = @import("reduce_core.zig");
inline fn getTag(x: Word) u8 { return core.getTag(x); }
inline fn setTag(x: Word, val: u8) void { core.setTag(x, val); }
const combinators = @import("combinators.zig");
const ready = @import("ready.zig");
const lex_handlers = @import("lex.zig");
const io_handlers = @import("io.zig");

pub const Word = core.Word;
pub const ReductionCtx = core.ReductionCtx;

// Extern globals referenced by reducer helpers

extern var cycles: i64;
pub extern var stdinuse: Word;

pub export fn reduce(e_val: Word) Word {
    var ctx: ReductionCtx = undefined;
    ctx.e = e_val;
    ctx.s = abi.BACKSTOP;
    ctx.hold = 0;
    ctx.args[0] = 0;
    ctx.args[1] = 0;
    ctx.args[2] = 0;
    ctx.args[3] = 0;
    ctx.action = word.ACT_NONE;

    main_loop: while (true) {
        while (is_ap(ctx.e)) {
            downLeft(&ctx);
        }

        cycles += 1;
        ctx.action = word.ACT_NONE;

        switch (ctx.e) {
            word.S => combinators.handleS(&ctx),
            word.B => combinators.handleB(&ctx),
            word.CB => combinators.handleCB(&ctx),
            word.C => combinators.handleC(&ctx),
            word.Y => combinators.handleY(&ctx),
            word.K => combinators.handleK(&ctx),
            word.KI => combinators.handleKI(&ctx),
            word.S1 => combinators.handleS1(&ctx),
            word.B1 => combinators.handleB1(&ctx),
            word.C1 => combinators.handleC1(&ctx),
            word.S_p => combinators.handleS_p(&ctx),
            word.B_p => combinators.handleB_p(&ctx),
            word.C_p => combinators.handleC_p(&ctx),
            word.ITERATE => combinators.handleITERATE(&ctx),
            word.ITERATE1 => combinators.handleITERATE1(&ctx),
            word.P, word.G_RULE => combinators.handleP(&ctx),
            word.U => combinators.handleU(&ctx),
            word.Uf => combinators.handleUf(&ctx),
            word.ATLEAST => combinators.handleATLEAST(&ctx),
            word.U_ => combinators.handleU_(&ctx),
            word.Ug => combinators.handleUg(&ctx),
            word.MATCH => combinators.handleMATCH(&ctx),
            word.MATCHINT => combinators.handleMATCHINT(&ctx),
            word.GENSEQ => combinators.handleGENSEQ(&ctx),
            word.MAP => combinators.handleMAP(&ctx),
            word.FLATMAP => combinators.handleFLATMAP(&ctx),
            word.FILTER => combinators.handleFILTER(&ctx),
            word.LIST_LAST => combinators.handleLIST_LAST(&ctx),
            word.LENGTH => combinators.handleLENGTH(&ctx),
            word.DROP => combinators.handleDROP(&ctx),
            word.SUBSCRIPT => combinators.handleSUBSCRIPT(&ctx),
            word.FOLDL1 => combinators.handleFOLDL1(&ctx),
            word.FOLDL => combinators.handleFOLDL(&ctx),
            word.FOLDR => combinators.handleFOLDR(&ctx),
            word.BADCASE => combinators.handleBADCASE(&ctx),
            word.GETARGS => combinators.handleGETARGS(&ctx),
            word.CONFERROR => combinators.handleCONFERROR(&ctx),
            word.ERROR => combinators.handleERROR(&ctx),
            word.WAIT => combinators.handleWAIT(&ctx),
            word.TRY => combinators.handleTRY(&ctx),
            word.FAIL => combinators.handleFAIL(&ctx),
            word.Ush1 => combinators.handleUsh1(&ctx),
            word.MKSTRICT => combinators.handleMKSTRICT(&ctx),

            word.I => combinators.handleI(&ctx),

            word.SEQ, word.FORCE, word.HD, word.TL, word.BODY, word.LAST, word.EXEC, word.FILEMODE, word.FILESTAT, word.GETENV, word.INTEGER, word.NUMVAL, word.TAKE, word.STARTREAD, word.STARTREADBIN, word.NB_STARTREAD, word.COND, word.APPEND, word.AND, word.OR, word.NOT, word.NEG, word.CODE, word.DECODE, word.SHOWNUM, word.SHOWHEX, word.SHOWOCT, word.ARCTAN_FN, word.EXP_FN, word.ENTIER_FN, word.LOG_FN, word.LOG10_FN, word.SIN_FN, word.COS_FN, word.SQRT_FN => combinators.handle_strict_monadic(&ctx),

            word.ZIP, word.STEP, word.EQ, word.NEQ, word.PLUS, word.MINUS, word.TIMES, word.INTDIV, word.FDIV, word.MOD, word.GRE, word.GR, word.POWER, word.SHOWSCALED, word.SHOWFLOAT, word.MERGE => combinators.handle_strict_diadic(&ctx),

            word.Ush, word.STEPUNTIL => combinators.handle_strict_triadic(&ctx),

            // Grammar Combinators (lex.zig)
            word.G_ERROR => lex_handlers.handle_G_ERROR(&ctx),
            word.G_ALT => lex_handlers.handle_G_ALT(&ctx),
            word.G_OPT => lex_handlers.handle_G_OPT(&ctx),
            word.G_STAR => lex_handlers.handle_G_STAR(&ctx),
            word.G_FBSTAR => lex_handlers.handle_G_FBSTAR(&ctx),
            word.G_SYMB => lex_handlers.handle_G_SYMB(&ctx),
            word.G_ANY => lex_handlers.handle_G_ANY(&ctx),
            word.G_SUCHTHAT => lex_handlers.handle_G_SUCHTHAT(&ctx),
            word.G_END => lex_handlers.handle_G_END(&ctx),
            word.G_STATE => lex_handlers.handle_G_STATE(&ctx),
            word.G_SEQ => lex_handlers.handle_G_SEQ(&ctx),
            word.G_UNIT => lex_handlers.handle_G_UNIT(&ctx),
            word.G_ZERO => lex_handlers.handle_G_ZERO(&ctx),
            word.G_CLOSE => lex_handlers.handle_G_CLOSE(&ctx),
            word.G_COUNT => lex_handlers.handle_G_COUNT(&ctx),

            // Lexer Combinators (lex.zig)
            word.LEX_RPT1 => lex_handlers.handle_LEX_RPT1(&ctx),
            word.LEX_RPT => lex_handlers.handle_LEX_RPT(&ctx),
            word.LEX_TRY => lex_handlers.handle_LEX_TRY(&ctx),
            word.LEX_TRY_ => lex_handlers.handle_LEX_TRY_(&ctx),
            word.LEX_TRY1 => lex_handlers.handle_LEX_TRY1(&ctx),
            word.LEX_TRY1_ => lex_handlers.handle_LEX_TRY1_(&ctx),
            word.DESTREV => lex_handlers.handle_DESTREV(&ctx),
            word.LEX_COUNT0 => lex_handlers.handle_LEX_COUNT0(&ctx),
            word.LEX_COUNT => lex_handlers.handle_LEX_COUNT(&ctx),
            word.LEX_STRING => lex_handlers.handle_LEX_STRING(&ctx),
            word.LEX_CLASS => lex_handlers.handle_LEX_CLASS(&ctx),
            word.LEX_DOT => lex_handlers.handle_LEX_DOT(&ctx),
            word.LEX_CHAR => lex_handlers.handle_LEX_CHAR(&ctx),
            word.LEX_SEQ => lex_handlers.handle_LEX_SEQ(&ctx),
            word.LEX_OR => lex_handlers.handle_LEX_OR(&ctx),
            word.LEX_RCONTEXT => lex_handlers.handle_LEX_RCONTEXT(&ctx),
            word.LEX_STAR => lex_handlers.handle_LEX_STAR(&ctx),
            word.LEX_OPT => lex_handlers.handle_LEX_OPT(&ctx),

            // IO (io.zig)
            word.READ => io_handlers.handle_READ(&ctx),
            word.READBIN => io_handlers.handle_READBIN(&ctx),
            word.READVALS => io_handlers.handle_READVALS(&ctx),

            else => {
                cycles -= 1;
                if (abnormal(ctx.e)) {
                    word.printErr("\nBLACK HOLE\n", .{});
                    abi.outstats();
                    abi.exit(1);
                }

                switch (getTag(ctx.e)) {
                    word.STRCONS => {
                        ctx.e = pn_val(ctx.e);
                        if (ctx.e == word.UNDEF or ctx.e == word.FREE) {
                            word.printErr("\nimpossible event in reduce - undefined pname\n", .{});
                            abi.exit(1);
                        }
                        ctx.action = word.ACT_NEXTREDEX;
                    },
                    word.DATAPAIR => {
                        upLeft(&ctx);
                        word.printErr("\nUNDEFINED NAME (specified as \"{s}\" in {s})\n", .{@as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(hd_get(hd_get(ctx.e)))))))), @as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(tl_get(ctx.e)))))))});
                        abi.outstats();
                        abi.exit(1);
                    },
                    word.ID => {
                        if (id_val(ctx.e) == word.UNDEF or id_val(ctx.e) == word.FREE) {
                            word.printErr("\nUNDEFINED NAME - {s}\n", .{get_id(ctx.e)});
                            abi.outstats();
                            abi.exit(1);
                        }
                        ctx.e = id_val(ctx.e);
                        ctx.action = word.ACT_NEXTREDEX;
                    },
                    word.CONSTRUCTOR => {
                        while (true) {
                            if (upleft(&ctx)) {
                                ctx.action = word.ACT_DONE;
                                break;
                            }
                        }
                    },
                    word.STARTREADVALS => {
                        io_handlers.handle_STARTREADVALS(&ctx);
                    },
                    word.ATOM, word.INT, word.UNICODE, word.DOUBLE, word.CONS => {
                        ctx.action = word.ACT_DONE;
                    },
                    else => {
                        word.printErr("\nimpossible tag ({}) in reduce\n", .{getTag(ctx.e)});
                        abi.exit(1);
                    },
                }
            },
        }

        if (ctx.action == word.ACT_NEXTREDEX) {
            continue :main_loop;
        }

        while (true) {
            if (ctx.s == abi.BACKSTOP) {
                return ctx.e;
            }

            upRight(&ctx);

            if (is_ap(ctx.e)) {
                downLeft(&ctx);
                downRight(&ctx);
                continue :main_loop;
            }

            ready.handle_ready_state(&ctx);
            if (ctx.action == word.ACT_NEXTREDEX) {
                continue :main_loop;
            }
        }
    }
}
pub extern fn print(e_val: Word) void;
pub extern var waiting: Word;
pub extern var errtrap: Word;
pub extern var s_out: ?*word.FILE;
pub extern fn reduce_badcase_error(arg_info: Word) void;
pub extern fn reduce_conf_error(arg_info: Word) void;
pub extern fn conv_args() Word;
pub extern fn getstring(x: Word, cmd: ?[*:0]const u8) ?[*:0]u8;
pub extern fn head(x_val: Word) Word;
pub extern fn force(x_val: Word) void;

pub inline fn clean_ptr(x: Word) usize {
    return @as(usize, @intCast(x & ~abi.tlptrbits));
}

const heap = @import("../heap.zig");

pub inline fn hd_get(x: Word) Word {
    return heap.heap.h(x & ~abi.tlptrbits);
}

pub inline fn hd_set(x: Word, val: Word) void {
    heap.heap.hp(x & ~abi.tlptrbits).* = val;
}

pub inline fn tl_get(x: Word) Word {
    return heap.heap.t(x & ~abi.tlptrbits);
}

pub inline fn tl_set(x: Word, val: Word) void {
    heap.heap.tp(x & ~abi.tlptrbits).* = val;
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
    ctx.s |= abi.tlptrbit;
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
    ctx.s &= ~abi.tlptrbits;
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
    hd_set(ctx.e, word.I);
    tl_set(ctx.e, r);
    ctx.e = r;
}

pub inline fn abnormal(x: Word) bool {
    return x < 0;
}
pub inline fn is_ap(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.AP;
}
pub inline fn is_num(x: Word) bool {
    if (abnormal(x)) return false;
    const t = getTag(x);
    return t == word.INT or t == word.DOUBLE;
}
pub inline fn is_constructor(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.CONSTRUCTOR;
}
pub inline fn is_int(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.INT;
}
pub inline fn is_double(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.DOUBLE;
}
pub inline fn is_atom(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.ATOM;
}
pub inline fn is_strcons(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.STRCONS;
}
pub inline fn is_id(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.ID;
}
pub inline fn id_val(x: Word) Word {
    return tl_get(x);
}
pub inline fn is_datapair(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.DATAPAIR;
}
pub inline fn is_startreadvals(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.STARTREADVALS;
}
pub inline fn is_cons(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.CONS;
}
pub inline fn is_unicode(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.UNICODE;
}

pub inline fn rewrite_to_value(expr: *Word, value: Word) void {
    hd_set(expr.*, word.I);
    tl_set(expr.*, value);
    expr.* = value;
}

pub inline fn rewrite_to_nil(expr: *Word) void {
    rewrite_to_value(expr, word.NIL);
}

pub inline fn rewrite_to_fail(expr: *Word) void {
    rewrite_to_value(expr, word.FAIL);
}

pub inline fn rewrite_to_failure(expr: *Word) void {
    rewrite_to_value(expr, word.NIL);
}

pub inline fn rewrite_to_cons_head(expr: Word, head_value: Word) void {
    setTag(expr, word.CONS);
    hd_set(expr, head_value);
}

pub inline fn rewrite_to_cons(expr: Word, head_value: Word, tail_value: Word) void {
    setTag(expr, word.CONS);
    hd_set(expr, head_value);
    tl_set(expr, tail_value);
}

pub inline fn rewrite_to_existing_tail(expr: Word) Word {
    hd_set(expr, word.I);
    return tl_get(expr);
}

pub inline fn ap(x: Word, y: Word) Word {
    return abi.make(word.AP, x, y);
}

pub inline fn rewrite_to_match_result(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) == 0) success_value else word.FAIL;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_int_match_result(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (!is_int(value) or abi.bigcmp(literal, value) != 0) word.FAIL else success_value;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_string(expr: *Word, value: [*:0]const u8) void {
    hd_set(expr.*, word.I);
    const val = abi.str_conv(value);
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn cons(x: Word, y: Word) Word {
    return abi.make(word.CONS, x, y);
}

pub inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

pub inline fn neg(x: Word) bool {
    return (hd_get(x) & word.SIGNBIT) != 0;
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

pub fn getStderr() ?*word.FILE {
    const T = @TypeOf(abi.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stderr();
    } else {
        return abi.stderr;
    }
}
pub fn getStdout() ?*word.FILE {
    const T = @TypeOf(abi.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stdout();
    } else {
        return abi.stdout;
    }
}
pub fn getStdin() ?*word.FILE {
    const T = @TypeOf(abi.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stdin();
    } else {
        return abi.stdin;
    }
}

pub inline fn force_dbl(x: Word) f64 {
    if (is_int(x)) {
        return abi.bigtodbl(x);
    } else {
        return abi.get_dbl(x);
    }
}

pub inline fn coerce_dbl(x: Word) Word {
    if (is_double(x)) return x;
    return abi.sto_dbl(abi.bigtodbl(x));
}

pub inline fn rewrite_to_compare_eq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) == 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_neq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) != 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_gt(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) > 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_ge(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) >= 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn bigzero(x: Word) bool {
    return hd_get(x) == 0 and tl_get(x) == 0;
}

pub inline fn getsmallint(x: Word) Word {
    const h_val = hd_get(x);
    return if ((h_val & word.SIGNBIT) != 0) -(h_val & word.MAXDIGIT) else h_val;
}
