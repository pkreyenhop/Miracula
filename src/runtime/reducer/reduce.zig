//! reducer/reduce.zig — the graph-reduction engine (the `reduce()` loop).
//!
//! Miranda programs are compiled to a **combinator graph**: a DAG of binary
//! `AP` (application) cells whose leaves are atoms — the SK-family combinators
//! (`S`/`K`/`I`/`B`/`C`/`Y`/…), built-in operators (`PLUS`, `HD`, `COND`, …),
//! and data cells (`INT`/`DOUBLE`/`CONS`/`CONSTRUCTOR`/…). `reduce(e)` evaluates
//! `e` to **weak head normal form** (WHNF — the outermost constructor/atom is
//! known, arguments may stay unevaluated) by normal-order (lazy) graph
//! reduction, rewriting the graph *in place* so shared sub-expressions are
//! evaluated at most once.
//!
//! **The spine.** The "spine" is the left-ancestor chain of `AP` nodes from the
//! root down to the head atom. Each step the engine unwinds the spine to its
//! head combinator, then applies that combinator's rewrite rule using the
//! argument sub-graphs hanging off the spine's `AP` nodes.
//!
//! **Pointer reversal (no separate stack).** Instead of an explicit spine
//! stack, the engine *reverses the graph pointers* as it descends: each node it
//! enters has its `hd` (or `tl`) rewritten to point back at the parent, so the
//! path back up is recorded in the graph itself and restored on the way up.
//! This is why every `hd`/`tl` access masks `& ~tlptrbits` and why the loop is
//! pure raw-`Word` bit-twiddling — the high bits of the spine word carry control
//! state, not data. The `ReductionCtx` registers:
//!   * `e`     — the node currently in focus (the candidate redex / result).
//!   * `s`     — the reversed-spine pointer (the "stack top"), with a direction
//!               mark in its top bits; `BACKSTOP` (sign bit) marks the bottom.
//!   * `hold`  — scratch used by the three-way pointer swaps.
//!   * `args`  — scratch slots for a combinator's pulled-out arguments.
//!   * `action`— post-dispatch protocol (see below).
//!
//! **The `action` protocol** tells the loop what to do after a handler runs:
//!   * `ACT_NONE`      — fall through to walk back *up* the spine forcing args.
//!   * `ACT_NEXTREDEX` — the redex was rewritten in place; re-examine from `e`.
//!   * `ACT_DONE`      — `e` is in WHNF; pop up the spine seeking the next arg.
//!
//! **Where the rules live.** This file owns the dispatch loop and the traversal
//! primitives; the per-combinator rewrite rules live in `combinators.zig`,
//! `ready.zig`, `lex.zig`, and `io.zig`, which share the machine primitives via
//! `reduce_core.zig`. NB: the `hd_get`/`downLeft`/classifier/`rewrite_to_*`
//! helpers below are duplicated in `reduce_core.zig` (the copy the handlers
//! import); see that file for the canonical set. Keep the two in lock-step.

const std = @import("std");
const word = @import("../word.zig");
const strtab = @import("../strtab.zig");
const core = @import("reduce_core.zig");
inline fn getTag(x: Word) u8 { return core.getTag(x); }
inline fn setTag(x: Word, val: u8) void { core.setTag(x, val); }
const combinators = @import("combinators.zig");
const ready = @import("ready.zig");
const lex_handlers = @import("lex.zig");
const io_handlers = @import("io.zig");
const trace = @import("trace.zig");
const r7_lex = @import("../../parser/lex.zig");
const r7_reduce = @import("../reduce.zig");
const big = @import("../big.zig");
const main_clib = @import("../main_clib.zig");

pub const Word = core.Word;
pub const ReductionCtx = core.ReductionCtx;

// Extern globals referenced by reducer helpers

/// Reduce `e_val` to weak head normal form and return the resulting node.
/// Drives the graph in place; the returned `Word` is the rewritten root.
pub fn reduce(e_val: Word) Word {
    // Fresh machine state. `s = BACKSTOP` is the empty-spine sentinel (its sign
    // bit makes `ctx.s < 0` true, terminating the upward walk).
    var ctx: ReductionCtx = undefined;
    ctx.e = e_val;
    ctx.s = word.BACKSTOP;
    ctx.hold = 0;
    ctx.args[0] = 0;
    ctx.args[1] = 0;
    ctx.args[2] = 0;
    ctx.args[3] = 0;
    ctx.action = word.ACT_NONE;

    main_loop: while (true) {
        // (1) Unwind the left spine: descend through `AP` nodes (reversing
        //     pointers) until `e` is the head atom/combinator/data node.
        while (is_ap(ctx.e)) {
            downLeft(&ctx);
        }

        r7_reduce.ev.cycles += 1; // one reduction step (the perf counter)
        trace.step(ctx.e); // per-combinator histogram (compiled out when off)
        ctx.action = word.ACT_NONE;

        // (2) Dispatch on the head. A bare combinator/operator atom selects a
        //     rewrite handler; anything else falls to the tag switch below.
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

            word.SEQ, word.FORCE, word.HD, word.TL, word.BODY, word.LAST, word.EXEC, word.FILEMODE, word.FILESTAT, word.GETENV, word.INTEGER, word.NUMVAL, word.TAKE, word.STARTREAD, word.STARTREADBIN, word.NB_STARTREAD, word.COND, word.APPEND, word.AND, word.OR, word.NOT, word.NEG, word.CODE, word.DECODE, word.SHOWNUM, word.SHOWHEX, word.SHOWOCT, word.ARCTAN_FN, word.EXP_FN, word.ENTIER_FN, word.LOG_FN, word.LOG10_FN, word.SIN_FN, word.COS_FN, word.SQRT_FN => combinators.handleStrictMonadic(&ctx),

            word.ZIP, word.STEP, word.EQ, word.NEQ, word.PLUS, word.MINUS, word.TIMES, word.INTDIV, word.FDIV, word.MOD, word.GRE, word.GR, word.POWER, word.SHOWSCALED, word.SHOWFLOAT, word.MERGE => combinators.handleStrictDiadic(&ctx),

            word.Ush, word.STEPUNTIL => combinators.handleStrictTriadic(&ctx),

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

            // (2b) Head is not a known combinator atom: it is a data/name node.
            //      Dispatch on its cell tag. (Undo the step count — these are
            //      not combinator reductions; a negative `e` is a corrupt graph.)
            else => {
                r7_reduce.ev.cycles -= 1;
                if (abnormal(ctx.e)) {
                    word.printErr("\nBLACK HOLE\n", .{});
                    r7_reduce.outstats();
                    main_clib.exit(1);
                }

                switch (getTag(ctx.e)) {
                    // A private-name placeholder: chase to its bound value.
                    word.STRCONS => {
                        ctx.e = pnVal(ctx.e);
                        if (ctx.e == word.UNDEF or ctx.e == word.FREE) {
                            word.printErr("\nimpossible event in reduce - undefined pname\n", .{});
                            main_clib.exit(1);
                        }
                        ctx.action = word.ACT_NEXTREDEX;
                    },
                    word.DATAPAIR => {
                        upLeft(&ctx);
                        word.printErr("\nUNDEFINED NAME (specified as \"{s}\" in {s})\n", .{strtab.strOf(hd_get(hd_get(ctx.e))), strtab.strOf(tl_get(ctx.e))});
                        r7_reduce.outstats();
                        main_clib.exit(1);
                    },
                    // A defined name: substitute its value and re-examine.
                    word.ID => {
                        if (idVal(ctx.e) == word.UNDEF or idVal(ctx.e) == word.FREE) {
                            word.printErr("\nUNDEFINED NAME - {s}\n", .{get_id(ctx.e)});
                            r7_reduce.outstats();
                            main_clib.exit(1);
                        }
                        ctx.e = idVal(ctx.e);
                        ctx.action = word.ACT_NEXTREDEX;
                    },
                    // A saturated constructor application is already WHNF: pop
                    // the whole spine back to the root, then we are done.
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
                    // Already a head-normal value (data leaf): nothing to rewrite.
                    word.ATOM, word.INT, word.UNICODE, word.DOUBLE, word.CONS => {
                        ctx.action = word.ACT_DONE;
                    },
                    else => {
                        word.printErr("\nimpossible tag ({}) in reduce\n", .{getTag(ctx.e)});
                        main_clib.exit(1);
                    },
                }
            },
        }

        // A handler rewrote the redex in place and wants it re-examined.
        if (ctx.action == word.ACT_NEXTREDEX) {
            continue :main_loop;
        }

        // (3) `e` is in WHNF. Walk back *up* the spine, restoring reversed
        //     pointers. At each `AP` we ascended through, force its right
        //     argument (descend into it) so strict operators find their
        //     operands ready; `ready.handleReadyState` applies the pending
        //     rule once an argument has been reduced. Stop at `BACKSTOP`.
        while (true) {
            if (ctx.s == word.BACKSTOP) {
                return ctx.e;
            }

            upRight(&ctx);

            if (is_ap(ctx.e)) {
                downLeft(&ctx);
                downRight(&ctx);
                continue :main_loop;
            }

            ready.handleReadyState(&ctx);
            if (ctx.action == word.ACT_NEXTREDEX) {
                continue :main_loop;
            }
        }
    }
}
pub const print = r7_reduce.print;
pub const badcaseError = r7_reduce.badcaseError;
pub const confError = r7_reduce.confError;
pub const convArgs = r7_lex.convArgs;
pub const getstring = r7_reduce.getstring;
pub const head = r7_reduce.head;
pub const force = r7_reduce.force;

pub inline fn clean_ptr(x: Word) usize {
    return @as(usize, @intCast(x & ~word.tlptrbits));
}

const heap = @import("../heap.zig");

// --- Cell access through the spine word --------------------------------------
// A spine word may carry direction bits in its top two bits (`tlptrbits`), so
// every access masks them off before indexing the heap. These mirror
// `reduce_core.zig`; keep both in sync.

pub inline fn hd_get(x: Word) Word {
    return heap.heap.h(x & ~word.tlptrbits);
}

pub inline fn hd_set(x: Word, val: Word) void {
    heap.heap.hp(x & ~word.tlptrbits).* = val;
}

pub inline fn tl_get(x: Word) Word {
    return heap.heap.t(x & ~word.tlptrbits);
}

pub inline fn tl_set(x: Word, val: Word) void {
    heap.heap.tp(x & ~word.tlptrbits).* = val;
}

// --- Pointer-reversal traversal (matches the C reducer exactly) ---------------
// Each `downX` step makes `e` the child and `s` the (reversed) parent, storing
// the old `s` back into the node so the matching `upX` can restore it. The
// lowercase wrappers (`downright`/`upleft`) first test `s < 0` (the BACKSTOP /
// bottom-of-spine sentinel) and report it rather than walking off the bottom.

/// Descend into the head: push `e` onto the spine and follow its `hd`, leaving a
/// back-link (old `s`) in the node's `hd`.
pub inline fn downLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = ctx.e;
    ctx.e = hd_get(ctx.e);
    hd_set(ctx.s, ctx.hold);
}

/// Descend into the tail of the current spine node, marking it (`tlptrbit`) so
/// `upRight` knows this node was entered via its `tl`.
pub inline fn downRight(ctx: *ReductionCtx) void {
    ctx.hold = hd_get(ctx.s);
    hd_set(ctx.s, ctx.e);
    ctx.e = tl_get(ctx.s);
    tl_set(ctx.s, ctx.hold);
    ctx.s |= word.tlptrbit;
}

pub inline fn downright(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    downRight(ctx);
    return false;
}

/// Ascend one `hd` link: restore the parent and make the just-visited node the
/// new focus. Inverse of `downLeft`.
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

/// Ascend one `tl` link (clearing the direction mark), restoring the node's
/// `hd`/`tl` and bringing the parent back into focus. Inverse of `downRight`.
pub inline fn upRight(ctx: *ReductionCtx) void {
    ctx.s &= ~word.tlptrbits;
    ctx.hold = tl_get(ctx.s);
    tl_set(ctx.s, ctx.e);
    ctx.e = hd_get(ctx.s);
    hd_set(ctx.s, ctx.hold);
}

/// Pull the next argument off the spine into `a` (ascend one `AP`, read its
/// `tl`). `getarg` reports hitting the bottom of the spine instead.
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

/// Overwrite the redex `e` with an indirection (`I r`) to the result `r` and
/// make `r` the new focus — the in-place rewrite that gives lazy sharing.
pub inline fn simpl(ctx: *ReductionCtx, r: Word) void {
    hd_set(ctx.e, word.I);
    tl_set(ctx.e, r);
    ctx.e = r;
}

// --- Node classifiers --------------------------------------------------------
// A negative `Word` is never a valid cell handle (it is a marked spine word or
// the BACKSTOP sentinel), so every predicate guards with `!abnormal(x)` before
// reading the tag.

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
pub inline fn idVal(x: Word) Word {
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

// --- In-place rewrites -------------------------------------------------------
// Handlers finish by overwriting the redex with their result. `rewrite_to_value`
// installs an `I value` indirection (shared); the `rewrite_to_cons*` variants
// re-tag the redex cell directly; the `rewrite_to_compare_*` ones fold a
// comparison to a boolean. All leave the redex pointing at the new value.

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
    return heap.make(word.AP, x, y);
}

pub inline fn rewrite_to_match_result(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (r7_reduce.compare(left, right) == 0) success_value else word.FAIL;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_int_match_result(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (!is_int(value) or big.cmp(literal, value) != 0) word.FAIL else success_value;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_string(expr: *Word, value: [*:0]const u8) void {
    hd_set(expr.*, word.I);
    const val = r7_lex.strConv(value);
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn cons(x: Word, y: Word) Word {
    return heap.make(word.CONS, x, y);
}

pub inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

// --- Number / name field accessors -------------------------------------------
// A bignum is a chain of `INT` cells; the sign lives in `SIGNBIT` of the leading
// digit. `neg`/`poz` test it; `getsmallint`/`force_dbl`/`coerce_dbl` decode a
// value; `pnVal`/`get_id`/`constr_name` read name-node fields.

pub inline fn neg(x: Word) bool {
    return (hd_get(x) & word.SIGNBIT) != 0;
}
pub inline fn poz(x: Word) bool {
    return !neg(x);
}
pub inline fn pnVal(x: Word) Word {
    return tl_get(x);
}
pub inline fn get_id(x: Word) [*:0]const u8 {
    return strtab.strOf(hd_get(hd_get(hd_get(x))));
}
pub inline fn constr_name(x: Word) [*:0]const u8 {
    const tlx = tl_get(x);
    if (is_id(tlx)) {
        return get_id(tlx);
    } else {
        return get_id(pnVal(tlx));
    }
}
pub inline fn suppressed(x: Word) bool {
    const tlx = tl_get(x);
    return is_strcons(tlx) and !is_id(pnVal(tlx));
}

pub fn getStderr() ?*word.FILE {
    const T = @TypeOf(main_clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stderr();
    } else {
        return main_clib.stderr;
    }
}
pub fn getStdout() ?*word.FILE {
    const T = @TypeOf(main_clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdout();
    } else {
        return main_clib.stdout;
    }
}
pub fn getStdin() ?*word.FILE {
    const T = @TypeOf(main_clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdin();
    } else {
        return main_clib.stdin;
    }
}

pub inline fn force_dbl(x: Word) f64 {
    if (is_int(x)) {
        return big.toFloat(x);
    } else {
        return heap.getDbl(x);
    }
}

pub inline fn coerce_dbl(x: Word) Word {
    if (is_double(x)) return x;
    return heap.stoDbl(big.toFloat(x));
}

pub inline fn rewrite_to_compare_eq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (r7_reduce.compare(left, right) == 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_neq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (r7_reduce.compare(left, right) != 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_gt(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (r7_reduce.compare(left, right) > 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_ge(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (r7_reduce.compare(left, right) >= 0) word.True else word.False;
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
